# shellcheck shell=sh
# shellcheck disable=SC2016

Describe "Standalone PgBouncer chart"
  prepare_charts() {
    helm dependency build .. --skip-refresh >/dev/null || return
    helm dependency build ../../../addons-cluster/pgbouncer --skip-refresh >/dev/null
  }
  BeforeAll 'prepare_charts'

  backend_contract() {
    RUBYOPT=-W0 ruby -ryaml -ropen3 -e '
      render = lambda do |*values|
        command = ["helm", "template", "pool", "../../../addons-cluster/pgbouncer", "--namespace", "demo", "--set", "postgresql.cluster=backend"]
        values.each { |value| command.concat(["--set", value]) }
        output, error, status = Open3.capture3(*command)
        abort error unless status.success?
        YAML.load_stream(output).compact.find { |doc| doc["kind"] == "Cluster" }.fetch("spec")
      end
      %w[rw ro].each do |role|
        values = ["backend.role=#{role}", "replicas=3", "cpu=1", "memory=2"]
        values.concat(["postgresql.service=replica-access", "postgresql.port=replica-port"]) if role == "ro"
        spec = render.call(*values)
        abort unless spec["clusterDef"] == "pgbouncer" && spec["topology"] == role
        pool = spec.fetch("componentSpecs").fetch(0)
        abort unless pool["name"] == "pgbouncer" && pool["replicas"] == 3
        abort unless pool.dig("resources", "limits") == {"cpu" => "1", "memory" => "2Gi"}
        abort unless pool.fetch("env").include?({"name" => "PGBOUNCER_BACKEND_ROLE", "value" => role})
        ref = pool.fetch("serviceRefs").fetch(0)
        abort unless ref["namespace"] == "demo" && ref["name"] == "postgresql"
        selector = ref.fetch("clusterServiceSelector")
        abort unless selector["cluster"] == "backend"
        expected = role == "ro" ? {"service" => "replica-access", "port" => "replica-port"} : {"component" => "postgresql", "service" => "postgresql", "port" => "tcp-postgresql"}
        abort unless selector["service"] == expected
        abort unless selector["credential"] == {"component" => "postgresql", "name" => "postgres"}
        abort if pool.key?("volumeClaimTemplates")
      end
      puts "ok"
    '
  }

  invalid_backend_contract() {
    RUBYOPT=-W0 ruby -ropen3 -e '
      ["postgresql.cluster=", "backend.role=invalid", "backend.role=ro", "postgresql.namespace=other", "postgresql.service=postgresql-ro", "replicas=0"].each do |value|
        _, _, status = Open3.capture3("helm", "template", "pool", "../../../addons-cluster/pgbouncer", "--namespace", "demo", "--set", "postgresql.cluster=backend", "--set", value)
        abort "accepted #{value}" if status.success?
      end
      puts "ok"
    '
  }

  definition_contract() {
    helm template addon .. | RUBYOPT=-W0 ruby -ryaml -e '
      docs = YAML.load_stream(ARGF.read).compact
      definition = docs.find { |doc| doc["kind"] == "ComponentDefinition" }.fetch("spec")
      abort unless definition["serviceKind"] == "pgbouncer"
      refs = definition.fetch("vars").select { |var| var["name"].start_with?("POSTGRESQL_") }
      abort unless refs.size == 4 && refs.all? { |var| var.dig("valueFrom", "serviceRefVarRef", "name") == "postgresql" }
      abort unless definition.fetch("systemAccounts").map { |account| account["name"] } == ["pgbouncer"]
      abort unless definition.dig("runtime", "containers", 0, "readinessProbe", "exec", "command") == ["/kb-scripts/pgbouncer-readiness.sh"]
      version = docs.find { |doc| doc["kind"] == "ComponentVersion" }
      abort unless version.dig("spec", "releases", 0, "images", "pgbouncer") == "docker.io/apecloud/pgbouncer:1.25.2"
      puts "ok"
    '
  }

  It "routes read/write and read-only instances to their respective services"
    When call backend_contract
    The status should be success
    The output should eq "ok"
  End

  It "rejects missing backends or replica services, conflicting primary services and cross-namespace credentials"
    When call invalid_backend_contract
    The status should be success
    The output should eq "ok"
  End

  It "resolves backend credentials independently from local management credentials"
    When call definition_contract
    The status should be success
    The output should eq "ok"
  End
End
