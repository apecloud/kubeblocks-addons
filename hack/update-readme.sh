#!/bin/bash
cat hack/readme-header.tpl | sed '$a\'> README.md

bash hack/get-addons.sh >> README.md