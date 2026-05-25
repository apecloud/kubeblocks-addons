# Smoke-backup acceptance journal (2026-05-25)

This file seeds a development branch used to track an acceptance lane: characterising the intermittent smoke-backup slice (T16 Backup / T17 Restore / T18 Scheduled Backup / T19 No-op Upgrade) result on the current Valkey addon HEAD. It is independent of any in-flight role-probe fix.

## Candidate package

- target branch: `feat/valkey-addon`
- development branch: `alice/smoke-backup-acceptance-20260525`
- target branch HEAD at fork: `b9cc769e4dd971d0a89c13bbe6159c7d0acffd13`
- KubeBlocks: KB main 1.2.0-alpha.x (controller image to be pinned at run time)
- DataProtection: KB main 1.2.0-alpha.x
- syncer: chart-default at run time
- included PRs: none yet
- excluded PRs: none yet
- acceptance gate: smoke-backup slice (kubeblocks-tests/valkey/tests/smoke-backup.sh) over multiple fresh-cluster rounds; on first non-environment non-SKIP FAIL, follow autonomous-addon-development-loop rule #20 and freeze the live cluster for investigation

## Scope

This dev branch hosts child PRs only when a test, harness, chart, or addon code fix is needed during the acceptance lane. It does not bundle unrelated features. The main PR description tracks each child PR link, tested commit, and short result. Final integration into `feat/valkey-addon` requires human approval after the acceptance gate is satisfied.
