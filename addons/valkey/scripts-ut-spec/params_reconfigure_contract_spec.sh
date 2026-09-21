# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey parameter reconfigure contract (KubeBlocks 1.0)"
  data_cmpd="../templates/cmpd.yaml"
  helpers="../templates/_helpers.tpl"
  paramsdef="../templates/paramsdef.yaml"
  pcr="../templates/pcr-valkey.yaml"
  reload_cm="../templates/reload-tools-script.yaml"

  # ── the unreleased reconfigure action must be gone ──────────────────────
  # `reconfigure` under ComponentDefinition.spec.configs[] only exists on
  # KubeBlocks master (unreleased); the 1.0 API drops the field silently.
  It "does not declare a reconfigure action under the cmpd configs"
    When call grep -F "reconfigure:" "${data_cmpd}"
    The status should be failure
  End

  It "does not keep the reconfigureAction helper around"
    When call grep -F "reconfigureAction" "${data_cmpd}" "${helpers}"
    The status should be failure
  End

  # ── ParametersDefinition uses the released 1.0 shape ────────────────────
  It "keeps the PD free of the unreleased componentDef/templateName/fileFormatConfig fields"
    When call grep -E "^[[:space:]]+(componentDef|templateName|fileFormatConfig):" "${paramsdef}"
    The status should be failure
  End

  It "declares the reload action as a shellTrigger on reload-parameter.sh"
    When call bash -c "grep -A 12 'reloadAction:' '${paramsdef}'"
    The status should be success
    The stdout should include "shellTrigger:"
    The stdout should include "sync: true"
    The stdout should include '"reload-parameter.sh"'
  End

  It "runs the reload inside the config-manager sidecar built from the Valkey image"
    When call bash -c "grep -A 20 'toolsSetup:' '${paramsdef}'"
    The status should be success
    The stdout should include "mountPoint: /kb_tools"
    The stdout should include "asContainerImage: true"
  End

  It "points the reload action at the reload tools ConfigMap"
    When call grep -F 'scriptConfigMapRef: {{ include "valkey.reloadToolsScript" $ }}' "${paramsdef}"
    The status should be success
    The stdout should include "valkey.reloadToolsScript"
  End

  It "ships reload-parameter.sh in that ConfigMap"
    When call grep -F '.Files.Get "scripts/reload-parameter.sh"' "${reload_cm}"
    The status should be success
    The stdout should include "reload-parameter.sh"
  End

  It "keeps the PD fileName in sync with the config file shipped by the template"
    When call grep -F "fileName: valkey.conf" "${paramsdef}"
    The status should be success
    The stdout should include "fileName: valkey.conf"
  End

  # ── the CUE schema must actually reach the PD ──────────────────────────
  # .Files.Get returns an empty string for a missing path, so a typo here
  # publishes a ParametersDefinition with an empty schema — no error anywhere.
  # The schema is per major: valkey-8 and valkey-9 differ (see the version
  # difference examples at the end of this file).
  It "loads the per-major constraint file that exists in the chart"
    When call grep -F '.Files.Get (printf "config/valkey%s-config-constraint.cue" .major)' "${paramsdef}"
    The status should be success
    The stdout should include "config/valkey%s-config-constraint.cue"
  End

  It "ships a non-empty constraint file per major"
    When call bash -c "test -s '../config/valkey8-config-constraint.cue' && test -s '../config/valkey9-config-constraint.cue' && echo both-present"
    The status should be success
    The stdout should include "both-present"
  End

  It "loads the per-major parameter effect scope"
    When call grep -F '.Files.Get (printf "config/valkey%s-config-effect-scope.yaml" .major) | fromYaml' "${paramsdef}"
    The status should be success
    The stdout should include "config/valkey%s-config-effect-scope.yaml"
  End

  It "declares the three parameter classes from that scope"
    When call bash -c "grep -cE '^(static|dynamic|immutable)Parameters:' '../config/valkey8-config-effect-scope.yaml'"
    The status should be success
    The stdout should eq "3"
  End

  It "declares a CUE type matching the PD topLevelKey"
    When call grep -F "#ValkeyParameter:" "../config/valkey8-config-constraint.cue"
    The status should be success
    The stdout should include "#ValkeyParameter:"
  End

  It "keeps the PD topLevelKey in sync with that CUE type"
    When call grep -F "topLevelKey: ValkeyParameter" "${paramsdef}"
    The status should be success
    The stdout should include "topLevelKey: ValkeyParameter"
  End

  # ── ParamConfigRenderer binds the PD to the component ───────────────────
  It "declares exactly one ParamConfigRenderer, ranged over the major versions"
    When call bash -c "grep -c 'kind: ParamConfigRenderer' '${pcr}'"
    The status should be success
    The stdout should eq "1"
  End

  It "binds the PCR to the stable component definition name"
    When call grep -F "componentDef: {{ .componentDef }}" "${pcr}"
    The status should be success
    The stdout should include "componentDef: {{ .componentDef }}"
  End

  It "does not put the chart version into the PCR name"
    # The ComponentDefinition name is stable across chart versions, so a
    # versioned PCR name would leave two PCRs matching the same componentDef
    # after an upgrade and make the resolution order-dependent.
    When call grep -F ".Chart.Version" "${pcr}"
    The status should be failure
  End

  It "references the ParametersDefinition of the same major version"
    When call bash -c "grep -A 2 'parametersDefs:' '${pcr}'"
    The status should be success
    The stdout should include 'valkey%s-pd'
  End

  It "describes valkey.conf as a redis-format file re-rendered on vscale"
    When call bash -c "grep -A 8 'configs:' '${pcr}'"
    The status should be success
    The stdout should include "name: valkey.conf"
    The stdout should include "format: redis"
    The stdout should include "- vscale"
  End

  It "names the configspec entry the PCR points at"
    # pcr.configs[].templateName must equal the cmpd configspec entry name,
    # otherwise KubeBlocks finds no config spec to watch and never builds the
    # reload handler.
    When call grep -F "templateName: valkey-replication-config" "${pcr}"
    The status should be success
    The stdout should include "templateName: valkey-replication-config"
  End

  It "keeps that configspec entry defined in the cmpd"
    When call grep -F "name: valkey-replication-config" "${data_cmpd}"
    The status should be success
    The stdout should include "- name: valkey-replication-config"
  End

  # ── version differences (generated from the upstream release lines) ─────
  # valkey-8 serves 8.0 and 8.1, so its schema is the union of the two and
  # marks what belongs to only one of them.
  It "marks the parameters that exist in only one release line"
    When call grep -F "// only in" "../config/valkey8-config-constraint.cue"
    The status should be success
    The stdout should include "// only in"
  End

  It "keeps the 8.0-only parameters in the valkey-8 schema"
    # [[:space:]] instead of \\s: the macOS grep ERE does not know \\s.
    When call bash -c "grep -cE '^[[:space:]]*\"(dynamic-hz|io-threads-do-reads|slowlog-max-len|slowlog-log-slower-than)\"' '../config/valkey8-config-constraint.cue'"
    The status should be success
    The stdout should eq "4"
  End

  It "records the 8.1 renames as legacy aliases"
    When call grep -F "legacy alias: slowlog-log-slower-than" "../config/valkey8-config-constraint.cue"
    The status should be success
    The stdout should include "legacy alias: slowlog-log-slower-than"
  End

  It "keeps the valkey-9 schema free of the 8.0-only parameters"
    When call bash -c "grep -cE '^[[:space:]]*\"(dynamic-hz|io-threads-do-reads|slowlog-max-len)\"' '../config/valkey9-config-constraint.cue'"
    The status should be failure
    The stdout should eq "0"
  End

  It "carries the 9.x commandlog parameters in the valkey-9 schema"
    When call grep -F '"commandlog-slow-execution-max-len"' "../config/valkey9-config-constraint.cue"
    The status should be success
    The stdout should include "commandlog-slow-execution-max-len"
  End

  It "admits the 9.1-only parameters in the valkey-9 schema"
    When call grep -F '"hash-seed"' "../config/valkey9-config-constraint.cue"
    The status should be success
    The stdout should include "hash-seed"
  End
End
