# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# shellcheck shell=bash

source ./utils.sh

Describe 'kblib template converter'
  setup() {
    input_file="${SHELLSPEC_TMPBASE}/kblib-template-input-${SHELLSPEC_SPECFILE_ID}"
    output_file="${SHELLSPEC_TMPBASE}/kblib-template-output-${SHELLSPEC_SPECFILE_ID}"
  }
  BeforeEach 'setup'

  convert_fixture() {
    marker="$1"
    {
      printf '%s\n' "$marker"
      printf '%s\n' 'Copyright ApeCloud Co., Ltd. All Rights Reserved.'
      printf '%s\n' '*/}}'
      printf '%s\n' 'converted_content=true'
    } > "$input_file"

    convert_tpl_to_bash "$input_file" "$output_file"
  }

  It 'removes a regular Helm comment block'
    When call convert_fixture '{{/*'
    The status should be success
    The contents of file "$output_file" should eq 'converted_content=true'
  End

  It 'removes a whitespace-trimming Helm comment block'
    When call convert_fixture '{{- /*'
    The status should be success
    The contents of file "$output_file" should eq 'converted_content=true'
  End
End
