#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

chart=${1:?chart path is required}

helm template elasticsearch "${chart}" \
  --set es9.enabled=true \
  --set-string es9.images.elasticsearch="${ES9_ES_DIGEST}" \
  --set-string es9.images.kibana="${ES9_KIBANA_DIGEST}" \
  --set-string es9.images.plugin="${ES9_PLUGIN_DIGEST}" \
  --set-string es9.images.exporter="${ES9_EXPORTER_DIGEST}" \
  --set-string es9.images.tools="${ES9_TOOLS_DIGEST}" \
  --set-string es9.images.agent="${ES9_AGENT_DIGEST}" \
  --set-string es9.images.esDump="${ES9_ES_DUMP_DIGEST}" |
  ruby "$(dirname "$0")/es9_contract_check.rb"
