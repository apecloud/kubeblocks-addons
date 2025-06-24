#!/bin/bash
set -exo pipefail

default_template_conf="$CONFIG_TEMPLATE_PATH"
default_conf="$CONFIG_FILE_PATH"

cp "$default_template_conf" "$default_conf"
sed -i.bak "s/^initial-cluster-state: 'new'/initial-cluster-state: 'existing'/g" "$default_conf"
rm "$default_conf.bak"
