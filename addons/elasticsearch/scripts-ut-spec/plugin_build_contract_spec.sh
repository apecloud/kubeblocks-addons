# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Elasticsearch 9.3.2 plugin image build contract"
  dockerfile="../plugins/Dockerfile"

  inspect_build_order() {
    ruby -e '
      source = File.read(ARGV.fetch(0))
      ik_hash = "804758ddd632fb460ca09bdd04f3c0aa70da878e03cbb53ae122137e4f18b2c5"
      pinyin_hash = "e418aa3a410257520c3480a0a741a7e388e3e69832a8c52cd7c190872c0abe99"
      abort "9.3.2 is missing" unless source.include?("9.3.2")
      abort "focused es9-plugins stage is missing" unless source.match?(/^FROM alpine:3[.]19[.]1 AS es9-plugins$/)
      abort "final image does not inherit the verified stage" unless source.match?(/^FROM es9-plugins$/)
      abort "IK hash is missing" unless source.include?(ik_hash)
      abort "Pinyin hash is missing" unless source.include?(pinyin_hash)
      [
        ["IK", ik_hash, "${ik_zip}"],
        ["Pinyin", pinyin_hash, "${pinyin_zip}"]
      ].each do |name, digest, archive_var|
        digest_position = source.index(digest)
        hash_check = digest_position && source.index("sha256sum -c", digest_position)
        unzip = source.index(%(unzip -q "#{archive_var}"))
        checked_before_unzip = digest_position && hash_check && unzip &&
          digest_position < hash_check && hash_check < unzip
        abort "#{name} ZIP is not hash-checked before unzip" unless checked_before_unzip
      end
      puts "hash-before-unzip=true"
    ' "${dockerfile}"
  }

  It "pins both upstream ZIP hashes and verifies them before extraction"
    When call inspect_build_order
    The output should eq "hash-before-unzip=true"
    The status should be success
  End
End
