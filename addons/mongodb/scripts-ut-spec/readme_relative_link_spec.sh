# shellcheck shell=bash

run_mongodb_readme_link_oracle() {
  local mode
  local ruby_bin

  mode=$1
  shift
  ruby_bin=${MONGODB_RUBY_BIN:-ruby}

  "$ruby_bin" -ruri -e '
    def inside_root?(root, path)
      path == root || path.start_with?("#{root}#{File::SEPARATOR}")
    end

    def pointy_destination(line, target_start, segment_end)
      index = target_start + 1
      backslash_run = 0
      malformed = false

      while index < segment_end
        byte = line.getbyte(index)
        if byte == 92
          backslash_run += 1
          index += 1
          next
        end

        escaped = backslash_run.odd?
        if byte == 60 && !escaped
          malformed = true
          break
        end
        if byte == 62 && !escaped
          if line.getbyte(index + 1) == 41
            raw_target = line[target_start..index]
            destination = raw_target.byteslice(
              1,
              raw_target.bytesize - 2
            )
            return [raw_target, destination, index + 2, false]
          end
          malformed = true
          break
        end

        backslash_run = 0
        index += 1
      end

      next_match = /\[[^\]\n]+\]\(/.match(line, target_start + 1)
      link_end = line.rindex(")", segment_end - 1) unless next_match
      raw_end = next_match ? next_match.begin(0) : (link_end || segment_end)
      raw_target = line[target_start...raw_end].sub(/\r?\n\z/, "")
      next_cursor = next_match ? next_match.begin(0) : (link_end ? link_end + 1 : segment_end)
      [raw_target, nil, next_cursor, true]
    end

    def malformed_bare_result(
      raw_target,
      next_cursor,
      reason,
      code = nil,
      offending_offset = nil
    )
      {
        kind: :malformed,
        raw_target: raw_target,
        destination: nil,
        next_cursor: next_cursor,
        reason: reason,
        code: code,
        offending_offset: offending_offset
      }
    end

    def bare_destination(line, target_start, segment_end)
      index = target_start
      depth = 0
      backslash_run = 0

      while index < segment_end
        byte = line.getbyte(index)
        if byte <= 32 || byte == 127
          return malformed_bare_result(
            line.byteslice(target_start, index - target_start + 1),
            index + 1,
            :forbidden_byte,
            byte,
            index - target_start
          )
        end

        if byte == 92
          backslash_run += 1
          index += 1
          next
        end

        escaped = backslash_run.odd?
        if byte == 40 && !escaped
          depth += 1
        elsif byte == 41 && !escaped
          if depth.zero?
            raw_target = line.byteslice(
              target_start,
              index - target_start
            )
            return {
              kind: :valid,
              raw_target: raw_target,
              destination: raw_target,
              next_cursor: index + 1,
              reason: nil,
              code: nil,
              offending_offset: nil
            }
          end
          depth -= 1
        end

        backslash_run = 0
        index += 1
      end

      raw_target = line.byteslice(
        target_start,
        segment_end - target_start
      ).sub(/\r?\n\z/, "")
      malformed_bare_result(
        raw_target,
        segment_end,
        :line_end_before_terminator
      )
    end

    def markdown_link_targets(text)
      targets = []
      opener = /\[[^\]\n]+\]\(/

      text.each_line do |line|
        cursor = 0
        while (match = opener.match(line, cursor))
          target_start = match.end(0)
          if line.getbyte(target_start) == 60
            segment_end = line.length
            raw_target, destination, cursor, malformed =
              pointy_destination(line, target_start, segment_end)
            targets << [raw_target, destination, malformed]
            next
          end

          segment_end = line.length
          result = bare_destination(line, target_start, segment_end)
          next_cursor = result.fetch(:next_cursor)
          unless target_start < next_cursor && next_cursor <= segment_end
            abort(
              "bare_destination cursor invariant failed: " \
              "target_start=#{target_start} " \
              "next_cursor=#{next_cursor} " \
              "segment_end=#{segment_end}"
            )
          end
          targets << [
            result.fetch(:raw_target),
            result.fetch(:destination),
            result.fetch(:kind) == :malformed
          ]
          cursor = next_cursor
        end
      end

      targets
    end

    def normalize_markdown_destination(destination)
      destination.gsub(/\\([\x21-\x2f\x3a-\x40\x5b-\x60\x7b-\x7e])/) do
        Regexp.last_match(1)
      end
    end

    mode = ARGV.shift
    if mode != "validate"
      code = Integer(ARGV.shift, 10) unless mode == "inspect-line-end"
      case mode
      when "inspect-code"
        line = "ab".b + [code].pack("C") + "cd)"
        result = bare_destination(line, 0, line.bytesize)
        puts "#{result.fetch(:reason)}:#{result.fetch(:code)}"
      when "inspect-escaped-code"
        line = "ab\\".b + [code].pack("C") + "cd)"
        result = bare_destination(line, 0, line.bytesize)
        puts "#{result.fetch(:reason)}:#{result.fetch(:code)}"
      when "inspect-result"
        line = "zzab".b + [code].pack("C") + "cd)"
        result = bare_destination(line, 2, 8)
        puts [
          "kind=#{result.fetch(:kind)}",
          "reason=#{result.fetch(:reason)}",
          "code=#{result.fetch(:code)}",
          "raw_hex=#{result.fetch(:raw_target).unpack1("H*")}",
          "offending_offset=#{result.fetch(:offending_offset)}",
          "next_cursor=#{result.fetch(:next_cursor)}"
        ].join(";")
      when "inspect-line-end"
        line = "unterminated".b
        result = bare_destination(line, 0, line.bytesize)
        puts result.fetch(:reason)
      else
        abort "unknown mode: #{mode.inspect}"
      end
      exit
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
  ' "$mode" "$@"
}

