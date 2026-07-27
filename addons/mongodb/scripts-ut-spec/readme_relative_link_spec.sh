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

      def pointy_destination(line, target_start)
        index = target_start + 1
        backslash_run = 0
        closer = nil
        nested = false

        while index < line.length
          byte = line.getbyte(index)
          if byte == 92
            backslash_run += 1
            index += 1
            next
          end

          escaped = backslash_run.odd?
          nested = true if byte == 60 && !escaped
          if byte == 62 && !escaped
            closer = index
            break
          end

          backslash_run = 0
          index += 1
        end

        link_end = line.index(")", target_start)
        if closer && line.getbyte(closer + 1) == 41 && !nested
          raw_target = line[target_start..closer]
          destination = raw_target.byteslice(1, raw_target.bytesize - 2)
          return [raw_target, destination, closer + 2, false]
        end

        raw_end = link_end || line.length
        raw_target = line[target_start...raw_end].sub(/\r?\n\z/, "")
        next_cursor = link_end ? link_end + 1 : line.length
        [raw_target, nil, next_cursor, true]
      end

      def markdown_link_targets(text)
        targets = []
        opener = /\[[^\]\n]+\]\(/

        text.each_line do |line|
          cursor = 0
          while (match = opener.match(line, cursor))
            target_start = match.end(0)
            if line.getbyte(target_start) == 60
              raw_target, destination, cursor, malformed =
                pointy_destination(line, target_start)
              targets << [raw_target, destination, malformed]
              next
            end

            link_end = line.index(")", target_start)
            break unless link_end

            raw_target = line[target_start...link_end]
            targets << [raw_target, raw_target, false]
            cursor = link_end + 1
          end
        end

        targets
      end

      def normalize_markdown_destination(destination)
        destination.gsub(/\\([\x21-\x2f\x3a-\x40\x5b-\x60\x7b-\x7e])/) do
          Regexp.last_match(1)
        end
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
        markdown_link_targets(File.read(readme)).each do |raw_target, destination, malformed|
          if malformed
            failures << "#{relative_readme} link=#{raw_target.inspect} malformed_markdown_destination"
            next
          end

          raw_path = normalize_markdown_destination(destination).split(/[?#]/, 2).first.to_s
          next if raw_path.empty?
          next if raw_path.match?(/\A[a-z][a-z0-9+.-]*:/i)

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

  It "skips a pointy external scheme before local percent validation"
    prepare_link_fixture
    printf '%s\n' \
      '[ExternalPointy](<https://example.invalid/bad%2G.md>)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "keeps query and fragment suffixes on a pointy canonical shared-doc link"
    prepare_link_fixture
    printf '%s\n' \
      '[PointyShared](<../../examples/docs/prerequisites.md?source=fixture#install>)' \
      '[Install](../../examples/docs/install-addon.md)' \
      '[BackupRepo](../../examples/docs/create-backuprepo.md)' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "accepts a pointy percent-encoded in-repository filename"
    prepare_link_fixture
    printf '# encoded filename\n' > "$MONGODB_REPO_ROOT/addons/mongodb/space name.md"
    printf '%s\n' '[PointySpace](<space%20name.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "rejects a pointy percent-encoded dot-segment escape"
    prepare_link_fixture
    mkdir -p "$MONGODB_REPO_ROOT/addons/mongodb/%2e%2e/%2e%2e/%2e%2e"
    printf '# decoy\n' > "$MONGODB_REPO_ROOT/addons/mongodb/%2e%2e/%2e%2e/%2e%2e/outside.md"
    printf '%s\n' \
      '[PointyEscape](<%2e%2e/%2e%2e/%2e%2e/outside.md>)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="<%2e%2e/%2e%2e/%2e%2e/outside.md>" escapes_repository'
  End

  It "reports an unwrapped missing path for a pointy local link"
    prepare_link_fixture
    printf '%s\n' '[PointyMissing](<missing-pointy.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="<missing-pointy.md>" missing=addons/mongodb/missing-pointy.md'
  End

  It "rejects a pointy symlink whose real target escapes the repository"
    prepare_link_fixture
    ln -s ../../../outside.md "$MONGODB_REPO_ROOT/addons/mongodb/pointy-outside.md"
    printf '%s\n' '[PointySymlink](<pointy-outside.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="<pointy-outside.md>" real_target_escapes_repository'
  End

  It "rejects a pointy shared-doc basename that resolves to the wrong real file"
    prepare_link_fixture
    printf '# wrong shared doc\n' > "$MONGODB_REPO_ROOT/addons/mongodb/install-addon.md"
    printf '%s\n' \
      '[Prerequisites](../../examples/docs/prerequisites.md)' \
      '[WrongShared](<install-addon.md>)' \
      '[BackupRepo](../../examples/docs/create-backuprepo.md)' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'actual=addons/mongodb/install-addon.md expected=examples/docs/install-addon.md'
  End

  It "rejects malformed percent encoding inside a pointy destination"
    prepare_link_fixture
    printf '%s\n' '[PointyMalformed](<bad%2G.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="<bad%2G.md>" malformed_percent_encoding'
  End

  It "rejects a leading pointy delimiter without a matching closer"
    prepare_link_fixture
    printf '%s\n' '[NoCloser](<missing.md)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
  End

  It "accepts a bare destination ending in a pointy delimiter"
    prepare_link_fixture
    printf '# bare closing pointy\n' > "$MONGODB_REPO_ROOT/addons/mongodb/closing>"
    printf '%s\n' '[BareClosing](closing>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "accepts a bare destination containing an interior pointy delimiter"
    prepare_link_fixture
    printf '# bare interior pointy\n' > "$MONGODB_REPO_ROOT/addons/mongodb/middle>name.md"
    printf '%s\n' '[BareInterior](middle>name.md)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "rejects nested unescaped pointy delimiters"
    prepare_link_fixture
    printf '%s\n' '[Nested](<<nested>.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
  End

  It "keeps an empty pointy destination as the empty destination"
    prepare_link_fixture
    printf '%s\n' '[Empty](<>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "accepts an escaped pointy delimiter as destination data"
    prepare_link_fixture
    printf '# escaped pointy\n' > "$MONGODB_REPO_ROOT/addons/mongodb/escaped>name.md"
    printf '%s\n' '[EscapedPointy](<escaped\>name.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "captures an escaped closing parenthesis inside a pointy destination"
    prepare_link_fixture
    printf '# escaped parenthesis\n' > "$MONGODB_REPO_ROOT/addons/mongodb/escaped)name.md"
    printf '%s\n' '[EscapedParen](<escaped\)name.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "normalizes an escaped scheme colon before external ownership"
    prepare_link_fixture
    printf '%s\n' \
      '[EscapedScheme](<https\://example.invalid/bad%2G.md>)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "keeps an escaped percent encoded scheme locally owned"
    prepare_link_fixture
    printf '%s\n' \
      '[EscapedPercent](<\%68ttps://example.invalid/resource.md>)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'missing=addons/mongodb/https:/example.invalid/resource.md'
  End

  It "rejects a pointy candidate whose only apparent closer is escaped"
    prepare_link_fixture
    printf '%s\n' '[OnlyEscaped](<escaped\>name.md)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
  End

  It "rejects a pointy candidate ending in a lone backslash"
    prepare_link_fixture
    printf '%s\n' '[LoneBackslash](<lone\)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
  End

  It "applies Markdown backslash normalization exactly once"
    prepare_link_fixture
    printf '# one-pass parenthesis\n' > "$MONGODB_REPO_ROOT/addons/mongodb/"'escaped\)name.md'
    printf '%s\n' '[OnePass](<escaped\\)name.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "uses even backslash parity to select the first unescaped pointy closer"
    prepare_link_fixture
    printf '# previous-byte decoy\n' > "$MONGODB_REPO_ROOT/addons/mongodb/"'escaped\>name.md'
    printf '%s\n' '[EvenParity](<escaped\\>name.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
  End

  It "uses odd backslash parity beyond run one"
    prepare_link_fixture
    printf '# triple parity\n' > "$MONGODB_REPO_ROOT/addons/mongodb/"'escaped\>name.md'
    printf '%s\n' '[TripleParity](<escaped\\\>name.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "uses odd backslash parity beyond run three"
    prepare_link_fixture
    printf '# five parity\n' > "$MONGODB_REPO_ROOT/addons/mongodb/"'escaped\\>name.md'
    printf '%s\n' '[FiveParity](<escaped\\\\\>name.md>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "preserves closing-parenthesis data in a malformed pointy diagnostic"
    prepare_link_fixture
    printf '%s\n' '[MalformedRaw](<before)after)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="<before)after" malformed_markdown_destination'
  End
End
