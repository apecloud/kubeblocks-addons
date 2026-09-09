#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run Redis client compatibility checks against Redis twemproxy and syncer Fake Sentinel.

Usage:
  client_compatibility.sh --namespace <ns> --cluster <cluster> [options]

Options:
  --namespace <ns>              Kubernetes namespace.
  --cluster <name>              KubeBlocks Cluster name.
  --mode <all|twemproxy|sentinel>
                                Test scope. Default: all.
  --twemproxy-host <host>       Twemproxy service host.
                                Default: <cluster>-redis-twemproxy-twemproxy.
  --twemproxy-port <port>       Twemproxy service port. Default: 22121.
  --sentinel-host <host>        syncer Fake Sentinel service host.
                                Default: <cluster>-redis-redis-syncer-sentinel.
  --sentinel-port <port>        syncer Fake Sentinel service port. Default: 26379.
  --master-name <name>          Sentinel master name.
                                Default: <cluster>-redis.
  --password-secret <secret>    Redis default account secret.
                                Default: <cluster>-redis-account-default.
  --password-key <key>          Password key in secret. Default: password.
  --timeout <seconds>           Per job timeout. Default: 180.
  --keep-jobs                   Do not delete completed test jobs.

What it covers:
  - Twemproxy direct access: redis-cli, redis-py, ioredis, go-redis.
  - Fake Sentinel discovery + master write: redis-cli, redis-py Sentinel,
    ioredis Sentinel, go-redis FailoverClient.

Examples:
  ./examples/redis/test/client_compatibility.sh \
    --namespace redis-twemproxy-syncer --cluster k2so-rt

  ./examples/redis/test/client_compatibility.sh \
    --namespace redis-ti-r2 --cluster r2ti --mode sentinel
EOF
}

NAMESPACE=""
CLUSTER=""
MODE="all"
TWEMPROXY_HOST=""
TWEMPROXY_PORT="22121"
SENTINEL_HOST=""
SENTINEL_PORT="26379"
MASTER_NAME=""
PASSWORD_SECRET=""
PASSWORD_KEY="password"
TIMEOUT_SECONDS="180"
KEEP_JOBS="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --namespace)
      NAMESPACE="$2"; shift 2 ;;
    --cluster)
      CLUSTER="$2"; shift 2 ;;
    --mode)
      MODE="$2"; shift 2 ;;
    --twemproxy-host)
      TWEMPROXY_HOST="$2"; shift 2 ;;
    --twemproxy-port)
      TWEMPROXY_PORT="$2"; shift 2 ;;
    --sentinel-host)
      SENTINEL_HOST="$2"; shift 2 ;;
    --sentinel-port)
      SENTINEL_PORT="$2"; shift 2 ;;
    --master-name)
      MASTER_NAME="$2"; shift 2 ;;
    --password-secret)
      PASSWORD_SECRET="$2"; shift 2 ;;
    --password-key)
      PASSWORD_KEY="$2"; shift 2 ;;
    --timeout)
      TIMEOUT_SECONDS="$2"; shift 2 ;;
    --keep-jobs)
      KEEP_JOBS="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

if [ -z "$NAMESPACE" ] || [ -z "$CLUSTER" ]; then
  usage >&2
  exit 2
fi

case "$MODE" in
  all|twemproxy|sentinel) ;;
  *)
    echo "invalid --mode: $MODE" >&2
    exit 2 ;;
esac

TWEMPROXY_HOST="${TWEMPROXY_HOST:-${CLUSTER}-redis-twemproxy-twemproxy}"
SENTINEL_HOST="${SENTINEL_HOST:-${CLUSTER}-redis-redis-syncer-sentinel}"
PASSWORD_SECRET="${PASSWORD_SECRET:-${CLUSTER}-redis-account-default}"
MASTER_NAME="${MASTER_NAME:-${CLUSTER}-redis}"
RUN_ID="$(date +%Y%m%d%H%M%S)-$RANDOM"
JOB_PREFIX="redis-client-compat-$RUN_ID"
WORK_DIR="$(mktemp -d)"
FAILED_CLIENTS=""

