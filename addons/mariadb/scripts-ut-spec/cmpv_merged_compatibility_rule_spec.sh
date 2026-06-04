# shellcheck shell=sh

# alpha.89 v1 commit 15 (Helen 2026-05-20, live N=1 first-blocker
# fix from vcluster `mariadb-test5` rerun on commit 14 chart) —
# the merged replication CmpD (`mariadb-replication-merged-...`)
# was not matched by any ComponentVersion compatibilityRule entry,
# so the InstanceSet did not get the engine / exporter /
# init-syncer images bound. Pod create failed with
# `spec.containers[*].image: Required value`.
#
# This spec locks that the merged CmpD regex is included in the
# replication/semisync/standalone release group's compDefs list,
# alongside the existing three regexes, so a future edit cannot
# silently drop it.

Describe "alpha.89 commit 15 ComponentVersion compatibility for merged CmpD"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  cmpv_path() {
    printf "%s/addons/mariadb/templates/cmpv.yaml" "$(repo_root)"
  }

  helper_path() {
    printf "%s/addons/mariadb/templates/_helpers.tpl" "$(repo_root)"
  }

  Describe "cmpv.yaml template references the merged regex helper"
    It "compDefs list in cmpv.yaml includes mariadb.replication.merged.cmpdRegexpPattern"
      When call grep -c 'mariadb.replication.merged.cmpdRegexpPattern' "$(cmpv_path)"
      The status should be success
      The output should equal "1"
    End

    It "cmpv.yaml still references the original three regexes (no regression)"
      When call grep -cE 'mariadb\.(standalone|replication|semisync)\.cmpdRegexpPattern' "$(cmpv_path)"
      The status should be success
      The output should equal "3"
    End

    It "_helpers.tpl defines the merged regex helper"
      When call grep -c 'define "mariadb\.replication\.merged\.cmpdRegexpPattern"' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End

    It "_helpers.tpl declares the merged regex as ^mariadb-replication-merged-"
      When call grep -cF '^mariadb-replication-merged-' "$(helper_path)"
      The status should be success
      The output should be present
    End
  End

  Describe "rendered manifest contains all four regexes in the same compatibilityRule"
    helm_not_available() { ! command -v helm >/dev/null 2>&1; }
    Skip if "helm not available" helm_not_available

    chart_path() {
      printf "%s/addons/mariadb" "$(repo_root)"
    }

    setup() {
      tmp_render=$(mktemp -t mariadb-cmpv-render-XXXXXX)
      helm template test "$(chart_path)" >"${tmp_render}" 2>/dev/null || true
    }

    cleanup() {
      rm -f "${tmp_render}" 2>/dev/null || true
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    extract_first_compatibility_compdefs() {
      # Print one line per compDef pattern in the FIRST
      # compatibilityRule's compDefs list. Used by the assertions
      # below to count and verify which patterns are present.
      awk '
        /kind: ComponentVersion/ { in_cmpv = 1 }
        in_cmpv && /compatibilityRules:/ { in_rules = 1; next }
        in_cmpv && in_rules && /^[[:space:]]+- compDefs:/ { in_first_rule++; next }
        in_cmpv && in_rules && in_first_rule == 1 && /^[[:space:]]+releases:/ { exit }
        in_cmpv && in_rules && in_first_rule == 1 && /^[[:space:]]+- / { print }
      ' "${tmp_render}"
    }

    It "first compatibilityRule lists ^mariadb-replication-merged-"
      When call extract_first_compatibility_compdefs
      The output should include "^mariadb-replication-merged-"
    End

    It "first compatibilityRule lists ^mariadb-[0-9] (standalone regression guard)"
      When call extract_first_compatibility_compdefs
      The output should include "^mariadb-[0-9]"
    End

    It "first compatibilityRule lists ^mariadb-replication-[0-9] (replication regression guard)"
      When call extract_first_compatibility_compdefs
      The output should include "^mariadb-replication-[0-9]"
    End

    It "first compatibilityRule lists ^mariadb-semisync- (semisync regression guard)"
      When call extract_first_compatibility_compdefs
      The output should include "^mariadb-semisync-"
    End

    It "rendered manifest declares image entries for 11.4.10 release (the merged CmpD default serviceVersion)"
      # Only do a bounded grep, not a full-content matcher, per
      # the macOS+Homebrew harness lesson. Look for the release
      # block's images.mariadb line.
      When call grep -c 'mariadb: docker\.io/mariadb:11\.4' "${tmp_render}"
      The status should be success
      The output should be present
    End
  End

End
