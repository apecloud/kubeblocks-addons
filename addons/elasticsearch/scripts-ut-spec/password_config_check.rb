# Verify rendered chart output, including the consumers of generated passwords.
require 'yaml'

version = ARGV.fetch(0)
abort 'must not overwrite the old account definitions' if version == '1.2.0-alpha.0'
docs = YAML.load_stream(STDIN.read).compact
definitions = docs.select { |doc| doc['kind'] == 'ComponentDefinition' }
by_name = definitions.to_h { |doc| [doc.fetch('metadata').fetch('name'), doc] }
es_names = %w[6 7 8].flat_map do |major|
  %w[elasticsearch elasticsearch-master elasticsearch-data].map { |prefix| "#{prefix}-#{major}-#{version}" }
end
kibana_names = %w[6 7 8].map { |major| "kibana-#{major}-#{version}" }
abort 'unexpected or missing ComponentDefinitions' unless by_name.keys.sort == (es_names + kibana_names).sort
policy = { 'length' => 10, 'numDigits' => 5, 'numSymbols' => 0, 'letterCase' => 'MixedCases' }
expected = %w[elastic kibana_system].map do |name|
  { 'name' => name, 'initAccount' => true, 'passwordConfig' => policy }
end

definitions.each do |doc|
  name = doc.fetch('metadata').fetch('name')
  abort "#{name}: old definitions must be retained by default" unless doc.dig('metadata', 'annotations', 'helm.sh/resource-policy') == 'keep'
  spec = doc.fetch('spec')
  if es_names.include?(name)
    abort "#{name}: password policy or account identity changed" unless spec.fetch('systemAccounts') == expected
  else
    abort "#{name}: Kibana must consume ES accounts, not create its own" if spec.key?('systemAccounts')
  end

  { 'ELASTIC_USER_PASSWORD' => 'elastic', 'KIBANA_SYSTEM_USER_PASSWORD' => 'kibana_system' }.each do |env, account|
    var = spec.fetch('vars').find { |item| item['name'] == env }
    ref = var&.dig('valueFrom', 'credentialVarRef')
    abort "#{name}: missing required #{env}" unless ref && ref['name'] == account && ref['password'] == 'Required' && ref['optional'] == false
    target = if name.start_with?('kibana-')
               '^elasticsearch-'
             elsif name.start_with?('elasticsearch-data-')
               name.sub('elasticsearch-data-', 'elasticsearch-master-')
             else
               name
             end
    abort "#{name}: changed credential target for #{env}" unless ref['compDef'] == target
    if name.start_with?('kibana-')
      abort "#{name}: changed multi-component credential selection" unless ref['multipleClusterObjectOption'] == { 'strategy' => 'individual' }
    else
      abort "#{name}: target does not expose #{account}" unless by_name.fetch(target).dig('spec', 'systemAccounts').any? { |a| a['name'] == account }
    end
  end
end

%w[elasticsearch kibana].each do |family|
  cv = docs.find { |doc| doc['kind'] == 'ComponentVersion' && doc.dig('metadata', 'name') == family }
  rules = cv.fetch('spec').fetch('compatibilityRules')
  cv.fetch('spec').fetch('releases').each do |release|
    major = release.fetch('serviceVersion').split('.').first
    prefixes = family == 'kibana' ? ['kibana'] : %w[elasticsearch elasticsearch-master elasticsearch-data]
    selectors = rules.select { |rule| rule.fetch('releases').include?(release.fetch('name')) }.flat_map { |rule| rule.fetch('compDefs') }
    prefixes.each do |prefix|
      [version, '1.2.0-alpha.0'].each do |chart_version|
        name = "#{prefix}-#{major}-#{chart_version}"
        abort "#{release.fetch('name')}: excludes #{name}" unless selectors.any? { |pattern| Regexp.new(pattern).match?(name) }
      end
    end
  end
end
abort 'chart must not render account Secrets' if docs.any? { |doc| doc['kind'] == 'Secret' }
