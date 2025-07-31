# Elasticsearch Agent Makefile

IMAGE_REGISTRY ?= apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com
IMAGE_REPOSITORY ?= apecloud/elasticsearch-agent
IMAGE_TAG ?= 0.1.0
FULL_IMAGE_NAME = $(IMAGE_REGISTRY)/$(IMAGE_REPOSITORY):$(IMAGE_TAG)
PLATFORMS ?= linux/amd64,linux/arm64

.PHONY: build push

build:
	@echo "Building Docker image: $(FULL_IMAGE_NAME)"
	@if ! docker buildx ls | grep -q multiarch-builder; then \
		docker buildx create --name multiarch-builder --driver docker-container --bootstrap; \
	fi
	@docker buildx use multiarch-builder
	@docker buildx build --platform $(PLATFORMS) --tag $(FULL_IMAGE_NAME) .
	@echo "Successfully built image: $(FULL_IMAGE_NAME)"

push:
	@echo "Building and pushing Docker image: $(FULL_IMAGE_NAME)"
	@if ! docker buildx ls | grep -q multiarch-builder; then \
		docker buildx create --name multiarch-builder --driver docker-container --bootstrap; \
	fi
	@docker buildx use multiarch-builder
	@docker buildx build --platform $(PLATFORMS) --tag $(FULL_IMAGE_NAME) --push .
	@echo "Successfully pushed image: $(FULL_IMAGE_NAME)"
