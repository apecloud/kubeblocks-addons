#!/usr/bin/env bash

set -eu

# the operator only works with the default ES distribution
license=/usr/share/elasticsearch/LICENSE.txt
if [[ ! -f $license || $(grep -Exc "ELASTIC LICENSE AGREEMENT|Elastic License 2.0" $license) -ne 1 ]]; then
    >&2 echo "unsupported_distribution"
    exit 42
fi

# compute time in seconds since the given start time
function duration() {
    local start=$1
    end=$(date +%s)
    echo $((end-start))
}

######################
#       START       #
######################

script_start=$(date +%s)

echo "Starting init script"

######################
#  Files persistence #
######################

# Persist the content of bin/, config/ and plugins/ to a volume,
# so installed plugins files can to be used by the ES container
mv_start=$(date +%s)

    if [[ -z "$(ls -A /usr/share/elasticsearch/config)" ]]; then
        echo "Empty dir /usr/share/elasticsearch/config"
    else
        echo "Copying /usr/share/elasticsearch/config/* to /mnt/elastic-internal/elasticsearch-config-local/"
        # Use "yes" and "-f" as we want the init container to be idempotent and not to fail when executed more than once.
        yes | cp -avf /usr/share/elasticsearch/config/* /mnt/elastic-internal/elasticsearch-config-local/
    fi

    if [[ -z "$(ls -A /usr/share/elasticsearch/plugins)" ]]; then
        echo "Empty dir /usr/share/elasticsearch/plugins"
    else
        echo "Copying /usr/share/elasticsearch/plugins/* to /mnt/elastic-internal/elasticsearch-plugins-local/"
        # Use "yes" and "-f" as we want the init container to be idempotent and not to fail when executed more than once.
        yes | cp -avf /usr/share/elasticsearch/plugins/* /mnt/elastic-internal/elasticsearch-plugins-local/
    fi

    if [[ -z "$(ls -A /usr/share/elasticsearch/bin)" ]]; then
        echo "Empty dir /usr/share/elasticsearch/bin"
    else
        echo "Copying /usr/share/elasticsearch/bin/* to /mnt/elastic-internal/elasticsearch-bin-local/"
        # Use "yes" and "-f" as we want the init container to be idempotent and not to fail when executed more than once.
        yes | cp -avf /usr/share/elasticsearch/bin/* /mnt/elastic-internal/elasticsearch-bin-local/
    fi

echo "Files copy duration: $(duration $mv_start) sec."

######################
#  Config linking    #
######################

# Link individual files from their mount location into the config dir
# to a volume, to be used by the ES container
ln_start=$(date +%s)

#    echo "Linking /mnt/elastic-internal/xpack-file-realm/users to /mnt/elastic-internal/elasticsearch-config-local/users"
#    ln -sf /mnt/elastic-internal/xpack-file-realm/users /mnt/elastic-internal/elasticsearch-config-local/users

#    echo "Linking /mnt/elastic-internal/xpack-file-realm/roles.yml to /mnt/elastic-internal/elasticsearch-config-local/roles.yml"
#    ln -sf /mnt/elastic-internal/xpack-file-realm/roles.yml /mnt/elastic-internal/elasticsearch-config-local/roles.yml

#    echo "Linking /mnt/elastic-internal/xpack-file-realm/users_roles to /mnt/elastic-internal/elasticsearch-config-local/users_roles"
#    ln -sf /mnt/elastic-internal/xpack-file-realm/users_roles /mnt/elastic-internal/elasticsearch-config-local/users_roles

    echo "Linking /mnt/elastic-internal/elasticsearch-config/elasticsearch.yml to /mnt/elastic-internal/elasticsearch-config-local/elasticsearch.yml"
    ln -sf /mnt/elastic-internal/elasticsearch-config/elasticsearch.yml /mnt/elastic-internal/elasticsearch-config-local/elasticsearch.yml

#    echo "Linking /mnt/elastic-internal/unicast-hosts/unicast_hosts.txt to /mnt/elastic-internal/elasticsearch-config-local/unicast_hosts.txt"
#    ln -sf /mnt/elastic-internal/unicast-hosts/unicast_hosts.txt /mnt/elastic-internal/elasticsearch-config-local/unicast_hosts.txt

#    echo "Linking /mnt/elastic-internal/xpack-file-realm/service_tokens to /mnt/elastic-internal/elasticsearch-config-local/service_tokens"
#    ln -sf /mnt/elastic-internal/xpack-file-realm/service_tokens /mnt/elastic-internal/elasticsearch-config-local/service_tokens

echo "File linking duration: $(duration $ln_start) sec."

######################
#         End        #
######################

echo "Init script successful"
echo "Script duration: $(duration $script_start) sec."