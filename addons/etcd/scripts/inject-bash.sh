#!/bin/bash
set -ex

load_common_library() {
  # the kb-common.sh and common.sh scripts are defined in the scripts-template configmap
  # and are mounted to the same path which defined in the cmpd.spec.scripts
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  . "${kblib_common_library_file}"
  # shellcheck disable=SC1090
  . "${etcd_common_library_file}"
}

inject_bash() {
  local version="$1"
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
    cp /bin/* /share/bin
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
inject_bash "$ETCD_VERSION"
