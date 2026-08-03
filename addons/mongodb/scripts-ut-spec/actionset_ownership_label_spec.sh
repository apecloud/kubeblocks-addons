# shellcheck shell=bash

Describe "MongoDB ActionSet ownership labels"

  render_and_validate_actionset_ownership_labels() {
    local chart_dir rendered

    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    helm dependency build "$chart_dir" >/dev/null || return
    rendered=$(helm template kb-addon-mongodb "$chart_dir") || return
    # shellcheck disable=SC2016
    printf '%s\n' "$rendered" | ruby -ryaml -e '
      action_sets = YAML.load_stream($stdin.read).compact.select do |document|
        document["kind"] == "ActionSet"
      end

      expected_names = %w[
        mongodb-dump-br
        mongodb-physical-br
        mongodb-pitr
        mongodb-rs-pbm-physical
        mongodb-rs-pbm-pitr
        mongodb-shard-pbm-logical
        mongodb-shard-pbm-physical
        mongodb-shard-pbm-pitr
        mongodb-volume-snapshot
      ]
      actual_names = action_sets.map { |action_set| action_set.dig("metadata", "name") }.sort
      abort "ActionSet inventory=#{actual_names.inspect}, expected #{expected_names.inspect}" unless actual_names == expected_names

      action_sets.each do |action_set|
        name = action_set.dig("metadata", "name")
        owner = action_set.dig(
          "metadata",
          "labels",
          "clusterdefinition.kubeblocks.io/name"
        )
        abort "#{name} ownership label=#{owner.inspect}, expected \"mongodb\"" unless owner == "mongodb"
      end

      puts "ActionSet ownership labels passed for #{action_sets.length} resources"
    '
  }

  It "labels every rendered ActionSet as owned by MongoDB"
    When call render_and_validate_actionset_ownership_labels
    The status should be success
    The output should include "ActionSet ownership labels passed for 9 resources"
  End
End
