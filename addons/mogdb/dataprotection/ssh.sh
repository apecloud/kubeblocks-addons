function setup_ssh_configure() {
    if [ ! -f /etc/ssh/ssh_config ]; then
        echo "SSH client config not exist!"
        exit 1
    fi

    {
        echo "StrictHostKeyChecking no"
    } >> /etc/ssh/ssh_config

    mkdir -p /home/omm/.ssh
    echo -n "$SSH_RSA" > /home/omm/.ssh/id_rsa

    chown -R omm:omm /home/omm/.ssh
    chmod 0600 /home/omm/.ssh/id_rsa
}