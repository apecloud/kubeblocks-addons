#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
REAL_CP_BIN="$(command -v cp)"
export REAL_CP_BIN

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

config_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --insecure)
      if [ "${FAKE_REJECT_INSECURE:-}" = "1" ]; then
        echo "fake mc rejected --insecure" >&2
        exit 1
      fi
      shift ;;
    --config-dir)
      config_dir="$2"
      shift 2 ;;
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
    if [ "${FAKE_REQUIRE_CA:-}" = "1" ]; then
      case "$(cat "${FAKE_MC_ALIAS_FILE}")" in
        https://*)
          [ -s "${config_dir}/certs/CAs/rustfs-ca.crt" ] || {
            echo "fake https trust probe rejected missing CA" >&2
            exit 1
          } ;;
      esac
    fi
    echo '2026-07-03 00:00:00 UTC aaa/'
    exit 0 ;;
  find)
    if [ "${FAKE_MC_FIND_FAIL:-}" = "1" ]; then
      echo "fake mc find failed" >&2
      exit 1
    fi
    target="$2"
    case "${target}" in
      rustfs*) echo 'rustfs/aaa/hello.txt' ;;
      */rustfs-backup/objects)
        echo "${target}"
        echo "${target}/aaa"
        echo "${target}/aaa/hello.txt" ;;
      */rustfs-restore/objects)
        echo "${target}"
        echo "${target}/aaa"
        echo "${target}/aaa/hello.txt" ;;
    esac
    exit 0 ;;
  mirror)
    src="$3"
    dst="$4"
    case "${src}" in
      rustfs/*|rustfs)
        mkdir -p "${dst}/aaa"
        printf hello > "${dst}/aaa/hello.txt" ;;
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
    if [ "${FAKE_DATASAFED_STAT_FAIL:-}" = "1" ]; then
      echo "fake datasafed stat failed" >&2
      exit 1
    fi
    if [ "${FAKE_DATASAFED_STAT_MISSING_TOTAL:-}" = "1" ]; then
      echo "ObjectCount: 1"
      exit 0
    fi
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

cat > "${TMP_ROOT}/bin/cp" <<'SH'
#!/bin/sh
set -eu

destination=""
for arg in "$@"; do
  destination="${arg}"
done
if [ "${FAKE_TRUNCATE_CA_COPY:-}" = "1" ]; then
  case "${destination}" in
    */certs/CAs/rustfs-ca.crt)
      : > "${destination}"
      exit 0 ;;
  esac
fi
exec "${REAL_CP_BIN:?missing REAL_CP_BIN}" "$@"
SH

chmod +x "${TMP_ROOT}/bin/mc" "${TMP_ROOT}/bin/datasafed" "${TMP_ROOT}/bin/cp"

export PATH="${TMP_ROOT}/bin:${PATH}"
export FAKE_STORE="${TMP_ROOT}/store"
export FAKE_MC_LOG="${TMP_ROOT}/mc.log"
export FAKE_MC_ALIAS_FILE="${TMP_ROOT}/mc-alias-endpoint"
export FAKE_FORCE_HTTPS=1
export FAKE_REJECT_INSECURE=1
export FAKE_REQUIRE_CA=1
export DP_BACKUP_BASE_PATH=/fake/base
export DP_BACKUP_INFO_FILE="${TMP_ROOT}/backup-info.json"
export DP_BACKUP_NAME=rustfs-test
export DP_DB_HOST=rustfs-0.rustfs-headless.demo.svc
export DP_DB_PORT=9000
export DP_DB_USER=root
export DP_DB_PASSWORD=secret
export RUSTFS_MC_IMAGE=docker.io/minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727
export TMPDIR="${TMP_ROOT}/tmp"
export MC_CONFIG_DIR="${TMP_ROOT}/mc-config"
export RUSTFS_TLS_CA_FILE="${TMP_ROOT}/tls/ca.crt"
mkdir -p "${TMPDIR}" "$(dirname "${RUSTFS_TLS_CA_FILE}")"
printf '%s\n' 'rustfs-test-ca' > "${RUSTFS_TLS_CA_FILE}"

assert_restore_rejects_manifest() {
  case_name="$1"
  manifest_file="$2"
  expected_error="$3"
  case_mc_log="${TMP_ROOT}/mc-${case_name}.log"
  case_stdout="${TMP_ROOT}/${case_name}.stdout"
  case_stderr="${TMP_ROOT}/${case_name}.stderr"

  cp "${manifest_file}" "${FAKE_STORE}/rustfs-test/manifest.txt"
  : > "${case_mc_log}"
  if (
    export FAKE_MC_LOG="${case_mc_log}"
    # shellcheck disable=SC1091
    . "${ROOT_DIR}/dataprotection/common.sh"
    # shellcheck disable=SC1091
    . "${ROOT_DIR}/dataprotection/restore.sh"
  ) > "${case_stdout}" 2> "${case_stderr}"; then
    echo "restore accepted invalid manifest case ${case_name}" >&2
    exit 1
  fi
  grep -Fq "${expected_error}" "${case_stderr}" || {
    echo "restore case ${case_name} did not report expected error: ${expected_error}" >&2
    cat "${case_stderr}" >&2
    exit 1
  }
  if grep -Eq '^mc .* (mb|mirror)( |$)' "${case_mc_log}"; then
    echo "restore case ${case_name} mutated target buckets or objects" >&2
    cat "${case_mc_log}" >&2
    exit 1
  fi
  cat "${case_stderr}" >&2
}