validate_mongodb_readme_links() {
  local repo_root

  repo_root=${MONGODB_REPO_ROOT:-$(git rev-parse --show-toplevel)} || return 2
  run_mongodb_readme_link_oracle validate "$repo_root"
}

inspect_mongodb_bare_destination_code() {
  run_mongodb_readme_link_oracle inspect-code "$1"
}

inspect_mongodb_bare_destination_escaped_code() {
  run_mongodb_readme_link_oracle inspect-escaped-code "$1"
}

inspect_mongodb_bare_destination_result() {
  run_mongodb_readme_link_oracle inspect-result "$1"
}

inspect_mongodb_bare_destination_line_end() {
  run_mongodb_readme_link_oracle inspect-line-end
}

Describe "MongoDB README relative-link closure"

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

  It "recovers at the next opener after a pointy segment without a closing parenthesis"
    prepare_link_fixture
    printf '%s\n' \
      '[MalformedSegment](<before[Later](missing-later.md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'link="<before" malformed_markdown_destination'
    The stderr should include 'link="missing-later.md" missing=addons/mongodb/missing-later.md'
  End

  It "keeps opener-shaped bytes inside a complete pointy destination"
    prepare_link_fixture
    printf '%s\n' \
      '[MalformedSegment](<before[Later](missing-later>)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include \
      'link="<before[Later](missing-later>" missing=addons/mongodb/before[Later](missing-later'
    The stderr should not include 'malformed_markdown_destination'
    The stderr should not include 'link="missing-later>"'
  End

  It "accepts opener-shaped bytes as pointy destination data"
    prepare_link_fixture
    printf '# opener-shaped data\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/before[Later](target.md"
    printf '%s\n' \
      '[OpenerData](<before[Later](target.md>)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "rejects an interior pointy opener without an early closer"
    prepare_link_fixture
    printf '# nested decoy\n' > "$MONGODB_REPO_ROOT/addons/mongodb/nested<inside"
    printf '%s\n' '[NestedOnly](<nested<inside>)' >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
  End

  It "accepts balanced nested parentheses in a bare destination"
    prepare_link_fixture
    printf '# balanced bare destination\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/balanced(and(more(nested))).md"
    printf '%s\n' \
      '[BareBalanced](balanced(and(more(nested))).md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "keeps an escaped closing parenthesis as bare destination data"
    prepare_link_fixture
    printf '# escaped bare parenthesis\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/escaped)name.md"
    printf '%s\n' \
      '[BareEscaped](escaped\)name.md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "keeps an escaped opening parenthesis as bare destination data"
    prepare_link_fixture
    printf '# escaped bare opening parenthesis\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/escaped(name.md"
    printf '%s\n' \
      '[BareEscapedOpen](escaped\(name.md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "uses odd backslash parity beyond run three in a bare destination"
    prepare_link_fixture
    printf '# bare five parity\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/"'escaped\\)name.md'
    printf '%s\n' \
      '[BareFiveParity](escaped\\\\\)name.md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "uses even backslash parity to terminate a bare destination"
    prepare_link_fixture
    printf '# bare even parity\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/"'even\'
    printf '%s\n' \
      '[BareEvenParity](even\\)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "keeps opener-shaped bytes inside a complete bare destination"
    prepare_link_fixture
    printf '# bare opener-shaped destination\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/"'before[Later](target).md'
    printf '%s\n' \
      '[BareOpenerData](before[Later](target).md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should be success
    The output should include "MongoDB README relative-link closure passed"
  End

  It "rejects an unescaped space inside a bare destination"
    prepare_link_fixture
    printf '# bare destination space decoy\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/space name.md"
    printf '%s\n' \
      '[BareSpace](space name.md)' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
  End

  It "rejects an unescaped tab inside a bare destination"
    prepare_link_fixture
    tab_name=$(printf 'tab\tname.md')
    printf '# bare destination tab decoy\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/$tab_name"
    printf '[BareTab](tab\tname.md)\n' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
  End

  It "rejects an unescaped DEL byte inside a bare destination"
    prepare_link_fixture
    del_name=$(printf 'del\177name.md')
    printf '# bare destination DEL decoy\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/$del_name"
    printf '[BareDel](del\177name.md)\n' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
  End

  It "continues at a later opener after a forbidden bare byte"
    prepare_link_fixture
    tab_name=$(printf 'bad\tname.md')
    printf '# forbidden-byte candidate decoy\n' \
      > "$MONGODB_REPO_ROOT/addons/mongodb/$tab_name"
    printf '[BadCursor](bad\tname.md)[LaterCursor](missing-after.md)\n' \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
    The stderr should include \
      'link="missing-after.md" missing=addons/mongodb/missing-after.md'
  End

  Parameters
    "0"
    "1"
    "2"
    "3"
    "4"
    "5"
    "6"
    "7"
    "8"
    "10"
    "11"
    "12"
    "13"
    "14"
    "15"
    "16"
    "17"
    "18"
    "19"
    "20"
    "21"
    "22"
    "23"
    "24"
    "25"
    "26"
    "27"
    "28"
    "29"
    "30"
    "31"
  End

  It "rejects unescaped ASCII control byte $1 inside a bare destination"
    prepare_link_fixture
    control_code="$1"
    control_octal=$(printf '%03o' "$control_code")
    if [ "$control_code" -ne 0 ]; then
      control_name=$(
        printf 'control-%03d%b-name.md' \
          "$control_code" "\\$control_octal"
      )
      printf '# bare destination control decoy\n' \
        > "$MONGODB_REPO_ROOT/addons/mongodb/$control_name"
    fi
    printf '[BareControl%03d](control-%03d%b-name.md)\n' \
      "$control_code" "$control_code" "\\$control_octal" \
      >> "$MONGODB_REPO_ROOT/addons/mongodb/README.md"

    When call validate_mongodb_readme_links
    The status should eq 1
    The stderr should include 'malformed_markdown_destination'
  End
