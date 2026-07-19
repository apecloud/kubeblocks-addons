# shellcheck shell=bash
# shellcheck disable=SC2034,SC2016

Describe "Elasticsearch 9.3.2 chart contract"
  addon_chart=".."
  cluster_chart="../../../addons-cluster/elasticsearch"
  es_digest="docker.io/elasticsearch@sha256:1111111111111111111111111111111111111111111111111111111111111111"
  kibana_digest="docker.io/apecloud/kibana@sha256:2222222222222222222222222222222222222222222222222222222222222222"
  plugin_digest="docker.io/apecloud/elasticsearch-plugins@sha256:3333333333333333333333333333333333333333333333333333333333333333"
  es_dump_digest="docker.io/elasticdump/elasticsearch-dump@sha256:5555555555555555555555555555555555555555555555555555555555555555"
  exporter_digest="docker.io/prometheuscommunity/elasticsearch-exporter@sha256:6666666666666666666666666666666666666666666666666666666666666666"
  tools_digest="docker.io/apecloud/curl-jq@sha256:7777777777777777777777777777777777777777777777777777777777777777"
  agent_digest="docker.io/apecloud/elasticsearch-agent@sha256:8888888888888888888888888888888888888888888888888888888888888888"

  It "renders isolated 9.x topology, digest-only releases, and version-mapped backup actions"
    When run env \
      ES9_ES_DIGEST="${es_digest}" \
      ES9_KIBANA_DIGEST="${kibana_digest}" \
      ES9_PLUGIN_DIGEST="${plugin_digest}" \
      ES9_EXPORTER_DIGEST="${exporter_digest}" \
      ES9_TOOLS_DIGEST="${tools_digest}" \
      ES9_AGENT_DIGEST="${agent_digest}" \
      ES9_ES_DUMP_DIGEST="${es_dump_digest}" \
      bash ./es9_render_check.sh "${addon_chart}"
    The output should include "topologies=single-node,multi-node"
    The output should include "topology_patterns=^elasticsearch-9-,^elasticsearch-master-9-,^elasticsearch-data-9-"
    The output should include "legacy_matches_9=false"
    The output should include "legacy_covers_678_families=true"
    The output should include "legacy_bpt_covers_678=true"
    The output should include "legacy_bpt_excludes_master=true"
    The output should include "legacy_bpt_excludes_9=true"
    The output should include "cmpds=elasticsearch-9,elasticsearch-data-9,elasticsearch-master-9,kibana-9"
    The output should include "roles_match_8x=true"
    The output should include "plugin_fail_close=true"
    The output should include "custom_init_absent=true"
    The output should include "cmpd_explicit_images_digest_only=true"
    The output should include "config_isolated=true"
    The output should include "kibana_multi_component_credentials=true"
    The output should include "es_release_digest_only=true"
    The output should include "custom_image_absent=true"
    The output should include "kibana_digest=${kibana_digest}"
    The output should include "physical_mapping=IMAGE|elasticsearch-9-physical-br|9.3.2|${es_digest}"
    The output should include "dump_mapping=ES_DUMP_IMAGE|elasticsearch-9-es-dump|9.3.2|${es_dump_digest}"
    The output should include 'physical_action=$(IMAGE)|$(IMAGE)'
    The output should include 'dump_action=$(ES_DUMP_IMAGE)|$(ES_DUMP_IMAGE)'
    The status should be success
  End

  render_with_digests() {
    helm template elasticsearch "${addon_chart}" \
      --set es9.enabled=true \
      --set-string es9.images.elasticsearch="${es_digest}" \
      --set-string es9.images.kibana="${kibana_digest}" \
      --set-string es9.images.plugin="${plugin_digest}" \
      --set-string es9.images.exporter="${exporter_digest}" \
      --set-string es9.images.tools="${tools_digest}" \
      --set-string es9.images.agent="${agent_digest}" \
      --set-string es9.images.esDump="${es_dump_digest}" \
      "$@"
  }

  verify_each_missing_digest_fails() {
    for image_name in elasticsearch kibana plugin exporter tools agent esDump; do
      output_file=$(mktemp)
      if render_with_digests --set-string "es9.images.${image_name}=" >"${output_file}" 2>&1; then
        echo "missing ${image_name} unexpectedly rendered" >&2
        rm -f "${output_file}"
        return 1
      fi
      if ! grep -Fq "es9.images.${image_name}" "${output_file}"; then
        cat "${output_file}" >&2
        rm -f "${output_file}"
        return 1
      fi
      rm -f "${output_file}"
    done
    echo "all-required-digests-fail-closed=true"
  }

  It "fails closed for each missing 9.x immutable image digest"
    When call verify_each_missing_digest_fails
    The output should eq "all-required-digests-fail-closed=true"
    The status should be success
  End

  It "rejects a mutable 9.x image tag"
    When call render_with_digests --set-string es9.images.plugin=docker.io/apecloud/elasticsearch-plugins:9.3.2
    The status should be failure
    The error should include "es9.images.plugin"
  End

  render_cluster_components() {
    mode=$1
    helm template elasticsearch "${cluster_chart}" --set version=9.3.2 --set mode="${mode}" |
      ruby -ryaml -e '
        cluster = YAML.load_stream(ARGF.read).compact.find { |item| item["kind"] == "Cluster" }
        abort "Cluster not rendered" unless cluster
        puts cluster.dig("spec", "componentSpecs").map { |item| "#{item["name"]}=#{item["componentDef"]}:#{item["serviceVersion"]}" }.join(",")
      '
  }

  It "renders the official single-node direct-CMPD entry for 9.3.2"
    When call render_cluster_components single-node
    The output should eq "mdit=elasticsearch-9:9.3.2,kibana=kibana-9:9.3.2"
    The status should be success
  End

  It "renders the official multi-node direct-CMPD entry for 9.3.2"
    When call render_cluster_components multi-node
    The output should eq "master=elasticsearch-master-9:9.3.2,data=elasticsearch-data-9:9.3.2,kibana=kibana-9:9.3.2"
    The status should be success
  End

  It "rejects an undeclared 9.x service version at render time"
    When run helm template elasticsearch "${cluster_chart}" --set version=9.4.0 --set mode=single-node
    The status should be failure
    The error should include "9.4.0"
  End

  It "keeps the template fail gate when schema validation is bypassed"
    When run helm template elasticsearch "${cluster_chart}" --skip-schema-validation --set version=9.4.0 --set mode=single-node
    The status should be failure
    The error should include "only Elasticsearch 9.3.2"
  End


  It "rejects an unsupported 9.x mode when schema validation is bypassed"
    When run helm template elasticsearch "${cluster_chart}" --skip-schema-validation --set version=9.3.2 --set mode=mdit
    The status should be failure
    The error should include "only single-node and multi-node modes"
  End
End
