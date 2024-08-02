#
# Copyright 2022 The KubeBlocks Authors
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

################################################################################
# Variables                                                                    #
################################################################################
# Define the target operating system if needed
OS ?= $(shell uname)
# Define the target system architecture if needed
ARCH ?= $(shell uname -m)

ifeq ($(OS), Darwin)
	OS=darwin
else ifeq ($(OS), Linux)
	OS=linux
endif

ifeq ($(ARCH), arm64)
	ARCH=aarch64
else ifeq ($(ARCH), amd64)
	ARCH=x86_64
endif

# Define the installation directory
PREFIX ?= /usr/local
SC_BINARY_PATH := $(PREFIX)/bin/shellcheck
SC_VERSION ?= "v0.10.0"
SC_URL := https://github.com/koalaman/shellcheck/releases/download/$(SC_VERSION)/shellcheck-$(SC_VERSION).$(OS).$(ARCH).tar.xz
SC_BUILD_DIR := shellcheck-build
SC_DOWNLOAD_FILE := shellcheck-$(SC_VERSION).$(OS).$(ARCH).tar.xz
SC_OPTIONS ?= --format=tty --severity=error
SHELLCHECK_FILE ?=
SHELLSPEC_LOAD_PATH ?= ./shellspec

.PHONY: help
help: ##    Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


.PHONY: install-shellcheck
install-shellcheck: ## Download shellcheck locally if necessary.
ifeq (, $(shell which shellcheck))
	@echo "Downloading ShellCheck..."
	@curl -L $(SC_URL) -o $(SC_DOWNLOAD_FILE)
	@echo "Extracting ShellCheck..."
	@mkdir -p $(SC_BUILD_DIR)
	@tar xvf $(SC_DOWNLOAD_FILE) -C $(SC_BUILD_DIR)
	@echo "Installing ShellCheck..."
	@mkdir -p $(PREFIX)/bin
	@sudo cp $(SC_BUILD_DIR)/shellcheck-$(SC_VERSION)/shellcheck $(SC_BINARY_PATH)
	@chmod +x $(SC_BINARY_PATH)
	@echo "Remove ShellCheck temporary files and directories..."
	@rm -rf $(SC_BUILD_DIR) $(SC_DOWNLOAD_FILE)
	@echo "ShellCheck Successfully installed"
	@shellcheck --version
else
	@echo "ShellCheck is detected: "$(shell which shellcheck)
	@shellcheck --version
endif

ifeq (, $(SHELLCHECK_FILE))
SCRIPT_FILES := $(shell find . -type f -name "*.sh")
endif

.PHONY: shellcheck
shellcheck: install-shellcheck ##    Run shellcheck on all shell scripts if not specify `SHELLCHECK_FILE`.
ifeq (, $(SHELLCHECK_FILE))
	$(foreach scriptFile, $(SCRIPT_FILES), \
		shellcheck $(SC_OPTIONS) $(scriptFile); \
	)
else
	@shellcheck $(SC_OPTIONS) $(SHELLCHECK_FILE)
endif

.PHONY: install-shellspec
install-shellspec: ## Install shellspec if necessary.
ifeq (, $(shell which shellspec))
	@echo "Installing ShellSpec..."
	@curl -fsSL https://git.io/shellspec | sh -s -- --yes
	@echo "ShellSpec Successfully installed"
	@shellspec --version
else
	@echo "ShellSpec is detected: "$(shell which shellspec)
	@shellspec --version
endif

.PHONY: scripts-test
scripts-test: install-shellspec ## Run shellspec tests.
	@shellspec --load-path $(SHELLSPEC_LOAD_PATH)