if (
  export RUSTFS_SCHEME=ftp
  export MC_CONFIG_DIR="${TMP_ROOT}/mc-invalid-scheme"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  rustfs_prepare_mc
); then
  echo "RustFS alias accepted an unsupported endpoint scheme" >&2
  exit 1
fi

if (
  export FAKE_DATASAFED_STAT_FAIL=1
  export DP_BACKUP_INFO_FILE="${TMP_ROOT}/backup-info-stat-fail.json"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  rustfs_save_backup_size
); then
  echo "backup size capture succeeded after datasafed stat failed" >&2
  exit 1
fi

if (
  export FAKE_DATASAFED_STAT_MISSING_TOTAL=1
  export DP_BACKUP_INFO_FILE="${TMP_ROOT}/backup-info-missing-total.json"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  rustfs_save_backup_size
); then
  echo "backup size capture succeeded without TotalSize" >&2
  exit 1
fi

if (
  export FAKE_MC_FIND_FAIL=1
  export DP_BACKUP_NAME=rustfs-find-fail
  export DP_BACKUP_INFO_FILE="${TMP_ROOT}/backup-info-find-fail.json"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/backup.sh"
); then
  echo "backup succeeded after mc find failed" >&2
  exit 1
fi

(
  export RUSTFS_TLS_CA_FILE="${TMP_ROOT}/tls/http-does-not-mount-ca.crt"
  export FAKE_FORCE_HTTPS=0
  export MC_CONFIG_DIR="${TMP_ROOT}/mc-http"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  rustfs_prepare_mc
  [ "${RUSTFS_SCHEME_EFFECTIVE}" = "http" ]
) || {
  echo "TLS-off RustFS alias did not resolve over HTTP" >&2
  exit 1
}

if (
  unset RUSTFS_TLS_CA_FILE
  export FAKE_FORCE_HTTPS=1
  export MC_CONFIG_DIR="${TMP_ROOT}/mc-missing-ca"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  rustfs_prepare_mc
); then
  echo "HTTPS alias succeeded without a trusted RustFS CA" >&2
  exit 1
fi

if (
  export RUSTFS_TLS_CA_FILE="${TMP_ROOT}/tls/missing-ca.crt"
  export RUSTFS_SCHEME=https
  export FAKE_FORCE_HTTPS=1
  export FAKE_REQUIRE_CA=0
  export MC_CONFIG_DIR="${TMP_ROOT}/mc-missing-ca-path"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  rustfs_prepare_mc
); then
  echo "HTTPS alias succeeded with a configured but missing RustFS CA" >&2
  exit 1
fi

if (
  export RUSTFS_SCHEME=https
  export FAKE_FORCE_HTTPS=1
  export FAKE_REQUIRE_CA=0
  export FAKE_TRUNCATE_CA_COPY=1
  export MC_CONFIG_DIR="${TMP_ROOT}/mc-empty-installed-ca"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  rustfs_prepare_mc
); then
  echo "HTTPS alias succeeded after installing an empty RustFS CA" >&2
  exit 1
