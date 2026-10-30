# shellcheck shell=bash
Describe "PostgreSQL backup policies for the optional PgBouncer component"
  matched_backends() {
    helm template kb-addon-postgresql .. --namespace kb-system --dependency-update |
      ruby -ryaml -e '
        documents = YAML.load_stream(ARGF.read).compact
        policy = documents.find { |item| item["kind"] == "BackupPolicyTemplate" }.fetch("spec")
        patterns = policy.fetch("compDefs").map { |pattern| Regexp.new(pattern) }
        definitions = documents.select { |item| item["kind"] == "ComponentDefinition" }
        definitions.each do |definition|
          matched = patterns.any? { |pattern| pattern.match?(definition.fetch("metadata").fetch("name")) }
          backend = definition.dig("spec", "serviceKind").to_s.downcase == "postgresql"
          abort "incorrect backup policy target" unless matched == backend
        end
        puts definitions.count { |definition| definition.dig("spec", "serviceKind").to_s.downcase == "postgresql" }
      '
  }
  It "covers all seven PostgreSQL versions and excludes the pooler"
    When call matched_backends
    The status should be success
    The output should eq "7"
  End
End
