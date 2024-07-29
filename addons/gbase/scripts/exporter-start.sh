#!/bin/bash   

export DATA_SOURCE_NAME="postgresql://postgres@localhost:15400/postgres?sslmode=disable"


docker-entrypoint.sh opengauss_exporter