End

Describe "MongoDB README bare parser reasons"
  It "distinguishes line end before a bare terminator"
    When call inspect_mongodb_bare_destination_line_end
    The status should be success
    The output should eq "line_end_before_terminator"
  End

  Parameters
    "0"
    "1"
    "2"
    "3"
    "4"
    "5"
    "6"
    "7"
    "8"
    "9"
    "10"
    "11"
    "12"
    "13"
    "14"
    "15"
    "16"
    "17"
    "18"
    "19"
    "20"
    "21"
    "22"
    "23"
    "24"
    "25"
    "26"
    "27"
    "28"
    "29"
    "30"
    "31"
    "32"
    "127"
  End

  It "reports exact forbidden bare byte $1 before line transport"
    When call inspect_mongodb_bare_destination_code "$1"
    The status should be success
    The output should eq "forbidden_byte:$1"
  End

  It "reports exact forbidden bare byte $1 after a backslash"
    When call inspect_mongodb_bare_destination_escaped_code "$1"
    The status should be success
    The output should eq "forbidden_byte:$1"
  End

  It "binds forbidden bare byte $1 result ownership and recovery cursor"
    result_hex=$(printf '%02x' "$1")

    When call inspect_mongodb_bare_destination_result "$1"
    The status should be success
    The output should eq \
      "kind=malformed;reason=forbidden_byte;code=$1;raw_hex=6162$result_hex;offending_offset=2;next_cursor=5"
  End
End
