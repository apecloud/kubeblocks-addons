FROM alpine:3.19.1

WORKDIR /plugins

RUN wget https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v8.8.2/elasticsearch-analysis-ik-8.8.2.zip \
    && unzip elasticsearch-analysis-ik-8.8.2.zip -d ./analysis-ik/ \
    && rm elasticsearch-analysis-ik-8.8.2.zip
