# shellcheck shell=bash

Describe "MongoDB static example serviceVersion reference closure"

  validate_example_service_versions() {
    local chart_dir
    local helm_bin
    local render_file
    local repo_root
    local ruby_bin
    local status

    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    helm_bin=${MONGODB_HELM_BIN:-helm}
    ruby_bin=${MONGODB_RUBY_BIN:-ruby}
    repo_root=${MONGODB_REPO_ROOT:-$(git -C "$chart_dir" rev-parse --show-toplevel)} || return 2

    "$helm_bin" dependency build "$chart_dir" >/dev/null || return 2
    render_file=$(mktemp "${TMPDIR:-/tmp}/mongodb-service-version-render.XXXXXX") || return 2
    "$helm_bin" template kb-addon-mongodb "$chart_dir" > "$render_file"
    status=$?
    if [ "$status" -ne 0 ]; then
      rm "$render_file"
      return 2
    fi

    "$ruby_bin" -ryaml -e '
      def selector_matches?(selector, value)
        value == selector || value.start_with?(selector) || Regexp.new(selector).match?(value)
      rescue RegexpError
        false
      end

      def versions_in(text)
        text.scan(/\b\d+\.\d+\.\d+\b/).uniq.sort
      end

      repo_root = ARGV.fetch(0)
      documents = YAML.load_stream(File.read(ARGV.fetch(1))).compact
      component_definitions = documents.select { |document| document["kind"] == "ComponentDefinition" }
      component_versions = documents.select { |document| document["kind"] == "ComponentVersion" }
      replica_definitions = component_definitions.select do |definition|
        definition.dig("metadata", "name")&.match?(/^mongodb-/)
      end
      abort "expected one replica ComponentDefinition, got #{replica_definitions.length}" unless replica_definitions.length == 1

      replica_name = replica_definitions.first.dig("metadata", "name")
      supported_versions = component_versions.flat_map do |version|
        release_names = Array(version.dig("spec", "compatibilityRules")).flat_map do |rule|
          next [] unless Array(rule["compDefs"]).any? { |selector| selector_matches?(selector, replica_name) }

          Array(rule["releases"])
        end
        Array(version.dig("spec", "releases")).map do |release|
          release["serviceVersion"] if release_names.include?(release["name"])
        end.compact
      end.uniq.sort
      abort "replica ComponentVersion has no supported serviceVersions" if supported_versions.empty?

      failures = []
      restore_path = File.join(repo_root, "examples", "mongodb", "restore.yaml")
      restore = YAML.load_file(restore_path)
      restore_version = restore.dig("spec", "componentSpecs", 0, "serviceVersion")
      unless supported_versions.include?(restore_version)
        failures << "examples/mongodb/restore.yaml serviceVersion=#{restore_version.inspect} supported=#{supported_versions.join(",")}"
      end

      readmes = {
        "examples/mongodb/README.md" => File.read(File.join(repo_root, "examples", "mongodb", "README.md")),
        "addons/mongodb/README.md" => File.read(File.join(repo_root, "addons", "mongodb", "README.md"))
      }
      readmes.each do |file, readme|
        versions_section = readme[/### Versions\n(.*?)\n## Prerequisites/m, 1].to_s
        actual_versions = versions_in(versions_section)
        unless actual_versions == supported_versions
          failures << "#{file} versions=#{actual_versions.join(",")} supported=#{supported_versions.join(",")}"
        end

        snippet = readme[
          /If you want to create a cluster of specified version.*?The list of supported versions/m,
          0
        ].to_s
        snippet_options = versions_in(snippet[/# Valid options are: \[([^\]]+)\]/, 1].to_s)
        unless snippet_options == supported_versions
          failures << "#{file} snippet_options=#{snippet_options.join(",")} supported=#{supported_versions.join(",")}"
        end

        snippet_selected = snippet[/serviceVersion:\s*"([^"]+)"/, 1]
        unless supported_versions.include?(snippet_selected)
          failures << "#{file} snippet_selected=#{snippet_selected.inspect} unsupported"
        end
      end

      addon_cluster = readmes.fetch("addons/mongodb/README.md")[
        /# cat examples\/mongodb\/cluster\.yaml.*?\n```/m,
        0
      ].to_s
      addon_cluster_options = versions_in(
        addon_cluster[/# Valid options are:?\s*\[([^\]]+)\](?=\n\s+serviceVersion:)/, 1].to_s
      )
      unless addon_cluster_options == supported_versions
        failures << "addons/mongodb/README.md embedded_cluster_options=#{addon_cluster_options.join(",")} supported=#{supported_versions.join(",")}"
      end

      addon_restore = readmes.fetch("addons/mongodb/README.md")[
        /# cat examples\/mongodb\/restore\.yaml.*?\n```/m,
        0
      ].to_s
      addon_restore_version = addon_restore[/serviceVersion:\s*"([^"]+)"/, 1]
      unless supported_versions.include?(addon_restore_version)
        failures << "addons/mongodb/README.md embedded_restore_version=#{addon_restore_version.inspect} unsupported"
      end
      unless addon_restore_version == restore_version
        failures << "addons/mongodb/README.md embedded_restore_version=#{addon_restore_version.inspect} canonical_restore_version=#{restore_version.inspect} mismatch"
      end

      cluster_source = File.read(File.join(repo_root, "examples", "mongodb", "cluster.yaml"))
      cluster_options = versions_in(
        cluster_source[/# Valid options are:?\s*\[([^\]]+)\](?=\n\s+serviceVersion:)/, 1].to_s
      )
      unless cluster_options == supported_versions
        failures << "examples/mongodb/cluster.yaml comment_options=#{cluster_options.join(",")} supported=#{supported_versions.join(",")}"
      end

      unless failures.empty?
        failures.each { |failure| warn failure }
        abort "static example serviceVersion reference closure failed: #{failures.length} drift(s)"
      end

      puts "static example serviceVersion reference closure passed for #{supported_versions.length} releases"
    ' "$repo_root" "$render_file"
    status=$?
    rm "$render_file"

    if [ "$status" -eq 0 ]; then
      return 0
    fi
    return 1
  }

  setup_example_service_version_test() {
    local chart_dir

    chart_dir=${MONGODB_CHART_DIR:-$(cd .. && pwd)}
    test_root=$(mktemp -d "${TMPDIR:-/tmp}/mongodb-service-version-spec.XXXXXX")
    fake_bin="$test_root/bin"
    call_log="$test_root/calls.log"
    real_helm_bin=$(command -v helm)
    real_ruby_bin=$(command -v ruby)
    source_repo_root=$(git -C "$chart_dir" rev-parse --show-toplevel)
    mkdir -p "$fake_bin"
    : > "$call_log"

    cat > "$fake_bin/helm" <<'SH'
#!/bin/sh
printf 'helm %s\n' "$*" >> "$MONGODB_FAKE_CALL_LOG"

case "${MONGODB_FAKE_HELM_MODE:-delegate}" in
  dependency-failure)
    if [ "$1" = "dependency" ] && [ "$2" = "build" ]; then
      exit 37
    fi
    exit 91
    ;;
  render-failure)
    if [ "$1" = "dependency" ] && [ "$2" = "build" ]; then
      exec "$MONGODB_REAL_HELM_BIN" "$@"
    fi
    "$MONGODB_REAL_HELM_BIN" "$@" || exit $?
    exit 42
    ;;
  delegate)
    exec "$MONGODB_REAL_HELM_BIN" "$@"
    ;;
  *)
    exit 92
    ;;
