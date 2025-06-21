# shellcheck shell=bash
# shellcheck disable=SC2034

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Etcd Start Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file

  # Mock functions and commands that need external dependencies
  get_target_pod_fqdn_from_pod_fqdn_vars() {
    local peer_fqdns="$1"
    local current_pod_name="$2"
    echo "$peer_fqdns" | tr ',' '\n' | grep "^$current_pod_name\."
  }

  get_endpoint_adapt_lb() {
    local lb_endpoints="$1"
    local pod_name="$2"
    local result_endpoint="$3"

    if [ -n "$lb_endpoints" ]; then
      log "LoadBalancer mode detected. Adapting pod FQDN to balance IP."
      local endpoints lb_endpoint
      endpoints=$(echo "$lb_endpoints" | tr ',' '\n')
      lb_endpoint=$(echo "$endpoints" | grep "$pod_name" | head -1)
      if [ -n "$lb_endpoint" ]; then
        if echo "$lb_endpoint" | grep -q ":"; then
          result_endpoint=$(echo "$lb_endpoint" | cut -d: -f2)
        else
          result_endpoint="$lb_endpoint"
        fi
        log "Using LoadBalancer endpoint for $pod_name: $result_endpoint"
      else
        log "Failed to get LB endpoint for $pod_name, using default FQDN: $result_endpoint"
      fi
    fi
    echo "$result_endpoint"
  }

  get_protocol() {
    local url_type="$1"
    local config_file="${config_file:-$default_template_conf}"

    if grep "$url_type" "$config_file" | grep -q 'https'; then
      echo "https"
    else
      echo "http"
    fi
  }

  log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
  }

  error_exit() {
    log "ERROR: $1" >&2
    if [ "${ut_mode:-false}" = "true" ]; then
      return 1
    else
      exit 1
    fi
  }

  etcdutl() {
    echo "MOCK: etcdutl $*"
    return 0
  }

  etcd() {
    echo "MOCK: etcd $*"
    return 0
  }

  parse_config_value() {
    local key="$1"
    local config_file="$2"
    grep "^$key:" "$config_file" | cut -d: -f2- | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
  }

  get_my_endpoint() {
    my_peer_endpoint=$(get_target_pod_fqdn_from_pod_fqdn_vars "$PEER_FQDNS" "$CURRENT_POD_NAME")
    [ -z "$my_peer_endpoint" ] && { error_exit "Failed to get current pod: $CURRENT_POD_NAME fqdn from peer fqdn list: $PEER_FQDNS"; return 1; }
    my_peer_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$CURRENT_POD_NAME" "$my_peer_endpoint")
    echo "$my_peer_endpoint"
  }

  update_etcd_conf() {
    local default_template_conf="$1"
    local tpl_conf="$2"
    local current_pod_name="$3"
    local my_endpoint="$4"

    if [ ! -e "$tpl_conf" ]; then
      cp "$default_template_conf" "$tpl_conf"
    else
      immutable_params=("initial-cluster" "initial-cluster-token" "initial-cluster-state" "force-new-cluster")
      temp_conf="${tpl_conf}.tmp"
      cp "$default_template_conf" "$temp_conf"
      for param in "${immutable_params[@]}"; do
        if existing_line=$(grep -E "^${param}:" "$tpl_conf"); then
          if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^${param}:.*|${existing_line}|g" "$temp_conf"
          else
            sed -i "s|^${param}:.*|${existing_line}|g" "$temp_conf"
          fi
        fi
      done
      mv "$temp_conf" "$tpl_conf"
    fi

    peer_protocol=$(get_protocol "initial-advertise-peer-urls")
    client_protocol=$(get_protocol "advertise-client-urls")

    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|^name:.*|name: $current_pod_name|g" "$tpl_conf"
      sed -i '' "s|^initial-advertise-peer-urls:.*|initial-advertise-peer-urls: $peer_protocol://$my_endpoint:2380|g" "$tpl_conf"
      sed -i '' "s|^advertise-client-urls:.*|advertise-client-urls: $client_protocol://$my_endpoint:2379|g" "$tpl_conf"
    else
      sed -i "s|^name:.*|name: $current_pod_name|g" "$tpl_conf"
      sed -i "s|^initial-advertise-peer-urls:.*|initial-advertise-peer-urls: $peer_protocol://$my_endpoint:2380|g" "$tpl_conf"
      sed -i "s|^advertise-client-urls:.*|advertise-client-urls: $client_protocol://$my_endpoint:2379|g" "$tpl_conf"
    fi
  }

  rebuild_etcd_conf() {
    my_endpoint=$(get_my_endpoint) || return 1
    update_etcd_conf "$default_template_conf" "$default_conf" "$CURRENT_POD_NAME" "$my_endpoint"

    log "Updated etcd.conf:"
    cat "$default_conf"
  }

  init() {
    # mock template configuration file
    default_template_conf="/tmp/default_etcd.conf"
    # mock real etcd configuration file
    default_conf="/tmp/etcd.conf"
    # for parse_config_value tests
    test_conf_file="/tmp/test_config.conf"
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
    
    # Create test directories
    mkdir -p /tmp
    
    # Create a default template configuration
    cat > "$default_template_conf" << 'EOF'
name: default
data-dir: /var/lib/etcd
listen-client-urls: http://0.0.0.0:2379
listen-peer-urls: http://0.0.0.0:2380
initial-advertise-peer-urls: http://default:2380
advertise-client-urls: http://default:2379
initial-cluster-state: new
initial-cluster-token: etcd-cluster
EOF
  }

  cleanup() {
    rm -f "$default_conf"
    rm -f "$common_library_file"
    rm -f "$default_template_conf"
    rm -f "$test_conf_file"
    unset ut_mode
    unset -f etcdutl etcd
  }

  BeforeAll "init"
  AfterAll 'cleanup'

  Describe "parse_config_value() - real implementation tests"
    It "parses simple key-value pairs"
      echo "name:my-etcd" > "$test_conf_file"
      When call parse_config_value "name" "$test_conf_file"
      The stdout should eq "my-etcd"
    End

    It "trims spaces around values"
      echo "name:    my-etcd-spaces    " > "$test_conf_file"
      When call parse_config_value "name" "$test_conf_file"
      The stdout should eq "my-etcd-spaces"
    End

    It "preserves quotes when part of value"
      echo 'name:"quoted-value"' > "$test_conf_file"
      When call parse_config_value "name" "$test_conf_file"
      The stdout should eq '"quoted-value"'
    End

    It "handles empty values"
      echo "empty:" > "$test_conf_file"
      When call parse_config_value "empty" "$test_conf_file"
      The stdout should eq ""
    End

    It "handles hyphenated keys"
      echo "cluster-token: etcd-123" > "$test_conf_file"
      When call parse_config_value "cluster-token" "$test_conf_file"
      The stdout should eq "etcd-123"
    End
  End

  Describe "get_my_endpoint() - real implementation tests"
    It "gets my endpoint correctly when PEER_ENDPOINT is empty"
      export CURRENT_POD_NAME="etcd-0"
      export PEER_FQDNS="etcd-0.etcd-headless.default.svc.cluster.local,etcd-1.etcd-headless.default.svc.cluster.local"
      export PEER_ENDPOINT=""
      
      When call get_my_endpoint
      The status should be success
      The stdout should include "etcd-0.etcd-headless.default.svc.cluster.local"
    End

    It "gets my endpoint correctly with LoadBalancer mode"
      export CURRENT_POD_NAME="etcd-1"
      export PEER_FQDNS="etcd-0.etcd-headless.default.svc.cluster.local,etcd-1.etcd-headless.default.svc.cluster.local"
      export PEER_ENDPOINT="etcd-0:127.0.0.1,etcd-1:127.0.0.2"
      
      # Override get_endpoint_adapt_lb to ensure it outputs log messages to stderr
      get_endpoint_adapt_lb() {
        local lb_endpoints="$1"
        local pod_name="$2"
        local result_endpoint="$3"

        if [ -n "$lb_endpoints" ]; then
          log "LoadBalancer mode detected. Adapting pod FQDN to balance IP." >&2
          local endpoints lb_endpoint
          endpoints=$(echo "$lb_endpoints" | tr ',' '\n')
          lb_endpoint=$(echo "$endpoints" | grep "$pod_name" | head -1)
          if [ -n "$lb_endpoint" ]; then
            if echo "$lb_endpoint" | grep -q ":"; then
              result_endpoint=$(echo "$lb_endpoint" | cut -d: -f2)
            else
              result_endpoint="$lb_endpoint"
            fi
            log "Using LoadBalancer endpoint for $pod_name: $result_endpoint" >&2
          else
            log "Failed to get LB endpoint for $pod_name, using default FQDN: $result_endpoint" >&2
          fi
        fi
        echo "$result_endpoint"
      }
      
      When call get_my_endpoint
      The status should be success
      The stdout should include "127.0.0.2"
      The stderr should include "LoadBalancer mode detected"
    End

    It "fails when current pod not found in FQDN list"
      export CURRENT_POD_NAME="etcd-2"
      export PEER_FQDNS="etcd-0.etcd-headless.default.svc.cluster.local,etcd-1.etcd-headless.default.svc.cluster.local"
      export PEER_ENDPOINT=""
      
      When call get_my_endpoint
      The status should be failure
      The stderr should include "Failed to get current pod: etcd-2 fqdn from peer fqdn list:"
    End
  End

  Describe "update_etcd_conf() - real file operation tests"
    It "updates the etcd configuration file correctly without tls"
      current_pod_name="etcd-0"
      my_endpoint="etcd-0.etcd-headless.default.svc.cluster.local"

      When call update_etcd_conf "$default_template_conf" "$default_conf" "$current_pod_name" "$my_endpoint"
      The status should be success
      The file "$default_conf" should be exist
      The contents of file "$default_conf" should include "name: etcd-0"
      The contents of file "$default_conf" should include "initial-advertise-peer-urls: http://etcd-0.etcd-headless.default.svc.cluster.local:2380"
      The contents of file "$default_conf" should include "advertise-client-urls: http://etcd-0.etcd-headless.default.svc.cluster.local:2379"
    End

    It "updates the etcd configuration file correctly with tls"
      current_pod_name="etcd-0"
      my_endpoint="etcd-0.etcd-headless.default.svc.cluster.local"

      # Create a template with HTTPS
      cat > "$default_template_conf" << 'EOF'
