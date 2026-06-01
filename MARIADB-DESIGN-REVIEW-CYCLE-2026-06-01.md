# MariaDB design-review cycle — 2026-06-01

This file is the placeholder commit so the development branch is non-empty and can host the main PR umbrella. Per `autonomous-addon-development-loop` Rule 7 this branch hosts:

- **Main PR**: this branch → `feat/mariadb-alpha37-semisync-fencing-pr` (integration owner gate).
- **Child PRs**: each design-review finding lands as a child PR with base = this branch. After self-test + self-review, child PRs are self-merged into this branch.
- **Acceptance**: rebased onto latest `feat/mariadb-alpha37-semisync-fencing-pr` after each child PR merge; new live test round after the candidate package on this branch stabilizes.

## Cycle goals (per @westonnnn 2026-06-01 20:11 directive in #mariadb)

Two review tools:

1. Read `kubeblocks-addon-docs/docs/addon-api/` — verify every MariaDB addon code path follows the contract.
2. Compare MySQL addon (`addons/mysql/`) + syncer `engines/mysql/` against MariaDB addon + syncer `engines/mariadb/` to surface design unsoundness.

Each finding → child PR → self-merge into this branch → main PR rebased forward.

## Linked child PRs

(populated as PRs land)

- (placeholder)

## Pinned candidate context

- Base: `feat/mariadb-alpha37-semisync-fencing-pr` head at cycle start = `9089c76955bd3e53a01ea2e5e772b209a8710b14` (alpha.110)
- Parallel in-flight PRs against same base (will rebase / fold once decisions clear):
  - PR #2701 (alpha.111 P0a URGENT FLUSH PRIVILEGES wrap)
  - PR #2702 (alpha.112 honest 60s memberJoin + galera single-shot)
  - PR #2712 (alpha.113 replication memberJoin single-shot bootstrap-or-defer)
  - PR #2714 (alpha.114 Path C account model declarative-only)
  - PR #2720 (Jack — contract guard for replication topology + install-time mode)
- New live MariaDB test round will run on the candidate package built from this branch after first round of child-PR merges.
