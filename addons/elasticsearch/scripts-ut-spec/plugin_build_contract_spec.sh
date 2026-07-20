# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Elasticsearch 9.3.2 plugin image build contract"
  dockerfile="../plugins/Dockerfile"
  verifier="${PLUGIN_VERIFY_SCRIPT:-../plugins/verify-and-unpack.sh}"

  setup() {
    fixture=$(mktemp -d)
    mkdir -p "${fixture}/bin"
    printf 'known IK bytes\n' >"${fixture}/ik.zip"
    printf 'known Pinyin bytes\n' >"${fixture}/pinyin.zip"
    ik_hash=$(sha256sum "${fixture}/ik.zip" | awk '{print $1}')
    pinyin_hash=$(sha256sum "${fixture}/pinyin.zip" | awk '{print $1}')
    cat >"${fixture}/bin/unzip" <<'SCRIPT'
#!/usr/bin/env sh
printf '%s\n' "$(basename "$2")" >>"${UNZIP_LOG}"
SCRIPT
    chmod +x "${fixture}/bin/unzip"
  }

  cleanup() {
    rm -rf "${fixture}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  inspect_production_path() {
    ruby -e '
      source = File.read(ARGV.fetch(0))
      ik_hash = "804758ddd632fb460ca09bdd04f3c0aa70da878e03cbb53ae122137e4f18b2c5"
      pinyin_hash = "e418aa3a410257520c3480a0a741a7e388e3e69832a8c52cd7c190872c0abe99"
      abort "9.3.2 is missing" unless source.include?("9.3.2")
      abort "focused es9-plugins stage is missing" unless source.match?(/^FROM alpine:3[.]19[.]1 AS es9-plugins$/)
      abort "final image does not inherit the verified stage" unless source.match?(/^FROM es9-plugins$/)
      abort "IK hash is not pinned" unless source.include?(ik_hash)
      abort "Pinyin hash is not pinned" unless source.include?(pinyin_hash)
      copy = "COPY verify-and-unpack.sh /usr/local/bin/verify-and-unpack-plugin"
      abort "production verifier is not copied into the build" unless source.include?(copy)
      verifier_calls = source.scan(%r{^\s*/usr/local/bin/verify-and-unpack-plugin \\$}).length
      abort "production verifier must be used for IK and Pinyin" unless verifier_calls == 2
      puts "production-verifier-linked=true"
    ' "${dockerfile}"
  }

  verify_archive() {
    archive=$1
    expected_hash=$2
    destination=$3
    UNZIP_BIN="${fixture}/bin/unzip" \
    UNZIP_LOG="${fixture}/unzip.log" \
      sh "${verifier}" "${archive}" "${expected_hash}" "${destination}"
  }

  verify_both_archives() {
    verify_archive "${fixture}/ik.zip" "${ik_hash}" "${fixture}/out/ik" &&
      verify_archive "${fixture}/pinyin.zip" "${pinyin_hash}" "${fixture}/out/pinyin"
  }

  It "links both Dockerfile downloads to the executable production verifier"
    When call inspect_production_path
    The output should eq "production-verifier-linked=true"
    The status should be success
  End

  It "rejects tampered IK bytes before unzip executes"
    printf 'tampered IK bytes\n' >"${fixture}/ik.zip"
    When call verify_archive "${fixture}/ik.zip" "${ik_hash}" "${fixture}/out/ik"
    The status should be failure
    The output should include "ik.zip: FAILED"
    The error should include "checksum did NOT match"
    The path "${fixture}/unzip.log" should not be exist
  End

  It "rejects tampered Pinyin bytes before unzip executes"
    printf 'tampered Pinyin bytes\n' >"${fixture}/pinyin.zip"
    When call verify_archive "${fixture}/pinyin.zip" "${pinyin_hash}" "${fixture}/out/pinyin"
    The status should be failure
    The output should include "pinyin.zip: FAILED"
    The error should include "checksum did NOT match"
    The path "${fixture}/unzip.log" should not be exist
  End

  It "extracts both archives only when both hashes match"
    When call verify_both_archives
    The status should be success
    The output should include "ik.zip: OK"
    The output should include "pinyin.zip: OK"
    The contents of file "${fixture}/unzip.log" should eq "ik.zip
pinyin.zip"
  End
End
