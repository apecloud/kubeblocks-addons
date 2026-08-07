FROM alpine:3.19.1 AS es9-plugins

WORKDIR /plugins

# Elasticsearch 9.x plugin artifacts are release inputs. Verify the frozen
# upstream bytes before extracting them so a changed ZIP fails the image build.
COPY verify-and-unpack.sh /usr/local/bin/verify-and-unpack-plugin

RUN set -e && \
    version=9.3.2 && \
    ik_zip="elasticsearch-analysis-ik-${version}.zip" && \
    pinyin_zip="elasticsearch-analysis-pinyin-${version}.zip" && \
    wget -q "https://release.infinilabs.com/analysis-ik/stable/${ik_zip}" && \
    /usr/local/bin/verify-and-unpack-plugin \
      "${ik_zip}" \
      '804758ddd632fb460ca09bdd04f3c0aa70da878e03cbb53ae122137e4f18b2c5' \
      "./${version}/ik" && \
    rm "${ik_zip}" && \
    wget -q "https://release.infinilabs.com/analysis-pinyin/stable/${pinyin_zip}" && \
    /usr/local/bin/verify-and-unpack-plugin \
      "${pinyin_zip}" \
      'e418aa3a410257520c3480a0a741a7e388e3e69832a8c52cd7c190872c0abe99' \
      "./${version}/pinyin" && \
    rm "${pinyin_zip}" && \
    rm /usr/local/bin/verify-and-unpack-plugin

FROM es9-plugins

# Install all plugins
RUN set -e && \
    # IK plugins for all versions \
    for version in 6.8.23 7.7.1 7.8.1 7.10.1 7.10.2 8.1.3 8.8.2 8.15.5 8.19.0; do \
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
    for version in 6.8.23 7.7.1 7.8.1 7.10.1 7.10.2; do \
        echo "Installing S3 plugin for Elasticsearch $version"; \
        mkdir -p ./${version}/s3 && \
        wget -q https://artifacts.elastic.co/downloads/elasticsearch-plugins/repository-s3/repository-s3-${version}.zip && \
        unzip -q repository-s3-${version}.zip -d ./${version}/s3/ && \
        rm repository-s3-${version}.zip; \
    done && \
    \
    echo "All plugins installed successfully"
