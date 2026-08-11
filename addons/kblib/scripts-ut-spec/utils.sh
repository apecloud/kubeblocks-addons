#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

convert_tpl_to_bash() {
  local input_file="$1"
  local output_file="$2"

  sed -e '/^{{-\{0,1\}[[:space:]]*\/\*$/,/^\*\/}}$/d' \
      -e '/^{{-.*}}/d' \
      -e 's/{{- define ".*" }}//' \
      -e 's/{{- end }}//' \
      "$input_file" > "$output_file"
}
