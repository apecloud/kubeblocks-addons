# shellcheck shell=bash

Describe "MongoDB README relative-link closure"

  validate_mongodb_readme_links() {
    local repo_root
    local ruby_bin

    repo_root=${MONGODB_REPO_ROOT:-$(git rev-parse --show-toplevel)} || return 2
    ruby_bin=${MONGODB_RUBY_BIN:-ruby}

    "$ruby_bin" -ruri -e '
      def inside_root?(root, path)
        path == root || path.start_with?("#{root}#{File::SEPARATOR}")
      end

      root = File.realpath(ARGV.fetch(0))
      readmes = %w[
        addons/mongodb/README.md
        examples/mongodb/README.md
      ]
      shared_docs = %w[
        prerequisites.md
        install-addon.md
        create-backuprepo.md
      ]
      failures = []
      seen = Hash.new { |hash, key| hash[key] = [] }

      readmes.each do |relative_readme|
        readme = File.join(root, relative_readme)
        File.read(readme).scan(/\[([^\]]+)\]\(([^)]+)\)/).each do |_label, raw_target|
          raw_path = raw_target.split(/[?#]/, 2).first
          next if raw_path.empty?

          if raw_path.match?(/%(?![0-9a-f]{2})/i)
            failures << "#{relative_readme} link=#{raw_target.inspect} malformed_percent_encoding"
            next
          end
          target = URI::DEFAULT_PARSER.unescape(raw_path)
          unless target.valid_encoding? && !target.include?("\0")
            failures << "#{relative_readme} link=#{raw_target.inspect} malformed_percent_encoding"
            next
          end
          if target.match?(/%[0-9a-f]{2}/i)
            failures << "#{relative_readme} link=#{raw_target.inspect} ambiguous_percent_encoding"
            next
          end

          next if target.match?(/\A[a-z][a-z0-9+.-]*:/i)

          basename = File.basename(target)
          seen[[relative_readme, basename]] << target if shared_docs.include?(basename)
          expanded = File.expand_path(target, File.dirname(readme))
          unless inside_root?(root, expanded)
            failures << "#{relative_readme} link=#{raw_target.inspect} escapes_repository"
            next
          end
          unless File.file?(expanded)
            failures << "#{relative_readme} link=#{raw_target.inspect} missing=#{expanded.delete_prefix("#{root}/")}"
            next
          end

          begin
            actual = File.realpath(expanded)
          rescue SystemCallError => error
            failures << "#{relative_readme} link=#{raw_target.inspect} realpath_error=#{error.class}"
            next
          end
          unless inside_root?(root, actual)
            failures << "#{relative_readme} link=#{raw_target.inspect} real_target_escapes_repository"
            next
          end

          next unless shared_docs.include?(basename)

          expected = File.realpath(File.join(root, "examples", "docs", basename))
          unless actual == expected
            failures << "#{relative_readme} link=#{raw_target.inspect} actual=#{actual.delete_prefix("#{root}/")} expected=#{expected.delete_prefix("#{root}/")}"
          end
        end
      end

      readmes.product(shared_docs).each do |relative_readme, basename|
        count = seen.fetch([relative_readme, basename], []).length
        failures << "#{relative_readme} shared_doc=#{basename} count=#{count} expected=1" unless count == 1
      end

      unless failures.empty?
        failures.each { |failure| warn failure }
        abort "MongoDB README relative-link closure failed: #{failures.length} drift(s)"
      end

      puts "MongoDB README relative-link closure passed"
    ' "$repo_root"
  }

  setup_readme_relative_link_test() {
    source_repo_root=$(git rev-parse --show-toplevel)
    test_root=$(mktemp -d "${TMPDIR:-/tmp}/mongodb-readme-link-spec.XXXXXX")
    export MONGODB_REPO_ROOT="$source_repo_root"
  }
  Before "setup_readme_relative_link_test"

  cleanup_readme_relative_link_test() {
    rm -rf "${test_root:?}"
    unset MONGODB_REPO_ROOT
  }
  After "cleanup_readme_relative_link_test"

  prepare_link_fixture() {
    local basename
    local repo_copy

    repo_copy="$test_root/repo"
    mkdir -p \
      "$repo_copy/addons/mongodb" \
      "$repo_copy/examples/docs" \
      "$repo_copy/examples/mongodb"

    for basename in prerequisites.md install-addon.md create-backuprepo.md; do
      printf '# %s\n' "$basename" > "$repo_copy/examples/docs/$basename"
    done
    printf '# outside\n' > "$test_root/outside.md"

    printf '%s\n' \
      '[Prerequisites](../../examples/docs/prerequisites.md?source=fixture#install)' \
      '[Install](../../examples/docs/install-addon.md)' \
      '[BackupRepo](../../examples/docs/create-backuprepo.md)' \
      > "$repo_copy/addons/mongodb/README.md"
    printf '%s\n' \
      '[Prerequisites](../docs/prerequisites.md)' \
      '[Install](../docs/install-addon.md)' \
      '[BackupRepo](../docs/create-backuprepo.md)' \
      > "$repo_copy/examples/mongodb/README.md"

    export MONGODB_REPO_ROOT="$repo_copy"
  }

  It "keeps every local link inside the repository and both READMEs on the canonical shared docs"
    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "keeps query and fragment suffixes on an in-repository local link"
    prepare_link_fixture

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "rejects a lexical local-link escape"
    prepare_link_fixture
    printf '%s\n' '[Escape](../../../outside.md)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="../../../outside.md" escapes_repository'
  End

  It "rejects an in-repository symlink whose real target escapes the repository"
    prepare_link_fixture
    ln -s ../../../outside.md "$MONGODB_REPO_ROOT/addons/mongodb/outside.md"
    printf '%s\n' '[Escape](outside.md)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="outside.md" real_target_escapes_repository'
  End

  It "rejects percent-encoded dot segments that escape after URL path decoding"
    prepare_link_fixture
    mkdir -p "$MONGODB_REPO_ROOT/addons/mongodb/%2e%2e/%2e%2e/%2e%2e"
    printf '# decoy\n' > "$MONGODB_REPO_ROOT/addons/mongodb/%2e%2e/%2e%2e/%2e%2e/outside.md"
    printf '%s\n' \
      '[Escape](%2e%2e/%2e%2e/%2e%2e/outside.md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="%2e%2e/%2e%2e/%2e%2e/outside.md" escapes_repository'
  End

  It "accepts a valid percent-encoded in-repository filename"
    prepare_link_fixture
    printf '# encoded filename\n' > "$MONGODB_REPO_ROOT/addons/mongodb/space name.md"
    printf '%s\n' '[Space](space%20name.md)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "rejects malformed percent encoding before filesystem resolution"
    prepare_link_fixture
    printf '%s\n' '[Malformed](bad%2G.md)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="bad%2G.md" malformed_percent_encoding'
  End

  It "keeps percent-encoded scheme text in the local-link contract"
    prepare_link_fixture
    printf '%s\n' \
      '[EncodedScheme](%68ttps://example.invalid/resource.md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="%68ttps://example.invalid/resource.md" missing=addons/mongodb/https:/example.invalid/resource.md'
  End

  It "skips a literal external scheme before local percent validation"
    prepare_link_fixture
    printf '%s\n' \
      '[External](https://example.invalid/bad%2G.md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "rejects an ambiguous target that remains percent-encoded after one decode"
    prepare_link_fixture
    printf '# ambiguous decoy\n' > "$MONGODB_REPO_ROOT/addons/mongodb/literal%2520name.md"
    printf '%s\n' \
      '[Ambiguous](literal%2520name.md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="literal%2520name.md" ambiguous_percent_encoding'
  End
End
