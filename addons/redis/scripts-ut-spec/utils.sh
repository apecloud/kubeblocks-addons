#!/bin/bash

# utils functions for shellspec unit tests

convert_tpl_to_bash() {
  local input_file="$1"
  local output_file="$2"

  sed -e '/^{{\/\*$/,/^\*\/}}$/d' \
      -e '/^{{-.*}}/d' \
      -e 's/{{- define ".*" }}//' \
      -e 's/{{- end }}//' \
      "$input_file" >> "$output_file"
}

generate_common_library() {
  local library_file="$1"

  libpods_tpl_file="../../kblib/templates/_libpods.tpl"
  libstrings_tpl_file="../../kblib/templates/_libstrings.tpl"
  libenvs_tpl_file="../../kblib/templates/_libenvs.tpl"

  convert_tpl_to_bash $libpods_tpl_file "$library_file"
  convert_tpl_to_bash $libstrings_tpl_file "$library_file"
  convert_tpl_to_bash $libenvs_tpl_file "$library_file"
}