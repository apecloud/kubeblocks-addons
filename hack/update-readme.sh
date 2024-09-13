#!/bin/bash
cat hack/readme-header.tpl | sed '$a\'> README.md

sh hack/get-addons.sh >> README.md