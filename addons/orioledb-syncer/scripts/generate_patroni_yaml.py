#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys
import yaml


def write_file(config, filename, overwrite):
    if not overwrite and os.path.exists(filename):
        pass
    else:
        with open(filename, 'w') as f:
            f.write(config)


def read_file_lines(file):
    ret = []
    for line in file.readlines():
        line = line.strip()
        if line and not line.startswith('#'):
            ret.append(line)
    return ret


def postgresql_conf_to_dict(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
    lines = content.splitlines()
    result = {}
    for line in lines:
        if line.startswith('#'):
            continue
        if '=' not in line:
            continue
        key, value = line.split('=', 1)
        result[key.strip()] = value.strip().strip("'")
    return result


def main(filename):
    # restore_dir = os.environ.get('RESTORE_DATA_DIR', '')
    local_config = yaml.safe_load(
        os.environ.get('SPILO_CONFIGURATION',
                       os.environ.get('PATRONI_CONFIGURATION', ''))) or {}


    podip = os.environ.get('POD_IP')
    # scope
    local_config['scope'] = os.environ.get('POSTGRES_COMPONENT_NAME')
    # name
    local_config['name'] = os.environ.get('CURRENT_POD_NAME')

    # restapi
    local_config['restapi'] = {
        'listen': f'{podip}:8008',
        'connect_address': f'{podip}:8008',
    }
    # patroni kubernetes config
    kubernetes = {
        'bypass_api_service': True,
        'namespace': os.environ.get('CLUSTER_NAMESPACE'),
        'labels': yaml.safe_load(os.environ.get('KUBERNETES_LABELS')),
        'role_label':"kubeblocks.io/role",
        'leader_label_value':'primary',
        'follower_label_value':'secondary',
        'pod_ip': podip,
        'ports': [{"name": "tcp-orioledb", "port": 5432}],
        'service_host': os.environ.get('KUBERNETES_SERVICE_HOST'),
        'service_port': os.environ.get('KUBERNETES_SERVICE_PORT'),
        'service_port_https': os.environ.get('KUBERNETES_SERVICE_PORT_HTTPS'),
    }
    local_config['kubernetes'] = kubernetes
    
    if 'postgresql' not in local_config:
        local_config['postgresql'] = {}
    postgresql = {}
    postgresql['data_dir'] = os.environ.get('PGDATA')
    postgresql['config_dir'] = '/home/postgres/pgdata/conf'
    postgresql['custom_conf'] = '/home/postgres/conf/postgresql.conf'
    postgresql['listen'] = '0.0.0.0:5432'
    postgresql['connect_address'] = f'{podip}:5432'
    local_config['postgresql'] = postgresql
    authentication = {}
    authentication['superuser'] = {
        "username": os.environ.get('PGUSER_SUPERUSER'),
        'password': os.environ.get('PGPASSWORD_SUPERUSER')
    }
    authentication['replication'] = {
        'username': os.environ.get('PGUSER_SUPERUSER'),
        'password': os.environ.get('POSTGRES_PASSWORD')
    }
    authentication['rewind'] = {
        'username': os.environ.get('PGUSER_SUPERUSER'),
        'password': os.environ.get('POSTGRES_PASSWORD')
    }
    postgresql['authentication'] = authentication
    postgresql['use_slots'] = True


    # add pg_hba.conf
    with open('/home/postgres/conf/pg_hba.conf', 'r') as f:
        lines = read_file_lines(f)
        if lines:
            postgresql['pg_hba'] = lines

    # patroni parameters
    if 'bootstrap' not in local_config:
        local_config['bootstrap'] = {}
    if 'dcs' not in local_config['bootstrap']:
        dcs = {}
        dcs['postgresql'] = postgresql
        local_config['bootstrap']['dcs'] = dcs

        


    if os.path.exists('/home/postgres/conf/patroni.yaml'):
        with open('/home/postgres/conf/patroni.yaml', 'r') as f:
            local_config['bootstrap']['dcs'].update(yaml.safe_load(f))
    else:
        print('patroni.yaml not found')
    write_file(yaml.dump(local_config, default_flow_style=False), filename, True)


if __name__ == '__main__':
    main(sys.argv[1])