cleanup() {
  rm -rf "$WORK_DIR"
  if [ "$KEEP_JOBS" != "true" ]; then
    kubectl -n "$NAMESPACE" delete job -l "redis-client-compat-run=$RUN_ID" --ignore-not-found >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wait_job() {
  local job="$1"
  local log_file="${WORK_DIR}/${job}.log"

  echo "==> waiting for $job"
  if ! kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$job" --timeout="${TIMEOUT_SECONDS}s"; then
    echo "job $job did not complete; collecting logs and status" >&2
    kubectl -n "$NAMESPACE" get job "$job" -o wide >&2 || true
    kubectl -n "$NAMESPACE" describe job "$job" >&2 || true
    kubectl -n "$NAMESPACE" logs "job/$job" --all-containers=true --tail=-1 >&2 || true
    return 1
  fi

  kubectl -n "$NAMESPACE" logs "job/$job" --all-containers=true --tail=-1 | tee "$log_file"
}

apply_job() {
  local job="$1"
  local image="$2"
  local script="$3"

  kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job}
  labels:
    redis-client-compat-run: "${RUN_ID}"
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        redis-client-compat-run: "${RUN_ID}"
    spec:
      restartPolicy: Never
      containers:
        - name: client
          image: ${image}
          imagePullPolicy: IfNotPresent
          env:
            - name: TWEMPROXY_HOST
              value: "${TWEMPROXY_HOST}"
            - name: TWEMPROXY_PORT
              value: "${TWEMPROXY_PORT}"
            - name: SENTINEL_HOST
              value: "${SENTINEL_HOST}"
            - name: SENTINEL_PORT
              value: "${SENTINEL_PORT}"
            - name: MASTER_NAME
              value: "${MASTER_NAME}"
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "${PASSWORD_SECRET}"
                  key: "${PASSWORD_KEY}"
            - name: TEST_TWEMPROXY
              value: "${TEST_TWEMPROXY}"
            - name: TEST_SENTINEL
              value: "${TEST_SENTINEL}"
          command:
            - /bin/sh
            - -ec
          args:
            - |
$(sed 's/^/              /' "$script")
EOF
}

create_redis_cli_script() {
  local file="$1"
  cat > "$file" <<'EOF'
key="kb:compat:redis-cli:$(date +%s)"
if [ "${TEST_TWEMPROXY:-true}" = "true" ]; then
  redis-cli -h "$TWEMPROXY_HOST" -p "$TWEMPROXY_PORT" -a "$REDIS_PASSWORD" --no-auth-warning SET "$key:tw" "twemproxy-ok"
  value="$(redis-cli -h "$TWEMPROXY_HOST" -p "$TWEMPROXY_PORT" -a "$REDIS_PASSWORD" --no-auth-warning GET "$key:tw")"
  test "$value" = "twemproxy-ok"
  echo "redis-cli twemproxy OK"
fi

if [ "${TEST_SENTINEL:-true}" = "true" ]; then
  master="$(redis-cli -h "$SENTINEL_HOST" -p "$SENTINEL_PORT" --raw SENTINEL get-master-addr-by-name "$MASTER_NAME" | tr '\n' ' ')"
  set -- $master
  host="$1"
  port="$2"
  test -n "$host"
  test -n "$port"
  redis-cli -h "$host" -p "$port" -a "$REDIS_PASSWORD" --no-auth-warning SET "$key:sentinel" "sentinel-ok"
  value="$(redis-cli -h "$host" -p "$port" -a "$REDIS_PASSWORD" --no-auth-warning GET "$key:sentinel")"
  test "$value" = "sentinel-ok"
  echo "redis-cli fake sentinel OK: $host:$port"
fi
EOF
}

create_python_script() {
  local file="$1"
  cat > "$file" <<'EOF'
pip install --quiet 'redis>=5,<6'
python - <<'PY'
import os
import time
import redis
from redis.sentinel import Sentinel

key = f"kb:compat:redis-py:{int(time.time())}"

if os.environ.get("TEST_TWEMPROXY", "true") == "true":
    r = redis.Redis(
        host=os.environ["TWEMPROXY_HOST"],
        port=int(os.environ["TWEMPROXY_PORT"]),
        password=os.environ["REDIS_PASSWORD"],
        socket_connect_timeout=10,
        socket_timeout=10,
        decode_responses=True,
    )
    r.set(key + ":tw", "twemproxy-ok")
    assert r.get(key + ":tw") == "twemproxy-ok"
    print("redis-py twemproxy OK")

if os.environ.get("TEST_SENTINEL", "true") == "true":
    sentinel = Sentinel(
        [(os.environ["SENTINEL_HOST"], int(os.environ["SENTINEL_PORT"]))],
        socket_timeout=10,
        decode_responses=True,
    )
    master = sentinel.master_for(
        os.environ.get("MASTER_NAME", "redis"),
        password=os.environ["REDIS_PASSWORD"],
        socket_timeout=10,
        decode_responses=True,
    )
    master.set(key + ":sentinel", "sentinel-ok")
    assert master.get(key + ":sentinel") == "sentinel-ok"
    print("redis-py fake sentinel OK")
PY
EOF
}

