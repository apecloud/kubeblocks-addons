# shellcheck shell=sh

Describe "DoltDB metrics integration"
  template_path="../config/server.yaml.tpl"
  standalone_cmpd_path="../templates/cmpd.yaml"
  replication_cmpd_path="../templates/cmpd-replication.yaml"
  cluster_template_path="../../../addons-cluster/doltdb/templates/cluster.yaml"
  cluster_values_path="../../../addons-cluster/doltdb/values.yaml"

  setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    unset TEST_DIR
  }
  AfterEach "cleanup"

  render_template_without_metrics_overrides() {
    go_file="${TEST_DIR}/render_template.go"
    cat >"${go_file}" <<'EOF'
package main

import (
	"bytes"
	"fmt"
	"os"
	"reflect"
	"text/template"
)

func defaultValue(def any, value any) any {
	if isEmpty(value) {
		return def
	}
	return value
}

func isEmpty(value any) bool {
	if value == nil {
		return true
	}
	v := reflect.ValueOf(value)
	switch v.Kind() {
	case reflect.Array, reflect.Map, reflect.Slice, reflect.String:
		return v.Len() == 0
	case reflect.Bool:
		return !v.Bool()
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return v.Int() == 0
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
		return v.Uint() == 0
	case reflect.Float32, reflect.Float64:
		return v.Float() == 0
	case reflect.Interface, reflect.Pointer:
		return v.IsNil()
	case reflect.Invalid:
		return true
	default:
		return false
	}
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: render_template <template-path>")
		os.Exit(2)
	}

	data := map[string]any{
		"DOLT_LOG_LEVEL":                         "info",
		"DOLT_LOG_FORMAT":                        "text",
		"DOLT_READ_ONLY":                         "false",
		"DOLT_AUTOCOMMIT":                        "true",
		"DOLT_TRANSACTION_COMMIT":                "false",
		"DOLT_AUTO_GC_ENABLED":                   "true",
		"DOLT_SQL_PORT":                          "3306",
		"DOLT_MAX_CONNECTIONS":                   "1000",
		"DOLT_BACK_LOG":                          "50",
		"DOLT_MAX_CONNECTIONS_TIMEOUT_MILLIS":    "60000",
		"DOLT_READ_TIMEOUT_MILLIS":               "28800000",
		"DOLT_WRITE_TIMEOUT_MILLIS":              "28800000",
		"TLS_ENABLED":                            "false",
	}

	tpl, err := template.New("server.yaml.tpl").
		Option("missingkey=error").
		Funcs(template.FuncMap{"default": defaultValue}).
		ParseFiles(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	var out bytes.Buffer
	if err := tpl.ExecuteTemplate(&out, "server.yaml.tpl", data); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Print(out.String())
}
EOF
    go run "${go_file}" "$template_path"
  }

  assert_cmpd_metrics_port_contract() {
    for file in "$standalone_cmpd_path" "$replication_cmpd_path"; do
      grep -Fq "name: metrics" "$file"
      grep -Fq "DOLT_METRICS_HOST" "$file"
      grep -Fq "DOLT_METRICS_PORT" "$file"
      if grep -Fq "exporter:" "$file"; then
        echo "${file} should not declare ComponentDefinition.spec.exporter for the main container metrics endpoint" >&2
        return 1
      fi
    done
  }

  assert_cluster_chart_does_not_render_disable_exporter() {
    if grep -Fq "disableExporter" "$cluster_template_path" "$cluster_values_path"; then
      echo "DoltDB cluster chart should not render or expose disableExporter for curl-only metrics validation" >&2
      return 1
    fi
  }

  It "renders Dolt native Prometheus metrics defaults without optional variables"
    When call render_template_without_metrics_overrides
    The status should be success
    The output should include "metrics:"
    The output should include "  host: 0.0.0.0"
    The output should include "  port: 11228"
    The output should include "  labels:"
  End

  It "declares a main-container metrics port without the KubeBlocks exporter API"
    When call assert_cmpd_metrics_port_contract
    The status should be success
  End

  It "does not expose disableExporter in the cluster chart"
    When call assert_cluster_chart_does_not_render_disable_exporter
    The status should be success
  End

End
