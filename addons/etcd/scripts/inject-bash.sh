#!/bin/bash

inject_bash() {
  version="$1"

  echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    echo "Invalid version format, check ETCD_VERSION" >&2
    return 1
  }

  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)
  patch=$(echo "$version" | cut -d. -f3)

  # <=3.3 || <= 3.4.22 || <=3.5.6 all base on debian image https://github.com/etcd-io/etcd/tree/main/CHANGELOG
  if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && { [ "$minor" -le 3 ] || { [ "$minor" -eq 4 ] && [ "$patch" -le 22 ]; } || { [ "$minor" -eq 5 ] && [ "$patch" -le 6 ]; }; }; }; then
    echo "No need to inject bash for etcd-$version image"
  else
    echo "etcd-$version image build with distroless, injecting brinaries to run scripts"
    cp /bin/* /share/bin
  fi
  return 0
}

main() {
  if is_empty "$ETCD_VERSION"; then
    echo "ETCD_VERSION env is not set"
    exit 1
  fi

  if ! inject_bash "$ETCD_VERSION"; then
    echo "Failed to inject bash" >&2
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
main