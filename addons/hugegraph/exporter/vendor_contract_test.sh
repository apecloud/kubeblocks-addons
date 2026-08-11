#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GO_BIN=${GO_BIN:-/opt/homebrew/opt/go@1.22/bin/go}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

manifest_for() {
  local vendor_dir=$1
  (
    cd "$vendor_dir"
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
  )
}

verify_manifest() {
  local vendor_dir=$1
  local manifest=$2
  manifest_for "$vendor_dir" | diff -q - "$manifest" >/dev/null
}

[[ -x "$GO_BIN" ]] || fail "Go 1.22 binary missing"
[[ "$($GO_BIN version)" == go\ version\ go1.22.12\ * ]] || fail "Go version is not 1.22.12"
[[ -d "$ROOT/vendor" ]] || fail "vendor directory missing"
verify_manifest "$ROOT/vendor" "$ROOT/vendor.manifest.sha256" || fail "vendor manifest mismatch"

assert_docker_count() {
  local want=$1
  local pattern=$2
  local got
  got=$(grep -F -c -- "$pattern" "$ROOT/Dockerfile" || true)
  [[ "$got" == "$want" ]] || fail "Dockerfile count for $pattern: want $want, got $got"
}

assert_docker_count 1 'FROM golang:1.22.12-alpine3.21 AS builder'
assert_docker_count 1 'FROM gcr.io/distroless/static-debian12:nonroot'
assert_docker_count 1 'COPY vendor ./vendor'
assert_docker_count 2 'RUN --network=none'
assert_docker_count 2 '-mod=vendor'
assert_docker_count 1 'CGO_ENABLED=0 GOOS=linux'
assert_docker_count 1 'ENTRYPOINT ["/hugegraph-exporter"]'
if rg -n 'go mod download|GOPROXY=|GONOSUMDB=|curl |wget ' "$ROOT/Dockerfile" >/dev/null; then
  fail "Dockerfile retains a network dependency path"
fi

if find "$ROOT/vendor" -type d \( -name .git -o -name .hg -o -name .svn -o -name .bzr \) -print -quit | grep -q .; then
  fail "vendor contains a VCS directory"
fi
if find "$ROOT/vendor" -type f \( -name '*.lock' -o -name '*.tmp' -o -name '*.swp' \) -print -quit | grep -q .; then
  fail "vendor contains lock or temporary files"
fi
if find "$ROOT/vendor" -path '*/sumdb/*' -print -quit | grep -q .; then
  fail "vendor contains sumdb state"
fi
if rg -n '/Users/|/home/[^/]+/|\.cache/go-build|pkg/mod/cache|BEGIN .*PRIVATE KEY' \
  "$ROOT/vendor" "$ROOT/vendor.manifest.sha256" >/dev/null; then
  fail "vendor contains a local path or credential-shaped block"
fi

while IFS= read -r module; do
  find "$ROOT/vendor/$module" -maxdepth 1 -type f -iname 'license*' -print -quit 2>/dev/null | grep -q . \
    || fail "vendored module lacks a license file: $module"
done < <(awk '/^# /{print $2}' "$ROOT/vendor/modules.txt")

(
  cd "$ROOT"
  env PATH="$(dirname "$GO_BIN"):$PATH" GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off \
    "$GO_BIN" mod vendor -o "$TMP/regenerated"
)
verify_manifest "$TMP/regenerated" "$ROOT/vendor.manifest.sha256" || fail "go mod vendor is not reproducible"

fresh_env=(
  env
  PATH="$(dirname "$GO_BIN"):$PATH"
  GOTOOLCHAIN=local
  GOPROXY=off
  GOSUMDB=off
  GOMODCACHE="$TMP/modcache"
  GOCACHE="$TMP/gocache"
)
(
  cd "$ROOT"
  "${fresh_env[@]}" "$GO_BIN" list -mod=vendor all >/dev/null
  "${fresh_env[@]}" "$GO_BIN" test -mod=vendor -ldflags=-linkmode=external ./...
  "${fresh_env[@]}" "$GO_BIN" test -race -mod=vendor -ldflags=-linkmode=external ./...
  "${fresh_env[@]}" "$GO_BIN" vet -mod=vendor ./...
  "${fresh_env[@]}" CGO_ENABLED=0 GOOS=linux GOARCH=amd64 "$GO_BIN" build \
    -mod=vendor -trimpath -ldflags="-s -w" -o "$TMP/hugegraph-exporter" ./cmd/hugegraph-exporter
)
file "$TMP/hugegraph-exporter" | rg -n 'ELF 64-bit.*x86-64.*statically linked.*stripped' >/dev/null \
  || fail "network-off vendor build did not produce the expected linux/amd64 binary"

cp -R "$ROOT/." "$TMP/missing-file"
rm "$TMP/missing-file/vendor/github.com/prometheus/client_golang/prometheus/collector.go"
if (cd "$TMP/missing-file" && "${fresh_env[@]}" "$GO_BIN" test -mod=vendor ./...) >/dev/null 2>&1; then
  fail "missing vendor file mutant survived"
fi

cp "$ROOT/vendor.manifest.sha256" "$TMP/bad-manifest"
perl -pi -e 'if ($. == 1) { s/^[0-9a-f]{64}/"0" x 64/e }' "$TMP/bad-manifest"
if verify_manifest "$ROOT/vendor" "$TMP/bad-manifest"; then
  fail "vendor hash mutant survived"
fi

cp "$ROOT/Dockerfile" "$TMP/proxy-Dockerfile"
printf '\nRUN go mod download\n' >>"$TMP/proxy-Dockerfile"
rg -n 'go mod download' "$TMP/proxy-Dockerfile" >/dev/null || fail "proxy mutant was not detected"

if command -v trivy >/dev/null 2>&1; then
  trivy fs --scanners secret --exit-code 1 --no-progress "$ROOT/vendor" >/dev/null
fi

printf 'PASS: hermetic vendor contract\n'