fi

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
[ -f "${FAKE_STORE}/rustfs-test/objects/aaa/hello.txt" ] || {
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
grep -q '^bucket:aaa$' "${FAKE_STORE}/rustfs-test/manifest.txt" || {
  echo "manifest bucket list missing" >&2
  exit 1
}
grep -q '^object:aaa/hello.txt$' "${FAKE_STORE}/rustfs-test/manifest.txt" || {
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
grep -q 'mb --ignore-existing rustfs/aaa' "${FAKE_MC_LOG}" || {
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
if grep -q -- '--insecure' "${FAKE_MC_LOG}"; then
  echo "backup/restore mc commands bypassed TLS certificate verification" >&2
  exit 1
fi
[ "$(cat "${MC_CONFIG_DIR}/certs/CAs/rustfs-ca.crt")" = 'rustfs-test-ca' ] || {
  echo "RustFS CA was not installed into the mc trust directory" >&2
  exit 1
}

cp "${FAKE_STORE}/rustfs-test/manifest.txt" "${TMP_ROOT}/manifest.good"
cp "${FAKE_STORE}/rustfs-test/objects/aaa/hello.txt" "${TMP_ROOT}/hello.good"
mkdir -p "${FAKE_STORE}/rustfs-test/objects/b"
printf hello > "${FAKE_STORE}/rustfs-test/objects/b/hello.txt"

cat > "${TMP_ROOT}/manifest-empty-bucket" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=1
objectCount=0
bucket:
MANIFEST
assert_restore_rejects_manifest empty-bucket "${TMP_ROOT}/manifest-empty-bucket" \
  "backup manifest contains an empty bucket name"

cat > "${TMP_ROOT}/manifest-duplicate-bucket" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=2
objectCount=0
bucket:aaa
bucket:aaa
MANIFEST
assert_restore_rejects_manifest duplicate-bucket "${TMP_ROOT}/manifest-duplicate-bucket" \
  "backup manifest contains duplicate bucket aaa"

cat > "${TMP_ROOT}/manifest-duplicate-object" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=1
objectCount=2
bucket:aaa
object:aaa/hello.txt
object:aaa/hello.txt
MANIFEST
mkdir -p "${FAKE_STORE}/rustfs-test/objects/aaa"
printf hello > "${FAKE_STORE}/rustfs-test/objects/aaa/hello.txt"
assert_restore_rejects_manifest duplicate-object "${TMP_ROOT}/manifest-duplicate-object" \
  "backup manifest contains duplicate object aaa/hello.txt"

cat > "${TMP_ROOT}/manifest-unsafe-bucket" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=1
objectCount=0
bucket:../escape
MANIFEST
assert_restore_rejects_manifest unsafe-bucket "${TMP_ROOT}/manifest-unsafe-bucket" \
  "backup manifest contains invalid bucket name ../escape"

cat > "${TMP_ROOT}/manifest-ipv4-bucket" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=1
objectCount=0
bucket:192.168.1.1
MANIFEST
assert_restore_rejects_manifest ipv4-bucket "${TMP_ROOT}/manifest-ipv4-bucket" \
  "backup manifest contains invalid bucket name 192.168.1.1"

cat > "${TMP_ROOT}/manifest-ipv4-shaped-bucket" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=1
objectCount=0
bucket:1234.1.1.1
MANIFEST
assert_restore_rejects_manifest ipv4-shaped-bucket "${TMP_ROOT}/manifest-ipv4-shaped-bucket" \
  "backup manifest contains invalid bucket name 1234.1.1.1"

cat > "${TMP_ROOT}/manifest-reserved-bucket" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=1
objectCount=0
bucket:rustfs
MANIFEST
assert_restore_rejects_manifest reserved-bucket "${TMP_ROOT}/manifest-reserved-bucket" \
  "backup manifest contains invalid bucket name rustfs"

cat > "${TMP_ROOT}/manifest-hyphen-dot-bucket" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=1
objectCount=0
bucket:aaa-.bbb
MANIFEST
assert_restore_rejects_manifest hyphen-dot-bucket "${TMP_ROOT}/manifest-hyphen-dot-bucket" \
  "backup manifest contains invalid bucket name aaa-.bbb"

cat > "${TMP_ROOT}/manifest-dot-hyphen-bucket" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=1
objectCount=0
bucket:aaa.-bbb
MANIFEST
assert_restore_rejects_manifest dot-hyphen-bucket "${TMP_ROOT}/manifest-dot-hyphen-bucket" \
  "backup manifest contains invalid bucket name aaa.-bbb"

cat > "${TMP_ROOT}/manifest-object-bucket-mismatch" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=1
objectCount=1
bucket:aaa
object:b/hello.txt
MANIFEST
assert_restore_rejects_manifest object-bucket-mismatch "${TMP_ROOT}/manifest-object-bucket-mismatch" \
  "backup object b/hello.txt does not belong to a declared bucket"

cat > "${TMP_ROOT}/manifest-duplicate-scalar" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=0
objectCount=0
MANIFEST
assert_restore_rejects_manifest duplicate-scalar "${TMP_ROOT}/manifest-duplicate-scalar" \
  "backup manifest must contain formatVersion exactly once"

cat > "${FAKE_STORE}/rustfs-test/manifest.txt" <<'MANIFEST'
formatVersion=rustfs-s3-full.v1
method=s3-full
bucketCount=1
objectCount=1
bucket:aaa
object:../escape
MANIFEST
printf escape > "${FAKE_STORE}/rustfs-test/escape"
if (
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/common.sh"
  # shellcheck disable=SC1091
  . "${ROOT_DIR}/dataprotection/restore.sh"
); then
  echo "restore accepted a path-traversing object artifact" >&2
  exit 1
fi
[ ! -e "${TMPDIR}/rustfs-restore/escape" ] || {
  echo "restore wrote a path-traversing object outside the objects directory" >&2
  exit 1
}
cp "${TMP_ROOT}/manifest.good" "${FAKE_STORE}/rustfs-test/manifest.txt"
cp "${TMP_ROOT}/hello.good" "${FAKE_STORE}/rustfs-test/objects/aaa/hello.txt"
rm -f "${FAKE_STORE}/rustfs-test/escape" "${FAKE_STORE}/rustfs-test/objects/b/hello.txt" \
  "${FAKE_STORE}/rustfs-test/objects/aaa/hello.txt"

rm -f "${FAKE_STORE}/rustfs-test/objects/aaa/hello.txt"
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
