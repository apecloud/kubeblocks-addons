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

data['datanode'].append({'dn1': dn1})

data['env'] = {
    'cluster_type': 'single-inst',
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