# shellcheck shell=bash

Describe "RabbitMQ root account schema upgrade identity"
  validate_account_upgrade_identity() {
    ruby -ryaml -ropen3 -rtmpdir -rfileutils -e '
      def render(path)
        output, error, status = Open3.capture3("helm", "template", "rmq-upgrade", path, "--namespace", "demo")
        abort error unless status.success?
        YAML.load_stream(output).compact
      end
      objects = render("..")
      definition = objects.find { |d| d["kind"] == "ComponentDefinition" }
      name = definition.fetch("metadata").fetch("name")
      abort "passwordConfig reuses the immutable alpha.1 definition" if name == "rabbitmq-1.2.0-alpha.1"
      annotations = definition.fetch("metadata").fetch("annotations")
      abort "old definitions must be retained by default" unless annotations["helm.sh/resource-policy"] == "keep"
      abort "immutable validation must not be bypassed" if annotations["apps.kubeblocks.io/skip-immutable-check"].to_s.downcase == "true"
      root = definition.fetch("spec").fetch("systemAccounts").find { |a| a["name"] == "root" }
      abort "new definition lacks passwordConfig" unless root["passwordConfig"] && !root.key?("passwordGenerationPolicy")
      parameters = objects.find { |d| d["kind"] == "ParametersDefinition" }
      abort "parameters target another definition" unless parameters.fetch("spec").fetch("componentDef") == name
      versions = objects.find { |d| d["kind"] == "ComponentVersion" }
      compatible = versions.fetch("spec").fetch("compatibilityRules").any? do |rule|
        rule.fetch("compDefs").any? { |pattern| Regexp.new(pattern).match?(name) }
      end
      abort "ComponentVersion does not cover the new definition" unless compatible
      Dir.mktmpdir("rabbitmq-upgrade-chart") do |directory|
        chart = File.join(directory, "rabbitmq")
        FileUtils.cp_r("../../../addons-cluster/rabbitmq", chart)
        FileUtils.mkdir_p(File.join(chart, "charts"))
        FileUtils.cp_r("../../../addons-cluster/kblib", File.join(chart, "charts", "kblib"))
        cluster = render(chart).find { |d| d["kind"] == "Cluster" }
        target = cluster.fetch("spec").fetch("componentSpecs").find { |c| c["name"] == "rabbitmq" }
        abort "Cluster chart still targets the old definition" unless target.fetch("componentDef") == name
      end
      puts "new root account definition and Cluster references agree"
    '
  }

  It "creates a new immutable definition and aligns the Cluster and parameter references"
    When call validate_account_upgrade_identity
    The status should be success
    The output should include "new root account definition and Cluster references agree"
  End
End
