# Fixed account/consumer contract captured before the passwordConfig migration.
require 'yaml'
require 'json'

version, chart_path = ARGV
chart = YAML.load_file(File.join(chart_path, 'Chart.yaml'))
abort 'old immutable definition identity must not be reused' if version == '1.2.0-alpha.0'
abort 'unsupported KubeBlocks product line' unless chart.dig('annotations', 'addon.kubeblocks.io/kubeblocks-version') == '>=1.2.0'
expected = JSON.parse(File.read(File.join(__dir__, 'password_config_expected.json')).gsub('<chart-version>', version))
docs = YAML.load_stream(STDIN.read).compact
definitions = docs.select { |d| d['kind'] == 'ComponentDefinition' }
abort 'missing or extra component definitions' unless definitions.map { |d| d.dig('metadata', 'name') }.sort == expected.keys.sort

definitions.each do |doc|
  name = doc.fetch('metadata').fetch('name')
  abort "#{name}: definitions must be retained by default" unless doc.dig('metadata', 'annotations', 'helm.sh/resource-policy') == 'keep'
  spec = doc.fetch('spec')
  accounts = spec.fetch('systemAccounts', [])
  abort "#{name}: account identity, statement or policy changed" unless accounts == expected.fetch(name).fetch('accounts')
  refs = spec.fetch('vars', []).map do |var|
    ref = var.dig('valueFrom', 'credentialVarRef')
    ref && { 'name' => var.fetch('name'), 'credentialVarRef' => ref }
  end.compact
  abort "#{name}: credential consumer changed" unless refs == expected.fetch(name).fetch('credentialRefs')
end

# Every new and previous definition must still be selectable by a ComponentVersion.
selectors = docs.select { |d| d['kind'] == 'ComponentVersion' }.flat_map do |d|
  d.fetch('spec').fetch('compatibilityRules').flat_map { |r| r.fetch('compDefs') }
end
expected.keys.each do |name|
  [name, name.sub(version, '1.2.0-alpha.0')].each do |candidate|
    abort "no ComponentVersion matches #{candidate}" unless selectors.any? { |pattern| Regexp.new(pattern).match?(candidate) }
  end
end
abort 'chart must not create or overwrite account Secrets' if docs.any? { |d| d['kind'] == 'Secret' }
