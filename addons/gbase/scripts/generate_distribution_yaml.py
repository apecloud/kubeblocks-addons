import sys
import yaml

gha_server_ips = sys.argv[1].split(',')
gtm_ips = sys.argv[2].split(',')
datanode_ips = sys.argv[3].split(',')
coordinator_ips = sys.argv[4].split(',')
dcs_ips = sys.argv[5].split(',')

data = {
    'gha_server': [],
    'gtm': [],
    'datanode': [],
    'coordinator': [],
    'dcs': [{'host': ip, 'port': 2379} for ip in dcs_ips],
    'env': {
        'cluster_type': 'multiple-nodes',
        'pkg_path': '/home/gbase/gbase_package',
        'prefix': '/home/gbase/gbase_db',
        'version': 'V5_S3.0.0B114',
        'user': 'gbase',
        'port': 22,
        'third_ssh': False
    }
}

# 配置gha_server
gha_server_port = 20001
for i, ip in enumerate(gha_server_ips):
    data['gha_server'].append({
        f'gha_server{i + 1}': {
            'host': ip,
            'port': gha_server_port
        }
    })
    gha_server_port += 1

# 配置gtm
gtm_port = 6666
agent_port = 8001
for i, ip in enumerate(gtm_ips):
    data['gtm'].append({
        f'gtm{i + 1}': {
            'host': ip,
            'agent_host': ip,
            'role': 'primary' if i == 0 else 'standby',
            'port': gtm_port,
            'agent_port': agent_port,
            'work_dir': f'/home/gbase/data/gtm/gtm{i + 1}'
        }
    })
    gtm_port += 1
    agent_port += 1

# 配置coordinator
coordinator_port = 5432
agent_port = 8010
for i, ip in enumerate(coordinator_ips):
    data['coordinator'].append({
        f'cn{i + 1}': {
            'host': ip,
            'agent_host': ip,
            'role': 'primary' if i == 0 else 'standby',
            'port': coordinator_port,
            'agent_port': agent_port,
            'work_dir': f'/home/gbase/data/coord/cn{i + 1}'
        }
    })
    coordinator_port += 1
    agent_port += 1

# 配置datanode
dn1 = []
dn2 = []
dn1_port = 15432
dn2_port = 20010
agent_port = 8025

for i, ip in enumerate(datanode_ips):
    dn1.append({
        f'dn1_{i + 1}': {
            'host': ip,
            'agent_host': ip,
            'role': 'primary' if i == 0 else 'standby',
            'port': dn1_port,
            'agent_port': agent_port,
            'work_dir': f'/home/gbase/data/dn1/dn1_{i + 1}'
        }
    })
    dn1_port += 1
    agent_port += 1

for i, ip in enumerate(datanode_ips):
    dn2.append({
        f'dn2_{i + 1}': {
            'host': ip,
            'agent_host': ip,
            'role': 'primary' if i == 0 else 'standby',
            'port': dn2_port,
            'agent_port': agent_port,
            'work_dir': f'/home/gbase/data/dn2/dn2_{i + 1}'
        }
    })
    dn2_port += 1
    agent_port += 1

data['datanode'].append({'dn1': dn1})
data['datanode'].append({'dn2': dn2})

# 将数据写入yaml文件
yaml_file_path = '/home/gbase/gbase_package/gbase.yml'

with open(yaml_file_path, 'w') as file:
    yaml.dump(data, file, default_flow_style=False)

with open(yaml_file_path, 'r') as file:
    loaded_data = yaml.safe_load(file)
    dcs_entries = [f"http://{entry['host']}:{entry['port']}" for entry in loaded_data['dcs']]
    dcs_output = ",".join(dcs_entries)
    print(dcs_output)