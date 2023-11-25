#!/bin/bash
set -o errexit
set -e

export GAUSSHOME=/usr/local/opengauss
export PATH=$GAUSSHOME/bin:$PATH
export LD_LIBRARY_PATH=$GAUSSHOME/lib:$LD_LIBRARY_PATH
export LANG=en_US.UTF-8

cp /home/omm/conf/* /tmp/
chmod 777 /tmp/postgresql.conf /tmp/pg_hba.conf