esac
SH

    cat > "$fake_bin/ruby" <<'SH'
#!/bin/sh
printf '%s\n' "ruby" >> "$MONGODB_FAKE_CALL_LOG"
exec "$MONGODB_REAL_RUBY_BIN" "$@"
SH
    chmod +x "$fake_bin/helm" "$fake_bin/ruby"

    export MONGODB_FAKE_CALL_LOG="$call_log"
    export MONGODB_HELM_BIN="$fake_bin/helm"
    export MONGODB_REAL_HELM_BIN="$real_helm_bin"
    export MONGODB_REAL_RUBY_BIN="$real_ruby_bin"
    export MONGODB_REPO_ROOT="$source_repo_root"
    export MONGODB_RUBY_BIN="$fake_bin/ruby"
  }
  Before "setup_example_service_version_test"

  cleanup_example_service_version_test() {
    rm -rf "${test_root:?}"
    unset MONGODB_FAKE_CALL_LOG
    unset MONGODB_FAKE_HELM_MODE
    unset MONGODB_HELM_BIN
    unset MONGODB_REAL_HELM_BIN
    unset MONGODB_REAL_RUBY_BIN
    unset MONGODB_REPO_ROOT
    unset MONGODB_RUBY_BIN
  }
  After "cleanup_example_service_version_test"

  prepare_supported_restore_drift() {
    local repo_copy

    repo_copy="$test_root/repo"
    mkdir -p "$repo_copy/addons/mongodb" "$repo_copy/examples/mongodb"
    cp "$source_repo_root/addons/mongodb/README.md" "$repo_copy/addons/mongodb/README.md"
    cp "$source_repo_root/examples/mongodb/README.md" "$repo_copy/examples/mongodb/README.md"
    cp "$source_repo_root/examples/mongodb/cluster.yaml" "$repo_copy/examples/mongodb/cluster.yaml"
    cp "$source_repo_root/examples/mongodb/restore.yaml" "$repo_copy/examples/mongodb/restore.yaml"
    "$real_ruby_bin" -e '
      path = ARGV.fetch(0)
      text = File.read(path)
      changed = text.sub(
        /(# cat examples\/mongodb\/restore\.yaml.*?serviceVersion: ")[^"]+(")/m
      ) { "#{Regexp.last_match(1)}7.0.28#{Regexp.last_match(2)}" }
      abort "embedded restore fixture was not changed" if changed == text
      File.write(path, changed)
    ' "$repo_copy/addons/mongodb/README.md"
    export MONGODB_REPO_ROOT="$repo_copy"
  }

  It "returns infrastructure status 2 and stops before render or assertions when dependency build fails"
    export MONGODB_FAKE_HELM_MODE=dependency-failure

    When call validate_example_service_versions
    The status should eq 2
    The contents of file "$call_log" should include "helm dependency build"
    The contents of file "$call_log" should not include "helm template"
    The contents of file "$call_log" should not include "ruby"
  End

  It "returns infrastructure status 2 and stops before assertions when template exits nonzero after valid output"
    export MONGODB_FAKE_HELM_MODE=render-failure

    When call validate_example_service_versions
    The status should eq 2
    The contents of file "$call_log" should include "helm dependency build"
    The contents of file "$call_log" should include "helm template"
    The contents of file "$call_log" should not include "ruby"
  End

  It "returns assertion status 1 for supported but mismatched embedded restore source"
    export MONGODB_FAKE_HELM_MODE=delegate
    prepare_supported_restore_drift

    When call validate_example_service_versions
    The status should eq 1
    The stderr should include 'embedded_restore_version="7.0.28" canonical_restore_version="6.0.27" mismatch'
    The contents of file "$call_log" should include "ruby"
  End

  It "returns success status 0 for aligned YAML examples and README surfaces"
    export MONGODB_FAKE_HELM_MODE=delegate

    When call validate_example_service_versions
    The status should be success
    The output should include "static example serviceVersion reference closure passed for 6 releases"
    The contents of file "$call_log" should include "ruby"
  End
End
