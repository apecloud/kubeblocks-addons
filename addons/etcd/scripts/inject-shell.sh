#!/bin/sh

load_common_library() {
  # the kb-common.sh and common.sh scripts are defined in the scripts-template configmap
  # and are mounted to the same path which defined in the cmpd.spec.scripts
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck source=/scripts/kb-common.sh
  . "${kblib_common_library_file}"
  # shellcheck source=/scripts/common.sh
  . "${etcd_common_library_file}"
}

inject_binaries() {
  version="$1"

  echo "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || {
    echo "Invalid version format, check ETCD_VERSION" >&2
    return 1
  }

  major=$(echo "$version" | cut -d. -f1 | sed 's/^v//')
  minor=$(echo "$version" | cut -d. -f2)
  patch=$(echo "$version" | cut -d. -f3)

  # <=3.3 || <= 3.4.22 || <=3.5.6 all use busybox https://github.com/etcd-io/etcd/tree/main/CHANGELOG
  if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && { [ "$minor" -le 3 ] || { [ "$minor" -eq 4 ] && [ "$patch" -le 22 ]; } || { [ "$minor" -eq 5 ] && [ "$patch" -le 6 ]; }; }; }; then
    cp /bin/sh /shell
  else
    echo "etcd image build with distroless, injecting brinaries in order to run scripts"
    cp /bin/* /shell
  fi
  return 0
}

main() {
  if [ -z "$ETCD_VERSION" ]; then
    echo "ETCD_VERSION env is not set"
    exit 1
  fi

  if inject_binaries "$ETCD_VERSION"; then
    echo "Binaries injected successfully"
  else
    echo "Failed to inject binaries" >&2
    exit 1
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
main