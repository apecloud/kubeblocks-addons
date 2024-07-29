#!/bin/bash

echo "start config $KB_COMP_NAME..."

echo "configure ssh..."

rm -rf /home/gbase/.ssh
rm -rf /root/.ssh

mkdir -p /home/gbase/.ssh
mkdir -p /root/.ssh

cp /ssh-key/id_rsa /home/gbase/.ssh/id_rsa
cp /ssh-key/id_rsa.pub /home/gbase/.ssh/id_rsa.pub
cp /ssh-key/id_rsa /root/.ssh/id_rsa
cp /ssh-key/id_rsa.pub /root/.ssh/id_rsa.pub

cat /ssh-key/id_rsa.pub >> /home/gbase/.ssh/authorized_keys
cat /ssh-key/id_rsa.pub >> /root/.ssh/authorized_keys

chown -R gbase:gbase /home/gbase/.ssh
chmod 700 /home/gbase/.ssh /root/.ssh
chmod 600 /home/gbase/.ssh/id_rsa /home/gbase/.ssh/authorized_keys /root/.ssh/id_rsa /root/.ssh/authorized_keys

echo 'StrictHostKeyChecking no' >> /home/gbase/.ssh/config
echo 'UserKnownHostsFile ~/.ssh/known_hosts' >> /home/gbase/.ssh/config
chmod 644 /home/gbase/.ssh/config

echo 'StrictHostKeyChecking no' >> /root/.ssh/config
echo 'UserKnownHostsFile ~/.ssh/known_hosts' >> /root/.ssh/config
chmod 644 /root/.ssh/config

echo "complete ssh configure"

