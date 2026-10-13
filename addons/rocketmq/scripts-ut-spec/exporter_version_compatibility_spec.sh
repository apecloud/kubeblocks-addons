# shellcheck shell=bash

Describe "RocketMQ exporter version compatibility"
  render_exporter_version_contract() {
    helm dependency build .. >/dev/null || return
    helm template rocketmq .. --show-only templates/cmpv-exporter.yaml | ruby -ryaml -e '
      version = YAML.load_stream(ARGF.read).compact.find do |document|
        document["kind"] == "ComponentVersion" &&
          document.dig("metadata", "name") == "rocketmq-exporter"
      end
      abort "rocketmq-exporter ComponentVersion not rendered" unless version

      release = version.dig("spec", "releases").find do |item|
        item["name"] == "rocketmq-exporter-0.0.3"
      end
      abort "rocketmq-exporter-0.0.3 release not rendered" unless release

      selectors = version.dig("spec", "compatibilityRules").select do |rule|
        rule["releases"].include?(release["name"])
      end.flat_map { |rule| rule["compDefs"] }.sort

      puts "service_version=#{release["serviceVersion"]}"
      puts "selectors=#{selectors.join(",")}"
    '
  }

  It "keeps the retained 1.0 identity compatible with exporter 0.0.3"
    When call render_exporter_version_contract
    The output should eq "service_version=0.0.3
selectors=rocketmq-exporter-1.0.3,rocketmq-exporter-1.2.0-alpha.0"
    The status should be success
  End
End
