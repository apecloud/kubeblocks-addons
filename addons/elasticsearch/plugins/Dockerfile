FROM alpine:3.19.1

WORKDIR /plugins

# Install IK analysis plugin for Chinese text analysis
# Create version-specific directories for IK plugins
RUN mkdir -p ./6.8.23/ik ./7.7.1/ik ./7.8.1/ik ./7.10.1/ik ./8.1.3/ik ./8.8.2/ik ./8.15.5/ik

# Download IK plugin for each Elasticsearch version
RUN wget -q https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v6.8.23/elasticsearch-analysis-ik-6.8.23.zip \
    && unzip -q elasticsearch-analysis-ik-6.8.23.zip -d ./6.8.23/ik/ \
    && rm elasticsearch-analysis-ik-6.8.23.zip

RUN wget -q https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v7.7.1/elasticsearch-analysis-ik-7.7.1.zip \
    && unzip -q elasticsearch-analysis-ik-7.7.1.zip -d ./7.7.1/ik/ \
    && rm elasticsearch-analysis-ik-7.7.1.zip

RUN wget -q https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v7.8.1/elasticsearch-analysis-ik-7.8.1.zip \
    && unzip -q elasticsearch-analysis-ik-7.8.1.zip -d ./7.8.1/ik/ \
    && rm elasticsearch-analysis-ik-7.8.1.zip

RUN wget -q https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v7.10.1/elasticsearch-analysis-ik-7.10.1.zip \
    && unzip -q elasticsearch-analysis-ik-7.10.1.zip -d ./7.10.1/ik/ \
    && rm elasticsearch-analysis-ik-7.10.1.zip

RUN wget -q https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v8.1.3/elasticsearch-analysis-ik-8.1.3.zip \
    && unzip -q elasticsearch-analysis-ik-8.1.3.zip -d ./8.1.3/ik/ \
    && rm elasticsearch-analysis-ik-8.1.3.zip

RUN wget -q https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v8.8.2/elasticsearch-analysis-ik-8.8.2.zip \
    && unzip -q elasticsearch-analysis-ik-8.8.2.zip -d ./8.8.2/ik/ \
    && rm elasticsearch-analysis-ik-8.8.2.zip

RUN wget -q https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v8.15.5/elasticsearch-analysis-ik-8.15.5.zip \
    && unzip -q elasticsearch-analysis-ik-8.15.5.zip -d ./8.15.5/ik/ \
    && rm elasticsearch-analysis-ik-8.15.5.zip

# Install S3 repository plugin for backup functionality
# S3 plugins are placed in version-specific subdirectories
RUN wget -q https://artifacts.elastic.co/downloads/elasticsearch-plugins/repository-s3/repository-s3-6.8.23.zip \
    && unzip -q repository-s3-6.8.23.zip -d ./6.8.23/s3/ \
    && rm repository-s3-6.8.23.zip

RUN wget -q https://artifacts.elastic.co/downloads/elasticsearch-plugins/repository-s3/repository-s3-7.7.1.zip \
    && unzip -q repository-s3-7.7.1.zip -d ./7.7.1/s3/ \
    && rm repository-s3-7.7.1.zip

RUN wget -q https://artifacts.elastic.co/downloads/elasticsearch-plugins/repository-s3/repository-s3-7.8.1.zip \
    && unzip -q repository-s3-7.8.1.zip -d ./7.8.1/s3/ \
    && rm repository-s3-7.8.1.zip

RUN wget -q https://artifacts.elastic.co/downloads/elasticsearch-plugins/repository-s3/repository-s3-7.10.1.zip \
    && unzip -q repository-s3-7.10.1.zip -d ./7.10.1/s3/ \
    && rm repository-s3-7.10.1.zip

# For Elasticsearch 8.x, S3 plugin is included in core by default, no need to download
