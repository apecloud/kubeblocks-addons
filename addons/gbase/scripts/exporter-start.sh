#!/bin/bash   

docker-entrypoint.sh opengauss_exporter --url="postgresql://${KBADMIN_USER}:${KBADMIN_PASSWORD}@localhost:${gbase_service_port}/postgres"