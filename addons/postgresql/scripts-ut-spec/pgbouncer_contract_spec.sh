# shellcheck shell=sh
# shellcheck disable=SC2016

Describe "PostgreSQL optional PgBouncer contract"

  chart_dir() {
    printf '%s' '..'
  }

  cluster_chart_dir() {
    printf '%s' '../../../addons-cluster/postgresql'
  }

  render_chart() {
    helm dependency build "$(chart_dir)" --skip-refresh >/dev/null || return
    helm template kb-addon-postgresql "$(chart_dir)" --namespace kb-system
  }

  pgbouncer_cluster_chart_contract() {
    helm dependency build "$(cluster_chart_dir)" --skip-refresh >/dev/null || return
    RUBYOPT=-W0 ruby -ryaml -ropen3 -e '
      chart = ARGV.fetch(0)
      render = lambda do |values|
        command = ["helm", "template", "pg-test", chart, "--namespace", "demo"]
        values.each { |value| command.concat(["--set", value]) }
        output, error, status = Open3.capture3(*command)
        abort error unless status.success?
        YAML.load_stream(output).compact.find { |doc| doc["kind"] == "Cluster" }.fetch("spec")
      end
      defaults = render.call([])
      abort unless defaults["componentSpecs"].map { |c| c["name"] } == ["postgresql"]
      abort unless render.call(["pgbouncer.replicas=2"]) == defaults

      [[], ["mode=standalone"], ["remoteSetting.isStandby=true", "remoteSetting.primaryHost=primary", "remoteSetting.primaryPort=5432"],
       ["etcd.enabled=true", "systemAccountSecret.postgres.name=pg-account", "systemAccountSecret.postgres.namespace=demo"]].each do |values|
        baseline = render.call(values)
        enabled = render.call(values + ["pgbouncer.enabled=true"])
        pool = enabled.fetch("componentSpecs").pop
        abort unless enabled == baseline
        abort unless pool == {"name" => "pgbouncer", "replicas" => 0, "resources" => {
          "limits" => {"cpu" => "0.5", "memory" => "0.5Gi"},
          "requests" => {"cpu" => "0.5", "memory" => "0.5Gi"}}}
      end

      custom = render.call(["pgbouncer.enabled=true", "pgbouncer.replicas=3", "pgbouncer.version=1.25.2",
        "pgbouncer.cpu=1", "pgbouncer.memory=2", "pgbouncer.requests.cpu=0.1", "pgbouncer.requests.memory=0.25"])
      pool = custom.fetch("componentSpecs").pop
      abort unless custom == defaults
      abort unless pool == {"name" => "pgbouncer", "replicas" => 3, "serviceVersion" => "1.25.2", "resources" => {
        "limits" => {"cpu" => "1", "memory" => "2Gi"},
        "requests" => {"cpu" => "0.1", "memory" => "0.25Gi"}}}

      %w[replicas=-1 replicas=65 replicas=1.5 enabled=yes cpu=invalid cpu=0 memory=-1 requests.cpu=0 requests.memory=invalid].each do |invalid|
        _, error, status = Open3.capture3("helm", "template", "pg-test", chart, "--set", "pgbouncer.#{invalid}")
        abort "accepted #{invalid}" if status.success?
        abort error unless error.include?("pgbouncer") && error.include?("schema")
      end
      puts "ok"
    ' "$(cluster_chart_dir)"
  }

  pgbouncer_component_contract() {
    render_chart | RUBYOPT=-W0 ruby -ryaml -e '
      documents = YAML.load_stream(ARGF.read).compact
      cluster_definition = documents.find { |document| document["kind"] == "ClusterDefinition" }
      topologies = cluster_definition.dig("spec", "topologies")
      abort unless topologies.map { |topology| topology["name"] } == ["replication"]
      replication = topologies.first
      abort unless replication["components"] == [
        {"name" => "postgresql", "compDef" => "postgresql-"},
        {"name" => "pgbouncer", "compDef" => "pgbouncer-1.2.0-alpha.6"}
      ]

      definitions = documents.select { |document| document["kind"] == "ComponentDefinition" }
      postgres = definitions.find { |definition| definition.dig("metadata", "name") == "postgresql-14-1.2.0-alpha.6" }
      pgbouncer = definitions.find { |definition| definition.dig("metadata", "name") == "pgbouncer-1.2.0-alpha.6" }
      abort unless pgbouncer.dig("spec", "replicasLimit") == {"minReplicas" => 0, "maxReplicas" => 64}
      abort unless pgbouncer.dig("spec", "serviceVersion") == "1.25.2"
      abort unless pgbouncer.dig("spec", "services", 0, "spec", "ports", 0, "port") == 6432
      abort if pgbouncer.dig("spec", "services", 0).key?("serviceName")
      resources = pgbouncer.dig("spec", "runtime", "containers", 0, "resources")
      abort unless resources == {
        "requests" => {"cpu" => "100m", "memory" => "128Mi"},
        "limits" => {"cpu" => "500m", "memory" => "512Mi"}
      }
      refs = pgbouncer.dig("spec", "vars").map do |var|
        var.dig("valueFrom", "serviceVarRef", "compDef") || var.dig("valueFrom", "credentialVarRef", "compDef")
      end.compact
      abort unless refs == Array.new(4, "postgresql-")
      abort if pgbouncer.dig("spec", "vars").any? { |var| var["name"].start_with?("PGBOUNCER_") }
      configs = pgbouncer.dig("spec", "configs")
      abort unless configs.map { |config| config["name"] } == ["pgbouncer-configuration"]
      abort unless configs.all? { |config| config["externalManaged"] == true && config["defaultMode"] == 0444 }
      abort if configs.any? { |config| config.key?("restartOnFileChange") }
      abort unless configs.map { |config| config["volumeName"] } == ["pgbouncer-config"]

      postgres_ports = postgres.dig("spec", "services", 0, "spec", "ports").map { |port| port["port"] }
      abort unless postgres_ports == [5432]
      postgres_containers = postgres.dig("spec", "runtime", "containers").map { |container| container["name"] }
      abort if postgres_containers.include?("pgbouncer")
      abort if documents.any? { |document| document["kind"] == "ParamConfigRenderer" }
      pgbouncer_pd = documents.find do |document|
        document["kind"] == "ParametersDefinition" &&
          document.dig("metadata", "name") == "pgbouncer-pd-1.2.0-alpha.6"
      end
      exposed = %w[
        pool_mode max_client_conn default_pool_size min_pool_size
        reserve_pool_size max_db_connections max_user_connections
        server_tls_sslmode
      ]
      abort unless pgbouncer_pd.dig("spec", "fileName") == "pgbouncer.ini"
      abort unless pgbouncer_pd.dig("spec", "dynamicParameters") == exposed
      abort unless pgbouncer_pd.dig("spec", "parametersSchema", "topLevelKey") == "PgBouncerParameter"
      abort if pgbouncer_pd.fetch("spec").key?("reloadAction")
      abort unless pgbouncer_pd.dig("spec", "componentDef") == pgbouncer.dig("metadata", "name")
      abort unless pgbouncer_pd.dig("spec", "serviceVersion") == "1.25.2"
      abort unless pgbouncer_pd.dig("spec", "templateName") == configs.first.fetch("name")
      abort unless pgbouncer_pd.dig("spec", "fileFormatConfig") == {"format" => "ini", "iniConfig" => {"sectionName" => "pgbouncer"}}
      reload_action = configs.first.dig("reconfigure", "exec")
      abort unless reload_action["container"] == "pgbouncer" && reload_action["targetPodSelector"] == "All"
      abort unless reload_action["command"].last.include?("--dbname=pgbouncer")
      abort unless reload_action["command"].last.include?("--set=ON_ERROR_STOP=1")
      abort unless reload_action["command"].last.include?("RELOAD;")
      abort if pgbouncer_pd.dig("spec").key?("staticParameters")
      pgbouncer_schema = pgbouncer_pd.dig("spec", "parametersSchema", "cue")
      exposed.each { |parameter| abort unless pgbouncer_schema.include?(parameter) }
      abort unless pgbouncer_schema.include?(%q{pool_mode?: "session" | "transaction" | "statement" | *"session"})
      abort unless pgbouncer_schema.include?("max_client_conn?: int & >=1 & <=999999 | *500")
      abort unless pgbouncer_schema.include?("max_db_connections?: int & >=0 & <=999999 | *80")
      abort unless pgbouncer_schema.include?(%q{server_tls_sslmode?: "disable" | "require" | "verify-ca" | "verify-full" | *"disable"})
      abort unless pgbouncer_schema.include?("#PgBouncerConfiguration: {\n\tpgbouncer: #PgBouncerConfig\n}")
      abort unless pgbouncer_schema.include?("configuration: #PgBouncerConfiguration")
      abort unless pgbouncer_schema.include?(%q{auth_type:                 "md5"})
      abort if pgbouncer_schema.match?(/^\s*\.\.\.\s*$/)
      account_refs = pgbouncer.dig("spec", "vars").map { |var| var.dig("valueFrom", "credentialVarRef", "name") }.compact
      abort unless account_refs == ["postgres", "postgres"]
      probe = pgbouncer.dig("spec", "runtime", "containers", 0, "readinessProbe", "exec", "command", -1)
      abort unless probe.include?("--port=6432") && probe.include?("$POSTGRESQL_USERNAME")
      abort unless probe.include?("$CURRENT_POD_IP") && probe.include?("NOT pg_is_in_recovery()")
      abort unless probe.include?("current_setting(\u0027transaction_read_only\u0027) = \u0027off\u0027")
      abort if probe.include?("budget-ready") || probe.include?("budget-sync")
      readiness = pgbouncer.dig("spec", "runtime", "containers", 0, "readinessProbe")
      abort unless readiness["failureThreshold"] == 1 && readiness["periodSeconds"] == 5
      pod_security = pgbouncer.dig("spec", "runtime", "securityContext")
      abort unless pod_security == {
        "runAsUser" => 70, "runAsGroup" => 70,
        "fsGroup" => 70, "fsGroupChangePolicy" => "OnRootMismatch"
      }
      volumes = pgbouncer.dig("spec", "runtime", "volumes")
      abort unless volumes == [{"name" => "pgbouncer-state", "emptyDir" => {}}]
      container = pgbouncer.dig("spec", "runtime", "containers", 0)
      container_security = container["securityContext"]
      abort unless container_security["runAsNonRoot"] == true
      abort unless container_security["runAsUser"] == 70 && container_security["runAsGroup"] == 70
      abort unless container_security["allowPrivilegeEscalation"] == false
      abort unless container_security.dig("capabilities", "drop") == ["ALL"]
      config_mount = container["volumeMounts"].find { |mount| mount["name"] == "pgbouncer-config" }
      abort unless config_mount["mountPath"] == "/opt/pgbouncer-template"
      state_mount = container["volumeMounts"].find { |mount| mount["name"] == "pgbouncer-state" }
      abort unless state_mount["mountPath"] == "/etc/pgbouncer"
      tls_mount = container["volumeMounts"].find { |mount| mount["name"] == "pgbouncer-tls" }
      abort if tls_mount
      abort unless pgbouncer.dig("spec", "tls") == {
        "volumeName" => "pgbouncer-tls", "mountPath" => "/etc/pgbouncer/tls",
        "defaultMode" => 0444, "caFile" => "ca.pem"
      }
      abort if container["volumeMounts"].any? { |mount| mount["mountPath"] == "/var/run/pgbouncer" }
      env = pgbouncer.dig("spec", "runtime", "containers", 0, "env")
      pod_ip = env.find { |entry| entry["name"] == "CURRENT_POD_IP" }
      abort unless pod_ip.dig("valueFrom", "fieldRef", "fieldPath") == "status.podIP"
      abort unless env.map { |entry| entry["name"] } == [
        "CURRENT_POD_IP", "POSTGRESQL_HOST", "POSTGRESQL_PORT", "POSTGRESQL_USERNAME", "POSTGRESQL_PASSWORD"
      ]
      pgbouncer_config = documents.find do |document|
        document["kind"] == "ConfigMap" &&
          document.dig("metadata", "name") == "pgbouncer-configuration-1.2.0-alpha.6"
      end.dig("data", "pgbouncer.ini")
      abort unless pgbouncer_config.lines.any? { |line| line.match?(/^\s*listen_addr\s*=\s*\*\s*$/) }
      abort unless pgbouncer_config.lines.any? { |line| line.match?(/^\s*client_tls_sslmode\s*=\s*disable\s*$/) }
      abort unless pgbouncer_config.lines.any? { |line| line.match?(/^\s*server_tls_sslmode\s*=\s*disable\s*$/) }
      abort unless pgbouncer_config.include?("server_tls_ca_file = /etc/pgbouncer/tls/ca.pem")
      abort unless pgbouncer_config.include?("auth_file = /etc/pgbouncer/userlist.txt")
      abort unless pgbouncer_config.include?("FROM pg_catalog.pg_authid")
      abort unless pgbouncer_config.include?("rolvaliduntil") && pgbouncer_config.include?("rolcanlogin")
      abort if pgbouncer_config.match?(/^\s*pidfile\s*=/)
      abort if pgbouncer_config.include?("{{")
      abort unless pgbouncer_config.include?("pool_mode = session")
      abort unless pgbouncer_config.include?("max_client_conn = 500")
      abort unless pgbouncer_config.include?("default_pool_size = 20")
      abort unless pgbouncer_config.include?("min_pool_size = 5")
      abort unless pgbouncer_config.include?("reserve_pool_size = 5")
      abort unless pgbouncer_config.include?("max_db_connections = 80")
      abort unless pgbouncer_config.include?("max_user_connections = 80")
      abort if pgbouncer_config.lines.any? { |line| line.match?(/^\s*logfile\s*=\s*\/dev\/stderr\s*$/) }
      main_config = documents.find do |document|
        document["kind"] == "ConfigMap" && document.dig("metadata", "name") == "pgbouncer-configuration-1.2.0-alpha.6"
      end
      abort unless main_config["data"].keys == ["pgbouncer.ini"]
      abort if documents.any? do |document|
        document["kind"] == "ConfigMap" && document.dig("metadata", "name").to_s.include?("pgbouncer-budget")
      end

      version = documents.find do |document|
        document["kind"] == "ComponentVersion" && document.dig("metadata", "name") == "pgbouncer"
      end
      abort unless version.dig("spec", "compatibilityRules", 0, "compDefs") == ["pgbouncer-"]
      release = version.dig("spec", "releases", 0)
      abort unless release["name"] == "1.25.2" && release["serviceVersion"] == "1.25.2"
      abort unless release.dig("images", "pgbouncer") == "docker.io/apecloud/pgbouncer:1.25.2"
      postgres_version = documents.find do |document|
        document["kind"] == "ComponentVersion" && document.dig("metadata", "name") == "postgresql"
      end
      abort unless postgres_version["spec"]["releases"].all? do |postgres_release|
        postgres_release.dig("images", "pgbouncer") == "docker.io/apecloud/pgbouncer:1.19.0"
      end
      puts "ok"
    '
  }

  pgbouncer_image_and_pull_policy_contract() {
    helm template kb-addon-postgresql "$(chart_dir)" --namespace kb-system --dependency-update \
      --set pgbouncer.componentImage.versions[0].version=1.25.2 \
      --set pgbouncer.componentImage.versions[0].tag=1.25.2 \
      --set pgbouncer.componentImage.versions[0].isDefault=false \
      --set pgbouncer.componentImage.versions[1].version=1.25.2-test \
      --set pgbouncer.componentImage.versions[1].tag=1.25.2-test \
      --set pgbouncer.componentImage.versions[1].isDefault=true \
      --set pgbouncer.componentImage.pullPolicy=Always | RUBYOPT=-W0 ruby -ryaml -e '
        documents = YAML.load_stream(ARGF.read).compact
        version = documents.find { |document| document["kind"] == "ComponentVersion" && document.dig("metadata", "name") == "pgbouncer" }
        abort unless version.dig("spec", "compatibilityRules", 0, "releases") == ["1.25.2", "1.25.2-test"]
        abort unless version.dig("spec", "releases").map { |release| release["name"] } == ["1.25.2", "1.25.2-test"]
        abort unless version.dig("spec", "releases", 0, "images", "pgbouncer") == "docker.io/apecloud/pgbouncer:1.25.2"
        abort unless version.dig("spec", "releases", 1, "images", "pgbouncer") == "docker.io/apecloud/pgbouncer:1.25.2-test"
        definition = documents.find { |document| document["kind"] == "ComponentDefinition" && document.dig("metadata", "name") == "pgbouncer-1.2.0-alpha.6" }
        abort unless definition.dig("spec", "serviceVersion") == "1.25.2-test"
        abort unless definition.dig("spec", "runtime", "containers", 0, "imagePullPolicy") == "Always"
        puts "ok"
      '
  }

  It "keeps the release-1.0 runtime with the KB 1.2 parameter API"
    When call pgbouncer_component_contract
    The status should eq 0
    The output should eq "ok"
  End

  It "renders optional PgBouncer and validates independent resources"
    When call pgbouncer_cluster_chart_contract
    The status should eq 0
    The output should eq "ok"
  End

  It "resolves independent PgBouncer versions and image overrides"
    When call pgbouncer_image_and_pull_policy_contract
    The status should eq 0
    The output should eq "ok"
  End
End
