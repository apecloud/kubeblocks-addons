import sys
import yaml

kb_pod_list = sys.argv[1:]

data = {
    'gha_server': [
        {
            'gha_server1': {
                'host': kb_pod_list[0],
                'port': 20001
            }
        }
    ],
    'dcs': [{'host': ip, 'port': 2379} for ip in kb_pod_list],
    'gtm': [
        {
            'gtm1': {
                'host': kb_pod_list[0],
                'agent_host': kb_pod_list[0],
                'role': 'primary',
                'port': 6666,
                'agent_port': 8001,
                'work_dir': '/data/gtm/gtm1'
            }
        }
    ],
    'coordinator': [
        {
            'cn1': {
                'host': kb_pod_list[0],
                'agent_host': kb_pod_list[0],
                'role': 'primary',
                'port': 5432,
                'agent_port': 8003,
                'work_dir': '/data/coord/cn1'
            }
        }
    ],
    'datanode': []
}

dn1 = []
dn2 = []
port = 15432
agent_port = 8005
for i, ip in enumerate(kb_pod_list):
    dn1.append({
        f'dn1_{i+1}': {
            'host': ip,
            'agent_host': ip,
            'role': 'primary' if i == 0 else 'standby',
            'port': port,
            'agent_port': agent_port,
            'work_dir': f'/data/dn1/dn1_{i+1}'
        }
    })
    port += 1
    agent_port += 1

port = 20010
for i, ip in enumerate(kb_pod_list):
    dn2.append({
        f'dn2_{i+1}': {
            'host': ip,
            'agent_host': ip,
            'role': 'primary' if i == 0 else 'standby',
            'port': port,
            'agent_port': agent_port,
            'work_dir': f'/data/dn2/dn2_{i+1}'
        }
    })
    port += 1
    agent_port += 1

data['datanode'].append({'dn1': dn1})
data['datanode'].append({'dn2': dn2})

data['env'] = {
    'cluster_type': 'multiple-nodes',
    'pkg_path': '/home/gbase/gbase_package',
    'prefix': '/home/gbase/gbase_db',
    'version': 'V5_S3.0.0B76',
    'user': 'gbase',
    'port': 22,
    'third_ssh': False
}

yaml_file_path = '/home/gbase/gbase_package/gbase.yml'

with open(yaml_file_path, 'w') as file:
    yaml.dump(data, file, default_flow_style=False)

with open(yaml_file_path, 'r') as file:
    loaded_data = yaml.safe_load(file)
    dcs_entries = [f"http://{entry['host']}:{entry['port']}" for entry in loaded_data['dcs']]
    dcs_output = ",".join(dcs_entries)
    print(dcs_output)
