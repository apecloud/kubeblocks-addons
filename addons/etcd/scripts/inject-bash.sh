#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"

inject_bash() {
  local version="$1"
  local target_dir="$2"
  local major minor patch

  echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || error_exit "Invalid version format, check ETCD_VERSION"

  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)
  patch=$(echo "$version" | cut -d. -f3)

  # <=3.3 || <= 3.4.22 || <=3.5.6 all base on debian image https://github.com/etcd-io/etcd/tree/main/CHANGELOG
  if [ "$major" -lt 3 ] ||
    { [ "$major" -eq 3 ] &&
      { [ "$minor" -le 3 ] ||
        { [ "$minor" -eq 4 ] && [ "$patch" -le 22 ]; } ||
        { [ "$minor" -eq 5 ] && [ "$patch" -le 6 ]; }; }; }; then
    echo "No need to inject bash for etcd-${version} image"
  else
    echo "etcd-$version image build with distroless, injecting binaries to run scripts"
    mkdir -p "$target_dir"
    cp /bin/* "$target_dir/"
    
    # Create /shared/bin directory and symlink all binaries for standard PATH
    mkdir -p /shared/bin
    for binary in "$target_dir"/*; do
      binary_name=$(basename "$binary")
      ln -sf "$binary" "/shared/bin/$binary_name"
    done
    echo "Created symlinks for $(ls /bin | wc -l) binaries in /bin"
  fi
}

# Shellspec magic
setup_shellspec

# main
load_common_library
target_dir="${1:-/share/bin}"
inject_bash "$ETCD_VERSION" "$target_dir"
