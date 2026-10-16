# Startup membership integration regression

This test runs three local etcd processes, adds a fourth member, and executes the
addon's registration barrier followed by the real etcd binary. A peer HTTP proxy
either returns stale `/members` responses or makes that endpoint unavailable;
all Raft traffic continues to the real members. The fourth member must become
healthy and read a key written through another member.

Requirements: Go, Bash 4+, curl, etcd and matching etcdctl binaries. The test uses
loopback ephemeral ports and temporary data directories, and stops every child
process on completion. No Kubernetes cluster or network download is needed.

From this directory:

```sh
ETCD_BINARY=/path/to/etcd ETCDCTL_BINARY=/path/to/etcdctl \
  BASH_BINARY=/path/to/bash \
  go test -v -count=1 -timeout=90s startup_membership_test.go
```

Run against each supported etcd release being validated. `ETCD_SCRIPTS_DIR` can
point to a checkout's `addons/etcd/scripts` to verify that the same regression
fails on an older implementation. The stale-peer case must fail on PR 3500's
original `1f35b67f` head with `member count is unequal` and pass after the fix.

These tests cover local HTTP startup and replication, not Kubernetes lifecycle,
TLS, rollout, or snapshot restore integration.
