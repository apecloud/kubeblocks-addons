import sys
import yaml

def main():
    yaml_file_path = '/home/gbase/gbase_package/gbase.yml'
    try:
        with open(yaml_file_path, 'r') as file:
            data = yaml.safe_load(file)
        
        # 提取 GTM 的工作目录
        for gtm in data['gtm']:
            for key in gtm:
                print(gtm[key]['work_dir'])

        # 提取 Coordinators 的工作目录
        for coord in data['coordinator']:
            for key in coord:
                print(coord[key]['work_dir'])

        # 提取所有 DataNodes 的工作目录
        for dn_group in data['datanode']:
            for dn_list in dn_group.values():
                for dn in dn_list:
                    for key in dn:
                        print(dn[key]['work_dir'])

    except Exception as e:
        print(f"Error reading or processing YAML file: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()