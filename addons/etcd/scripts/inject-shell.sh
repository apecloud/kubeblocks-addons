#!/bin/sh

# inject shell if needed

busyboxAction() {
  # copy sh to /shell in order to adapt distroless entrypoint
  cp /bin/sh /shell
}

distrolessAction() {
  echo "etcd image build with distroless, injecting brinaries in order to run scripts"
  cp /bin/* /shell
}

# versionCheck only check image type but not availability
checkVersionAndInject() {
  local version=$1
  echo "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'
  if [ $? -ne 0 ]; then
    echo "Invalid version format, check vars ETCD_VERSION"
    exit 1
  fi

  versionParse=$(echo "$version" | sed 's/^v//')
  major=$(echo "$versionParse" | cut -d. -f1)
  minor=$(echo "$versionParse" | cut -d. -f2)
  patch=$(echo "$versionParse" | cut -d. -f3)

  # <=3.3 || <= 3.4.22 || <=3.5.6 all use busybox https://github.com/etcd-io/etcd/tree/main/CHANGELOG
  if [ $major -lt 3 ] || ([ $major -eq 3 ] && [ $minor -lt 4 ]); then
    busyboxAction
  elif [ $major -eq 3 ] && [ $minor -eq 4 ] && [ $patch -le 22 ]; then
    busyboxAction
  elif [ $major -eq 3 ] && [ $minor -eq 5 ] && [ $patch -le 6 ]; then
    busyboxAction
  else
    distrolessAction
  fi
}

checkVersionAndInject $ETCD_VERSION