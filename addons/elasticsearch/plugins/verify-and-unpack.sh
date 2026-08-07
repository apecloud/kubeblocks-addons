#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 ARCHIVE EXPECTED_SHA256 DESTINATION" >&2
  exit 2
fi

archive=$1
expected_sha256=$2
destination=$3
unzip_bin=${UNZIP_BIN:-unzip}

printf '%s  %s\n' "${expected_sha256}" "${archive}" | sha256sum -c -
mkdir -p "${destination}"
"${unzip_bin}" -q "${archive}" -d "${destination}/"
