#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

mkdir -p "${TMP_ROOT}/bin" "${TMP_ROOT}/store"

cat > "${TMP_ROOT}/bin/mc" <<'SH'
#!/bin/sh
set -eu

log="${FAKE_MC_LOG:?missing FAKE_MC_LOG}"
echo "mc $*" >> "${log}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --insecure) shift ;;
    --config-dir) shift 2 ;;
    *) break ;;
  esac
done

case "$1" in
  alias)
    endpoint="$4"
    printf '%s\n' "${endpoint}" > "${FAKE_MC_ALIAS_FILE:?missing FAKE_MC_ALIAS_FILE}"
    exit 0 ;;
  ls)
    if [ "${FAKE_FORCE_HTTPS:-}" = "1" ]; then
      case "$(cat "${FAKE_MC_ALIAS_FILE}")" in
        http://*)
          echo "fake http read probe rejected" >&2
          exit 1 ;;
      esac
    fi
    echo '2026-07-03 00:00:00 UTC a/'
    exit 0 ;;
  find)
    target="$2"
    case "${target}" in
      rustfs*) echo 'rustfs/a/hello.txt' ;;
      */rustfs-backup/objects)
        echo "${target}"
        echo "${target}/a"
        echo "${target}/a/hello.txt" ;;
      */rustfs-restore/objects)
        echo "${target}"
        echo "${target}/a"
        echo "${target}/a/hello.txt" ;;
    esac
    exit 0 ;;
  mirror)
    src="$3"
    dst="$4"
    case "${src}" in
      rustfs/*|rustfs)
        mkdir -p "${dst}/a"
        printf hello > "${dst}/a/hello.txt" ;;
    esac
    exit 0 ;;
  mb)
    exit 0 ;;
  *)
    echo "unexpected mc command: $*" >&2
    exit 2 ;;
esac
SH

cat > "${TMP_ROOT}/bin/datasafed" <<'SH'
#!/bin/sh
set -eu

store="${FAKE_STORE:?missing FAKE_STORE}"
cmd="$1"
shift

case "${cmd}" in
  push)
    src="$1"
    dest="$2"
    dest_path="${store}/${dest}"
    mkdir -p "$(dirname "${dest_path}")"
    cp "${src}" "${dest_path}" ;;
  stat)
    echo "TotalSize: 11" ;;
  list)
    if [ "${1:-}" = "-f" ]; then
      shift 2
      prefix="$1"
      find "${store}/${prefix}" -type f | while IFS= read -r f; do
        printf '%s\n' "${f#"${store}"/}"
      done
    else
      name="$1"
      [ -f "${store}/${name}" ] && echo "${name}"
    fi ;;
  pull)
    src="$1"
    dest="$2"
    mkdir -p "$(dirname "${dest}")"
    cp "${store}/${src}" "${dest}" ;;
  *)
    echo "unexpected datasafed command: ${cmd}" >&2
    exit 2 ;;
esac
SH

chmod +x "${TMP_ROOT}/bin/mc" "${TMP_ROOT}/bin/datasafed"

export PATH="${TMP_ROOT}/bin:${PATH}"
export FAKE_STORE="${TMP_ROOT}/store"
export FAKE_MC_LOG="${TMP_ROOT}/mc.log"
export FAKE_MC_ALIAS_FILE="${TMP_ROOT}/mc-alias-endpoint"
export FAKE_FORCE_HTTPS=1
export DP_BACKUP_BASE_PATH=/fake/base
export DP_BACKUP_INFO_FILE="${TMP_ROOT}/backup-info.json"
export DP_BACKUP_NAME=rustfs-test
export DP_DB_HOST=rustfs-0.rustfs-headless.demo.svc
export DP_DB_PORT=9000
export DP_DB_USER=root
export DP_DB_PASSWORD=secret
export RUSTFS_MC_IMAGE=docker.io/minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727
export TMPDIR="${TMP_ROOT}/tmp"
mkdir -p "${TMPDIR}"

(
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/backup.sh"
)

(
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/restore.sh"
)

[ -f "${FAKE_STORE}/rustfs-test/buckets.txt" ] || {
  echo "missing buckets.txt artifact" >&2
  exit 1
}
[ -f "${FAKE_STORE}/rustfs-test/objects.txt" ] || {
  echo "missing objects.txt artifact" >&2
  exit 1
}
[ -f "${FAKE_STORE}/rustfs-test/manifest.txt" ] || {
  echo "missing manifest.txt artifact" >&2
  exit 1
}
[ -f "${FAKE_STORE}/rustfs-test/objects/a/hello.txt" ] || {
  echo "missing object artifact" >&2
  exit 1
}
[ "$(cat "${DP_BACKUP_INFO_FILE}")" = '{"totalSize":"11"}' ] || {
  echo "unexpected backup info: $(cat "${DP_BACKUP_INFO_FILE}")" >&2
  exit 1
}

grep -q '^formatVersion=rustfs-s3-full.v1$' "${FAKE_STORE}/rustfs-test/manifest.txt" || {
  echo "manifest formatVersion missing" >&2
  exit 1
}
grep -q '^method=s3-full$' "${FAKE_STORE}/rustfs-test/manifest.txt" || {
  echo "manifest method missing" >&2
  exit 1
}
grep -q '^bucketCount=1$' "${FAKE_STORE}/rustfs-test/manifest.txt" || {
  echo "manifest bucket count missing" >&2
  exit 1
}
grep -q '^objectCount=1$' "${FAKE_STORE}/rustfs-test/manifest.txt" || {
  echo "manifest object count missing" >&2
  exit 1
}
grep -q '^bucket:a$' "${FAKE_STORE}/rustfs-test/manifest.txt" || {
  echo "manifest bucket list missing" >&2
  exit 1
}
grep -q '^object:a/hello.txt$' "${FAKE_STORE}/rustfs-test/manifest.txt" || {
  echo "manifest object list missing" >&2
  exit 1
}
grep -q '^endpointScheme=https$' "${FAKE_STORE}/rustfs-test/manifest.txt" || {
  echo "manifest endpoint scheme did not record https fallback" >&2
  exit 1
}

grep -q 'mirror --overwrite rustfs/' "${FAKE_MC_LOG}" || {
  echo "backup mirror command was not called" >&2
  exit 1
}
grep -q 'mb --ignore-existing rustfs/a' "${FAKE_MC_LOG}" || {
  echo "restore bucket creation command was not called" >&2
  exit 1
}
grep -q 'mirror --overwrite .*/rustfs-restore/objects rustfs/' "${FAKE_MC_LOG}" || {
  echo "restore mirror command was not called" >&2
  exit 1
}
grep -q 'alias set rustfs https://rustfs-0.rustfs-headless.demo.svc:9000' "${FAKE_MC_LOG}" || {
  echo "https alias fallback was not exercised" >&2
  exit 1
}

rm -f "${FAKE_STORE}/rustfs-test/objects/a/hello.txt"
if (
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/restore.sh"
); then
  echo "restore succeeded despite missing object artifact" >&2
  exit 1
fi

echo "rustfs backup/restore contract test passed"
