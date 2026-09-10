# shellcheck shell=sh

Describe "DoltDB ServiceRef contract"
  cmpd_template="../templates/cmpd.yaml"
  mysql_source_servicedescriptor="../../../examples/doltdb/mysql-source-servicedescriptor.yaml"

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

  extract_mysql_service_version() {
    awk '
      /serviceKind:[[:space:]]*mysql/ { seen = 1; next }
      seen && /serviceVersion:/ {
        line = $0
        sub(/^[[:space:]]*serviceVersion:[[:space:]]*/, "", line)
        gsub(/^"/, "", line)
        gsub(/"$/, "", line)
        print line
        exit
      }
    ' "$1"
  }

  assert_mysql_source_version_regex_matches_example_descriptor() {
    pattern="$(extract_mysql_service_version "$cmpd_template")"
    example_version="$(extract_mysql_service_version "$mysql_source_servicedescriptor")"

    if [ -z "$pattern" ] || [ -z "$example_version" ]; then
      echo "missing mysql serviceVersion contract or example version" >&2
      return 1
    fi

    go_file="${TEST_DIR}/assert_service_version_regex.go"
    cat >"${go_file}" <<'EOF'
package main

import (
	"fmt"
	"os"
	"regexp"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: assert_service_version_regex <pattern> <version>")
		os.Exit(2)
	}

	re, err := regexp.Compile(os.Args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid serviceVersion regexp %q: %v\n", os.Args[1], err)
		os.Exit(1)
	}
	if !re.MatchString(os.Args[2]) {
		fmt.Fprintf(os.Stderr, "serviceVersion regexp %q does not match example version %q\n", os.Args[1], os.Args[2])
		os.Exit(1)
	}
}
EOF

    go run "${go_file}" "$pattern" "$example_version"
  }

  It "declares a valid mysql-source serviceVersion regex matching the external example"
    When call assert_mysql_source_version_regex_matches_example_descriptor
    The status should be success
  End
End
