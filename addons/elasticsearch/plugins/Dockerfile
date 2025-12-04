FROM alpine:3.19.1

WORKDIR /plugins

# Install all plugins
RUN set -e && \
    # IK plugins for all versions \
    for version in 6.8.23 7.7.1 7.8.1 7.10.1 8.1.3 8.8.2 8.15.5; do \
        echo "Installing IK plugin for Elasticsearch $version"; \
        mkdir -p ./${version}/ik && \
        wget -q https://release.infinilabs.com/analysis-ik/stable/elasticsearch-analysis-ik-${version}.zip && \
        unzip -q elasticsearch-analysis-ik-${version}.zip -d ./${version}/ik/ && \
        rm elasticsearch-analysis-ik-${version}.zip; \
        echo "Installing Pinyin plugin for Elasticsearch $version"; \
        mkdir -p ./${version}/pinyin && \
        wget -q https://release.infinilabs.com/analysis-pinyin/stable/elasticsearch-analysis-pinyin-${version}.zip && \
        unzip -q elasticsearch-analysis-pinyin-${version}.zip -d ./${version}/pinyin/ && \
        rm elasticsearch-analysis-pinyin-${version}.zip; \
    done && \
    \
    # S3 plugins for 6.x and 7.x (8.x has it built-in) \
    for version in 6.8.23 7.7.1 7.8.1 7.10.1; do \
        echo "Installing S3 plugin for Elasticsearch $version"; \
        mkdir -p ./${version}/s3 && \
        wget -q https://artifacts.elastic.co/downloads/elasticsearch-plugins/repository-s3/repository-s3-${version}.zip && \
        unzip -q repository-s3-${version}.zip -d ./${version}/s3/ && \
        rm repository-s3-${version}.zip; \
    done && \
    \
    echo "All plugins installed successfully"