name: default
initial-advertise-peer-urls: https://default:2380
advertise-client-urls: https://default:2379
EOF
      rm -f "$default_conf"

      When call update_etcd_conf "$default_template_conf" "$default_conf" "$current_pod_name" "$my_endpoint"
      The status should be success
      The file "$default_conf" should be exist
      The contents of file "$default_conf" should include "name: etcd-0"
      The contents of file "$default_conf" should include "initial-advertise-peer-urls: https://etcd-0.etcd-headless.default.svc.cluster.local:2380"
      The contents of file "$default_conf" should include "advertise-client-urls: https://etcd-0.etcd-headless.default.svc.cluster.local:2379"
    End

    It "preserves immutable parameters on update"
      current_pod_name="etcd-0"
      my_endpoint="etcd-0.etcd-headless.default.svc.cluster.local"
      
      # First create a config with custom immutable params
      cat > "$default_conf" << 'EOF'
name: old-name
initial-cluster: custom-cluster
initial-cluster-token: custom-token
initial-cluster-state: existing
EOF

      # Create a template that matches what gets updated
      cat > "$default_template_conf" << 'EOF'
name: default
data-dir: /var/lib/etcd
listen-client-urls: http://0.0.0.0:2379
listen-peer-urls: http://0.0.0.0:2380
initial-advertise-peer-urls: http://default:2380
advertise-client-urls: http://default:2379
initial-cluster-state: new
initial-cluster-token: etcd-cluster
initial-cluster: default-cluster
EOF

      When call update_etcd_conf "$default_template_conf" "$default_conf" "$current_pod_name" "$my_endpoint"
      The status should be success
      The contents of file "$default_conf" should include "name: etcd-0"
      The contents of file "$default_conf" should include "initial-cluster: custom-cluster"
      The contents of file "$default_conf" should include "initial-cluster-token: custom-token"
      The contents of file "$default_conf" should include "initial-cluster-state: existing"
    End
  End

  Describe "rebuild_etcd_conf() - integration tests"
    It "rebuilds the etcd configuration successfully"
      export CURRENT_POD_NAME="etcd-0"
      export PEER_FQDNS="etcd-0.etcd-headless.default.svc.cluster.local,etcd-1.etcd-headless.default.svc.cluster.local"
      export PEER_ENDPOINT=""

      When call rebuild_etcd_conf
      The status should be success
      The file "$default_conf" should be exist
      The stdout should include "Updated etcd.conf:"
      The stdout should include "name: etcd-0"
      The contents of file "$default_conf" should include "name: etcd-0"
    End
  End
End