create_node_script() {
  local file="$1"
  cat > "$file" <<'EOF'
cd /tmp
npm init -y >/dev/null
npm install ioredis@5
node - <<'NODE'
const Redis = require("ioredis");
const key = `kb:compat:ioredis:${Date.now()}`;

async function main() {
  if (process.env.TEST_TWEMPROXY !== "false") {
    const direct = new Redis({
      host: process.env.TWEMPROXY_HOST,
      port: Number(process.env.TWEMPROXY_PORT),
      password: process.env.REDIS_PASSWORD,
      lazyConnect: true,
      connectTimeout: 10000,
      maxRetriesPerRequest: 1,
    });
    await direct.connect();
    await direct.set(`${key}:tw`, "twemproxy-ok");
    const value = await direct.get(`${key}:tw`);
    if (value !== "twemproxy-ok") throw new Error(`bad twemproxy value: ${value}`);
    await direct.quit();
    console.log("ioredis twemproxy OK");
  }

  if (process.env.TEST_SENTINEL !== "false") {
    const sentinel = new Redis({
      sentinels: [{ host: process.env.SENTINEL_HOST, port: Number(process.env.SENTINEL_PORT) }],
      name: process.env.MASTER_NAME || "redis",
      password: process.env.REDIS_PASSWORD,
      sentinelRetryStrategy: (times) => (times > 1 ? null : 100),
      connectTimeout: 10000,
      maxRetriesPerRequest: 1,
    });
    sentinel.on("error", (err) => console.error("ioredis error", err));
    await sentinel.set(`${key}:sentinel`, "sentinel-ok");
    const value = await sentinel.get(`${key}:sentinel`);
    if (value !== "sentinel-ok") throw new Error(`bad sentinel value: ${value}`);
    await sentinel.quit();
    console.log("ioredis fake sentinel OK");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
NODE
EOF
}

create_go_script() {
  local file="$1"
  cat > "$file" <<'EOF'
mkdir -p /tmp/redis-client-compat
cd /tmp/redis-client-compat
cat > go.mod <<'GOMOD'
module redis-client-compat

go 1.24

require github.com/redis/go-redis/v9 v9.12.1
GOMOD

cat > main.go <<'GO'
package main

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

func mustPort(name string) int {
	v, err := strconv.Atoi(os.Getenv(name))
	if err != nil {
		panic(err)
	}
	return v
}

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	key := fmt.Sprintf("kb:compat:go-redis:%d", time.Now().UnixNano())

	if os.Getenv("TEST_TWEMPROXY") != "false" {
		direct := redis.NewClient(&redis.Options{
			Addr:     fmt.Sprintf("%s:%d", os.Getenv("TWEMPROXY_HOST"), mustPort("TWEMPROXY_PORT")),
			Password: os.Getenv("REDIS_PASSWORD"),
		})
		if err := direct.Set(ctx, key+":tw", "twemproxy-ok", 0).Err(); err != nil {
			panic(err)
		}
		value, err := direct.Get(ctx, key+":tw").Result()
		if err != nil || value != "twemproxy-ok" {
			panic(fmt.Sprintf("bad twemproxy value=%q err=%v", value, err))
		}
		_ = direct.Close()
		fmt.Println("go-redis twemproxy OK")
	}

	if os.Getenv("TEST_SENTINEL") != "false" {
		failover := redis.NewFailoverClient(&redis.FailoverOptions{
			MasterName:    os.Getenv("MASTER_NAME"),
			SentinelAddrs: []string{fmt.Sprintf("%s:%d", os.Getenv("SENTINEL_HOST"), mustPort("SENTINEL_PORT"))},
			Password:      os.Getenv("REDIS_PASSWORD"),
		})
		if err := failover.Set(ctx, key+":sentinel", "sentinel-ok", 0).Err(); err != nil {
			panic(err)
		}
		value, err := failover.Get(ctx, key+":sentinel").Result()
		if err != nil || value != "sentinel-ok" {
			panic(fmt.Sprintf("bad sentinel value=%q err=%v", value, err))
		}
		_ = failover.Close()
		fmt.Println("go-redis fake sentinel OK")
	}
}
GO

go mod tidy
go run .
EOF
}

run_client() {
  local name="$1"
  local image="$2"
  local script="$3"
  local job="${JOB_PREFIX}-${name}"

  apply_job "$job" "$image" "$script"
  if wait_job "$job"; then
    echo "PASS $name"
  else
    echo "FAIL $name" >&2
    FAILED_CLIENTS="${FAILED_CLIENTS} ${name}"
  fi
}

if [ "$MODE" = "twemproxy" ]; then
  export TEST_TWEMPROXY="true"
  export TEST_SENTINEL="false"
elif [ "$MODE" = "sentinel" ]; then
  export TEST_TWEMPROXY="false"
  export TEST_SENTINEL="true"
else
  export TEST_TWEMPROXY="true"
  export TEST_SENTINEL="true"
fi

echo "namespace=$NAMESPACE cluster=$CLUSTER mode=$MODE"
echo "twemproxy=${TWEMPROXY_HOST}:${TWEMPROXY_PORT}"
echo "fake-sentinel=${SENTINEL_HOST}:${SENTINEL_PORT} master-name=${MASTER_NAME}"

redis_cli_script="${WORK_DIR}/redis-cli.sh"
python_script="${WORK_DIR}/redis-py.sh"
node_script="${WORK_DIR}/ioredis.sh"
go_script="${WORK_DIR}/go-redis.sh"

create_redis_cli_script "$redis_cli_script"
create_python_script "$python_script"
create_node_script "$node_script"
create_go_script "$go_script"

run_client "redis-cli" "redis:7-alpine" "$redis_cli_script"
run_client "redis-py" "python:3.12-alpine" "$python_script"
run_client "ioredis" "node:20-alpine" "$node_script"
run_client "go-redis" "golang:1.24-alpine" "$go_script"

if [ -n "$FAILED_CLIENTS" ]; then
  echo "failed Redis client compatibility checks:${FAILED_CLIENTS}" >&2
  exit 1
fi

echo "all selected Redis client compatibility checks passed"
