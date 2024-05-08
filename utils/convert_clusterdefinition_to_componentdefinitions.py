import argparse
import yaml
import os
import subprocess
from datetime import datetime
from dataclasses import dataclass
from typing import List

API_VERSION = "apps.kubeblocks.io/v1alpha1"
COMPONENT_DEFINITION_KIND = "ComponentDefinition"
COMPONENT_DEFINITION_YAML_FILE_PREFIX = "componentdefinition-"
HOST_NETWORK_DYNAMIC_PORT_THRESHOLD = 100
UNKNOWN_BUILTIN_ACTION_HANDLER = "UnknownBuiltinActionHandler"
READ_WRITE_MODE = "ReadWrite"
WORKLOAD_CONSENSUS = "Consensus"
WORKLOAD_REPLICATION = "Replication"
WORKLOAD_STATEFUL = "Stateful"
WORKLOAD_STATELESS = "Stateless"
LEADER = "Leader"
PRIMARY = "Primary"


@dataclass
class Port:
    name: str
    container_port: int


@dataclass
class Container:
    name: str
    ports: List[Port]


@dataclass
class HostNetworkContainerPort:
    container: str
    ports: List[str]


@dataclass
class HostNetwork:
    container_ports: List[HostNetworkContainerPort]


class ComponentVolume:
    def __init__(self, name, need_snapshot=False, high_watermark=0):
        self.name = name
        self.need_snapshot = need_snapshot
        self.high_watermark = high_watermark


class ProtectedVolume:
    def __init__(self, name=None, high_watermark=None):
        self.name = name
        self.high_watermark = high_watermark


class VolumeProtectionSpec:
    def __init__(self, high_watermark, volumes):
        self.high_watermark = high_watermark
        self.volumes = volumes


class ReplicaRole:
    def __init__(self, name, serviceable, writable, votable):
        self.name = name
        self.serviceable = serviceable
        self.writable = writable
        self.votable = votable


class HelmTemplateRenderer:
    @staticmethod
    def render_helm_template(chart_path, output_path, template_name):
        try:
            subprocess.run(['helm', 'template', chart_path, '--show-only', template_name],
                           stdout=open(output_path, 'w'), check=True)
        except subprocess.CalledProcessError as e:
            raise Exception(f"Failed to render Helm template: {e}")

    @staticmethod
    def delete_temp_files(file_paths):
        for file_path in file_paths:
            if os.path.exists(file_path):
                os.remove(file_path)
                print(f"Deleted temporary file: {file_path}")

    @staticmethod
    def keep_first_cluster_version(file_path):
        with open(file_path, 'r') as file:
            yaml_content = yaml.safe_load_all(file)
            cluster_versions = list(yaml_content)

        if len(cluster_versions) > 1:
            first_cluster_version = cluster_versions[0]
            with open(file_path, 'w') as file:
                yaml.dump(first_cluster_version, file)
            print(f"Kept only the first ClusterVersion object in {file_path}")


class ClusterDefinitionConvertor:
    def __init__(self, cluster_def, cluster_ver):
        self.cluster_def = cluster_def
        self.cluster_ver = cluster_ver
        self.cluster_comp_ver_map = self.parse_cluster_comp_ver_map()

    def convert(self):
        component_defs = []
        for cluster_comp_def in self.cluster_def.get('spec', {}).get('componentDefs', []):
            converter = ComponentDefinitionConvertor(
                self.cluster_def, self.cluster_ver, cluster_comp_def, self.cluster_comp_ver_map)
            component_def = converter.convert()
            component_defs.append(component_def)
        return component_defs

    def parse_cluster_comp_ver_map(self):
        comp_ver_map = {}
        for comp_ver in self.cluster_ver.get('spec', {}).get('componentVersions', []):
            comp_ver_map[comp_ver['componentDefRef']] = comp_ver
        return comp_ver_map


class ComponentDefinitionConvertor:
    def __init__(self, cluster_def, cluster_ver, cluster_comp_def, cluster_comp_ver_map):
        self.cluster_comp_ver_map = cluster_comp_ver_map
        self.cluster_def = cluster_def
        self.cluster_ver = cluster_ver
        self.cluster_comp_def = cluster_comp_def

    def convert(self):
        if self.cluster_comp_def is None:
            return None

        comp_def = {
            'apiVersion': API_VERSION,
            'kind': COMPONENT_DEFINITION_KIND,
            'metadata': self.build_metadata(),
            'spec': self.convert_spec()
        }

        return comp_def

    def build_metadata(self):
        return {
            'name': self.cluster_comp_def['name'],
            'labels': self.cluster_def.get('metadata', {}).get('labels', {}),
            'annotations': self.cluster_def.get('metadata', {}).get('annotations', {})
        }

    def convert_spec(self):
        cmpd_spec = {
            'provider': self.convert_provider(),
            'description': self.convert_description(),
            'serviceKind': self.convert_service_kind(),
            'serviceVersion': self.convert_service_version(),
            'runtime': self.convert_runtime()
        }

        # convert vars if needed
        cmpd_vars = self.convert_vars()
        if cmpd_vars:
            cmpd_spec['vars'] = cmpd_vars

        # convert host network if needed
        host_network = self.convert_host_network()
        if host_network:
            cmpd_spec['hostnetwork'] = host_network

        # convert component services if needed
        component_services = self.convert_component_services()
        if component_services:
            cmpd_spec['services'] = component_services

        # convert configs if needed
        config_specs = self.convert_configs()
        if config_specs:
            cmpd_spec['configs'] = config_specs

        # convert scripts if needed
        script_specs = self.convert_scripts()
        if script_specs:
            cmpd_spec['scripts'] = script_specs

        # convert log configs if needed
        log_configs = self.convert_log_configs()
        if log_configs:
            cmpd_spec['logConfigs'] = log_configs

        # convert service ref declarations if needed
        service_ref_declarations = self.convert_service_ref_declaration()
        if service_ref_declarations:
            cmpd_spec['serviceRefDeclarations'] = service_ref_declarations

        # convert sidecar container if needed
        sidecar_container = self.convert_sidecar_container()
        if sidecar_container:
            cmpd_spec['sidecarContainers'] = sidecar_container

        # convert labels if needed
        labels = self.convert_labels()
        if labels:
            cmpd_spec['labels'] = labels

        # convert system accounts if needed
        system_accounts = self.convert_system_accounts()
        if system_accounts:
            cmpd_spec['systemAccounts'] = system_accounts

        # convert volumes if needed
        volumes = self.convert_volumes()
        if volumes:
            cmpd_spec['volumes'] = volumes

        # convert update strategy if needed
        update_strategy = self.convert_update_strategy()
        if update_strategy:
            cmpd_spec['updateStrategy'] = update_strategy

        # convert roles if needed
        roles = self.convert_roles()
        if roles:
            cmpd_spec['roles'] = roles

        # convert lifecycle actions if needed
        lifecycle_actions = self.convert_lifecycle_actions()
        if lifecycle_actions:
            cmpd_spec['lifecycleActions'] = lifecycle_actions

        return cmpd_spec

    @staticmethod
    def convert_provider():
        return 'KubeBlocks'

    def convert_service_kind(self):
        return self.cluster_comp_def['characterType']

    def convert_service_version(self):
        # parse the default version from the cluster version name
        return self.cluster_ver['metadata']['name'].split('-')[-1]

    def convert_description(self):
        return self.cluster_comp_def.get('description', '')

    def convert_scripts(self):
        return self.cluster_comp_def.get('scriptSpecs', [])

    def convert_log_configs(self):
        return self.cluster_comp_def.get('logConfigs', [])

    def convert_service_ref_declaration(self):
        return self.cluster_comp_def.get('serviceRefDeclarations', [])

    def convert_sidecar_container(self):
        return self.cluster_comp_def.get('sidecarContainerSpecs', [])

    @staticmethod
    def convert_policy_rules():
        return None

    @staticmethod
    def convert_replicas_limit():
        return None

    def convert_component_services(self):
        comp_services = []
        if 'service' not in self.cluster_comp_def:
            return comp_services

        service_spec = {
            'ports': self.cluster_comp_def['service']['ports'],
            'type': self.cluster_comp_def['service'].get('type', 'ClusterIP'),
        }

        comp_svc = {
            'name': 'default',
            'serviceName': '',
            'spec': service_spec
        }
        role_selector = self._role_selector()
        if role_selector:
            comp_svc['roleSelector'] = role_selector
        comp_services.append(comp_svc)

        return comp_services

    def convert_labels(self):
        labels = {}
        if 'customLabelSpecs' not in self.cluster_comp_def:
            return labels
        for label in self.cluster_comp_def['customLabelSpecs']:
            labels[label['key']] = label['value']
        return labels

    def convert_update_strategy(self):
        strategy = None

        workload_type = self.cluster_comp_def.get('workloadType')
        if workload_type == WORKLOAD_CONSENSUS:
            if 'rsmSpec' in self.cluster_comp_def and 'memberUpdateStrategy' in self.cluster_comp_def['rsmSpec']:
                strategy = self.cluster_comp_def['rsmSpec']['memberUpdateStrategy']
            if 'consensusSpec' in self.cluster_comp_def and 'updateStrategy' in self.cluster_comp_def['consensusSpec']:
                strategy = self.cluster_comp_def['consensusSpec']['updateStrategy']
        elif workload_type == WORKLOAD_REPLICATION:
            strategy = 'Serial'
        elif workload_type in [WORKLOAD_STATEFUL, WORKLOAD_STATELESS]:
            # do nothing
            pass
        else:
            raise ValueError(f"unknown workload type: {workload_type}")

        return strategy

    def convert_roles(self):
        replica_roles = self._convert_roles()
        if replica_roles is None:
            return []
        replica_roles_map_list = []
        for role in replica_roles:
            role_dict = {
                'name': role.name,
                'serviceable': role.serviceable,
                'writable': role.writable,
                'votable': role.votable
            }
            replica_roles_map_list.append(role_dict)

        return replica_roles_map_list

    def convert_configs(self):
        if self.cluster_comp_ver_map is None or self.cluster_comp_ver_map.get(self.cluster_comp_def['name']) is None:
            return self.cluster_comp_def.get('configSpecs', [])
        else:
            cluster_comp_ver = self.cluster_comp_ver_map[self.cluster_comp_def['name']]
            cluster_comp_ver_config_specs = cluster_comp_ver.get('configSpecs', [])
            return self._merge_config_templates(cluster_comp_ver_config_specs,
                                                self.cluster_comp_def.get('configSpecs', []))

    def convert_system_accounts(self):
        accounts = []
        if 'systemAccounts' in self.cluster_comp_def:
            for account in self.cluster_comp_def['systemAccounts']['accounts']:
                system_account = {
                    'name': account['name'],
                    'passwordGenerationPolicy': self.cluster_comp_def['systemAccounts']['passwordConfig'],
                }
                if account['provisionPolicy'].get('secretRef') is not None:
                    system_account['secretRef'] = account['provisionPolicy']['secretRef']
                if account['provisionPolicy'].get('statements') is not None:
                    if account['provisionPolicy']['statements'].get('creation') is not None:
                        system_account['statement'] = account['provisionPolicy']['statements'].get('creation', '')
                accounts.append(system_account)
        return accounts

    def convert_volumes(self):
        volumes = []
        if 'volumeTypes' in self.cluster_comp_def:
            comp_volumes = [ComponentVolume(vol['name'], False, 0) for vol in self.cluster_comp_def['volumeTypes']]
            if 'volumeProtectionSpec' not in self.cluster_comp_def:
                for volume in comp_volumes:
                    volumes.append({
                        'name': volume.name,
                        'needSnapshot': volume.need_snapshot,
                        'highWatermark': volume.high_watermark
                    })
                return volumes

            comp_volume_protection_volumes = self.cluster_comp_def['volumeProtectionSpec']['volumes']
            comp_volume_protection_high_watermark = self.cluster_comp_def['volumeProtectionSpec']['highWatermark']

            def high_watermark(protected_volume):
                return protected_volume['highWatermark'] if protected_volume['highWatermark'] is not None \
                    else comp_volume_protection_high_watermark

            def set_high_watermark(protected_vol):
                for i, c_volume in enumerate(comp_volumes):
                    if c_volume.name == protected_vol['name']:
                        c_volume.high_watermark = high_watermark(protected_vol)
                        break

            for vol in comp_volume_protection_volumes:
                set_high_watermark(vol)

            for volume in comp_volumes:
                volumes.append({
                    'name': volume.name,
                    'needSnapshot': volume.need_snapshot,
                    'highWatermark': volume.high_watermark
                })

        return volumes

    def convert_vars(self):
        cmpd_vars = []
        cmpd_vars.extend(self._convert_host_network_vars())
        return cmpd_vars

    def convert_host_network(self):
        host_network = self._convert_host_network()
        if not host_network or not host_network.container_ports:
            return None
        return {
            'containerPorts': host_network.container_ports
        }

    def convert_runtime(self):
        if self.cluster_comp_def.get('podSpec') is None:
            return None
        runtime = self.cluster_comp_def['podSpec']

        if self.cluster_ver is None or self.cluster_comp_ver_map is None or self.cluster_comp_ver_map.get(
                self.cluster_comp_def['name']) is None:
            return runtime

        cluster_comp_ver = self.cluster_comp_ver_map[self.cluster_comp_def['name']]
        cluster_comp_version_ctx = cluster_comp_ver.get('versionsContext', {})
        cluster_comp_version_ctx_init_containers = cluster_comp_version_ctx.get('initContainers', [])
        cluster_comp_version_ctx_containers = cluster_comp_version_ctx.get('containers', [])

        # handling initContainers
        if 'initContainers' in runtime:
            for init_container in cluster_comp_version_ctx_init_containers:
                runtime['initContainers'] = self._append_or_override_container_attr(runtime['initContainers'],
                                                                                    init_container)
        # handling containers
        if 'containers' in runtime:
            for container in cluster_comp_version_ctx_containers:
                runtime['containers'] = self._append_or_override_container_attr(runtime['containers'], container)

        return runtime

    def convert_lifecycle_actions(self):
        new_lifecycle_actions = {}
        lifecycle_actions = self._convert_lifecycle_actions()
        for k, v in lifecycle_actions.items():
            if v is not None:
                new_lifecycle_actions[k] = v
        return new_lifecycle_actions

    def _convert_lifecycle_actions(self):
        lifecycle_actions = {}

        if (self.cluster_comp_def.get('RSMSpec') and self.cluster_comp_def['RSMSpec'].get('roleProbe')) or \
                (self.cluster_comp_def.get('probes') and self.cluster_comp_def['probes'].get('roleProbe')):
            lifecycle_actions['roleProbe'] = self._convert_role_probe()

        if self.cluster_comp_def.get('switchoverSpec'):
            cv_switchover_spec = self.cluster_comp_ver_map[self.cluster_comp_def['name']].get('switchoverSpec')
            lifecycle_actions['switchover'] = self._convert_switchover(self.cluster_comp_def['switchoverSpec'],
                                                                       cv_switchover_spec)

        if self.cluster_comp_def.get('PostStartSpec'):
            lifecycle_actions['postProvision'] = self._convert_post_provision()

        # These are set to None, indicating no action is defined for them
        for action in ["preTerminate", "memberJoin", "memberLeave", "readonly",
                       "readwrite", "dataDump", "dataLoad", "reconfigure", "accountProvision"]:
            lifecycle_actions[action] = None

        return lifecycle_actions

    def _convert_role_probe(self):
        builtin_handler = self._get_builtin_action_handler()

        if self.cluster_comp_def.get('RSMSpec') and \
                self.cluster_comp_def['RSMSpec'].get('roleProbe', {}).get('customHandler'):
            custom_handler = self.cluster_comp_def['RSMSpec']['roleProbe']['customHandler'][0]
            return {
                'customHandler': {
                    'image': custom_handler['image'],
                    'exec': {
                        'command': custom_handler['command'],
                        'args': custom_handler['args']
                    }
                }
            }

        if not self.cluster_comp_def.get('probes') or not self.cluster_comp_def['probes'].get('roleProbe'):
            return None

        role_probe = self.cluster_comp_def['probes']['roleProbe']
        result = {
            'timeoutSeconds': role_probe['timeoutSeconds'],
            'periodSeconds': role_probe['periodSeconds'],
            'builtinHandler': builtin_handler
        }

        if role_probe.get('commands') is not None and (
                role_probe.get('commands').get('writes') or role_probe.get('commands').get('queries')):
            commands = role_probe['commands']['writes'] if role_probe['commands'].get('writes') \
                else role_probe['commands']['queries']
            result['customHandler'] = {'exec': {'command': commands}}

        return result

    def _convert_post_provision(self):
        if self.cluster_comp_def.get('postStartSpec') is None:
            return None

        post_start = self.cluster_comp_def['postStartSpec']
        return {
            'customHandler': {
                'image': post_start['cmdExecutorConfig']['Image'],
                'exec': {
                    'command': post_start['cmdExecutorConfig']['command'],
                    'args': post_start['cmdExecutorConfig']['args']
                },
                'env': post_start['cmdExecutorConfig']['env'],
                'preCondition': 'ComponentReady'
            }
        }

    def _convert_switchover(self, switchover, cluster_comp_ver):
        if cluster_comp_ver:
            switchover = self._override_switchover_spec_attr(switchover, cluster_comp_ver)

        if switchover.get('withCandidate') is None and switchover.get('withoutCandidate') is None:
            return None

        result = {}
        if switchover.get('withCandidate') and switchover['withCandidate'].get('cmdExecutorConfig'):
            result['withCandidate'] = {
                'image': switchover['withCandidate']['cmdExecutorConfig']['image'],
                'exec': {
                    'command': switchover['withCandidate']['cmdExecutorConfig']['command'],
                    'args': switchover['withCandidate']['cmdExecutorConfig']['args']
                },
            }
            if 'env' in switchover['withCandidate']['cmdExecutorConfig']:
                result['withCandidate']['env'] = switchover['withCandidate']['cmdExecutorConfig']['env']

        if switchover.get('withoutCandidate') and switchover['withoutCandidate'].get('cmdExecutorConfig'):
            result['withoutCandidate'] = {
                'image': switchover['withoutCandidate']['cmdExecutorConfig']['image'],
                'exec': {
                    'command': switchover['withoutCandidate']['cmdExecutorConfig']['command'],
                    'args': switchover['withoutCandidate']['cmdExecutorConfig']['args']
                },
            }
            if 'env' in switchover['withoutCandidate']['cmdExecutorConfig']:
                result['withoutCandidate']['env'] = switchover['withoutCandidate']['cmdExecutorConfig']['env']

        return result

    def _get_builtin_action_handler(self):
        if self.cluster_comp_def is None or not self.cluster_comp_def.get('characterType'):
            return UNKNOWN_BUILTIN_ACTION_HANDLER

        character_type = self.cluster_comp_def['characterType']
        workload_type = self.cluster_comp_def.get('workloadType', None)

        if character_type == 'mysql':
            if workload_type == WORKLOAD_CONSENSUS:
                return 'wesql'
            else:
                return 'mysql'
        elif character_type == 'postgresql':
            if workload_type == WORKLOAD_CONSENSUS:
                return 'apecloud-postgresql'
            else:
                return 'postgresql'
        elif character_type == 'redis':
            return 'redis'
        elif character_type == 'mongodb':
            return 'mongodb'
        elif character_type == 'etcd':
            return 'etcd'
        elif character_type == 'polardbx':
            return 'polardbx'
        else:
            return UNKNOWN_BUILTIN_ACTION_HANDLER

    @staticmethod
    def _override_switchover_spec_attr(switchover_spec, cv_switchover_spec):
        if switchover_spec is None or cv_switchover_spec is None or cv_switchover_spec.get('cmdExecutorConfig') is None:
            return

        def apply_cmd_executor_config(cmd_executor_config, cv_cmd_executor_config):
            if cmd_executor_config is None:
                return
            if cv_cmd_executor_config.get('image', ''):  # Check if 'Image' key exists and is not empty
                cmd_executor_config['image'] = cv_cmd_executor_config['image']
            if cv_cmd_executor_config.get('env', []):  # Check if 'Env' key exists and is not empty
                cmd_executor_config['env'] = cv_cmd_executor_config['env']

        # Apply configuration to 'WithCandidate' if exists
        if switchover_spec.get('withCandidate') and switchover_spec['withCandidate'].get('cmdExecutorConfig'):
            apply_cmd_executor_config(switchover_spec['withCandidate']['cmdExecutorConfig'],
                                      cv_switchover_spec['cmdExecutorConfig'])

        # Apply configuration to 'WithoutCandidate' if exists
        if switchover_spec.get('withoutCandidate') and switchover_spec['withoutCandidate'].get('cmdExecutorConfig'):
            apply_cmd_executor_config(switchover_spec['withoutCandidate']['cmdExecutorConfig'],
                                      cv_switchover_spec['cmdExecutorConfig'])
        return switchover_spec

    def _append_or_override_container_attr(self, comp_ver_containers, target_container):
        def get_container_by_name(containers, name):
            for i, container in enumerate(containers):
                if container['name'] == name:
                    return i, container
            return -1, None

        index, comp_ver_container = get_container_by_name(comp_ver_containers, target_container['name'])
        if comp_ver_container is None:
            comp_ver_containers.append(target_container)
        else:
            comp_ver_containers[index] = self._do_container_attr_override(comp_ver_container, target_container)

        return comp_ver_containers

    @staticmethod
    def _do_container_attr_override(comp_container, container):
        keys_to_copy = [
            "image", "command", "args", "workingDir", "ports", "envFrom",
            "env", "resources", "volumeMounts", "volumeDevices" "livenessProbe",
            "readinessProbe", "startupProbe", "lifecycle", "securityContext",
            "terminationMessagePath", "TerminationMessagePolicy", "imagePullPolicy",
        ]

        for key in keys_to_copy:
            if key in container and container[key]:
                comp_container[key] = container[key]

        return comp_container

    def _convert_host_network_vars(self):
        host_network = self._convert_host_network()
        if not host_network or not host_network.container_ports:
            return []

        host_net_work_vars = []
        for cc in host_network.container_ports:
            for port in cc.ports:
                var_name = self._host_network_dynamic_port_var_name(cc.container, port)
                var_value = {
                    'name': var_name,
                    'valueFrom': {
                        'podVarRef': {
                            'optional': False,
                            'container': cc.container,
                            'port': {'name': port, 'option': 'required'}
                        }
                    }
                }
                host_net_work_vars.append(var_value)
        return host_net_work_vars

    def _convert_host_network(self):
        host_network = HostNetwork(container_ports=[])
        if self.cluster_comp_def.get('podSpec') is None or not self.cluster_comp_def['podSpec'].get('hostNetwork'):
            return host_network

        host_network = HostNetwork(container_ports=[])
        containers = self.cluster_comp_def['podSpec']['containers']
        for container in containers:
            cp = HostNetworkContainerPort(container=container['name'], ports=[])
            for port in container['ports']:
                if self._is_host_network_dynamic_port(port['containerPort']):
                    cp.ports.append(port.name)
            if cp.ports:
                host_network.container_ports.append(cp)
        return host_network

    @staticmethod
    def _is_host_network_dynamic_port(port):
        return port <= HOST_NETWORK_DYNAMIC_PORT_THRESHOLD

    @staticmethod
    def _host_network_dynamic_port_var_name(container, port):
        container_name = container.replace("-", "_").upper()
        port_name = port.upper()
        return f"KB_HOSTNETWORK_{container_name}_{port_name}"

    def _role_selector(self):
        if self.cluster_comp_def.get('rsmSpec') and self.cluster_comp_def['rsmSpec'].get('roles'):
            for role in self.cluster_comp_def['rsmSpec']['roles']:
                if role['accessMode'] == READ_WRITE_MODE:
                    return role['name']

        # Convert the leader name with respect to workload type
        workload_type = self.cluster_comp_def.get('workloadType')
        if workload_type == WORKLOAD_CONSENSUS:
            if not self.cluster_comp_def.get('consensusSpec'):
                return LEADER
            return self.cluster_comp_def['consensusSpec']['leader']['name']
        elif workload_type == WORKLOAD_REPLICATION:
            return PRIMARY
        return ""

    @staticmethod
    def _merge_config_templates(cv_config_specs, cd_config_specs):
        if not cv_config_specs:
            return cd_config_specs

        if not cd_config_specs:
            return cv_config_specs

        merged_cfg_tpl = []
        merged_tpl_map = {}

        for config_spec in cv_config_specs:
            tpl_name = config_spec['name']
            if tpl_name in merged_tpl_map:
                continue
            merged_cfg_tpl.append(config_spec)
            merged_tpl_map[tpl_name] = True

        for config_spec in cd_config_specs:
            tpl_name = config_spec['name']
            if tpl_name in merged_tpl_map:
                continue
            merged_cfg_tpl.append(config_spec)
            merged_tpl_map[tpl_name] = True

        return merged_cfg_tpl

    def _convert_roles(self):
        if 'rsmSpec' in self.cluster_comp_def and self.cluster_comp_def['rsmSpec'] is not None:
            return self._convert_instance_set_role()

        workload_type = self.cluster_comp_def.get('workloadType')
        if workload_type == 'Consensus':
            return self._convert_consensus_role()
        elif workload_type == 'Replication':
            default_roles = [
                ReplicaRole('Primary', True, True, True),
                ReplicaRole('Secondary', True, False, True)
            ]
            return default_roles
        elif workload_type in ['Stateful', 'Stateless']:
            return None
        else:
            raise ValueError(f"unknown workload type: {workload_type}")

    def _convert_instance_set_role(self):
        rsm_spec = self.cluster_comp_def.get('rsmSpec')
        if rsm_spec is None:
            return None

        roles = [ReplicaRole(role['name'], role['accessMode'] != 'None',
                             role['accessMode'] == 'ReadWrite', role['canVote']) for role in rsm_spec['roles']]
        return roles

    def _convert_consensus_role(self):
        consensus_spec = self.cluster_comp_def.get('consensusSpec')
        if consensus_spec is None:
            return None

        roles = [ReplicaRole(consensus_spec['leader']['name'],
                             consensus_spec['leader']['access_mode'] != 'None',
                             consensus_spec['leader']['access_mode'] == 'ReadWrite',
                             True)]
        for follower in consensus_spec['followers']:
            roles.append(ReplicaRole(follower['name'],
                                     follower['accessMode'] != 'None', follower['accessMode'] == 'ReadWrite', True))
        if 'learner' in consensus_spec and consensus_spec['learner'] is not None:
            roles.append(ReplicaRole(consensus_spec['learner']['name'],
                                     consensus_spec['learner']['accessMode'] != 'None',
                                     consensus_spec['learner']['accessMode'] == 'ReadWrite',
                                     False))
        return roles


def main():
    parser = argparse.ArgumentParser(description='Convert ClusterDefinition to ComponentDefinition')
    parser.add_argument('--cluster-definition', required=True, help='Path to the ClusterDefinition YAML file')
    parser.add_argument('--cluster-version', required=True, help='Path to the ClusterVersion YAML file')
    parser.add_argument('--output-dir', default='.',
                        help='Output directory for the generated ComponentDefinition YAML files')
    parser.add_argument('--overwrite', default=True, type=bool,
                        help='Whether to overwrite existing ComponentDefinition YAML files (default: True)')
    parser.add_argument('--use-helm-template-render-first', default=True, type=bool,
                        help='Whether to use Helm template to render the YAML files before conversion (default: True)')
    parser.add_argument('--chart-path', required=True, help='Path to the Helm chart directory')
    args = parser.parse_args()

    rendered_cluster_def_path = 'rendered_cluster_definition.yaml'
    rendered_cluster_ver_path = 'rendered_cluster_version.yaml'

    if args.use_helm_template_render_first:
        if not args.chart_path:
            raise Exception("Chart path is required when using Helm template rendering")

        # Render ClusterDefinition using Helm template
        HelmTemplateRenderer.render_helm_template(args.chart_path,
                                                  rendered_cluster_def_path, 'templates/' + args.cluster_definition)

        # Render ClusterVersion using Helm template
        HelmTemplateRenderer.render_helm_template(args.chart_path,
                                                  rendered_cluster_ver_path, 'templates/' + args.cluster_version)

        # Keep only the first ClusterVersion object in the rendered file
        HelmTemplateRenderer.keep_first_cluster_version(rendered_cluster_ver_path)

        cluster_def_path = rendered_cluster_def_path
        cluster_ver_path = rendered_cluster_ver_path
    else:
        cluster_def_path = args.cluster_definition
        cluster_ver_path = args.cluster_version

    with open(cluster_def_path, 'r') as file:
        cluster_def = yaml.safe_load(file)

    with open(cluster_ver_path, 'r') as file:
        cluster_ver = yaml.safe_load(file)

    converter = ClusterDefinitionConvertor(cluster_def, cluster_ver)
    component_defs = converter.convert()

    os.makedirs(args.output_dir, exist_ok=True)

    for comp_def in component_defs:
        base_file_name = COMPONENT_DEFINITION_YAML_FILE_PREFIX + comp_def['metadata']['name'] + '.yaml'
        file_path = os.path.join(args.output_dir, base_file_name)

        if args.overwrite:
            with open(file_path, 'w') as file:
                yaml.dump(comp_def, file)
            print(f"Generated ComponentDefinition YAML: {file_path}")
        else:
            timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
            unique_file_name = COMPONENT_DEFINITION_YAML_FILE_PREFIX + comp_def['metadata']['name'] + f'-{timestamp}.yaml'
            unique_file_path = os.path.join(args.output_dir, unique_file_name)
            with open(unique_file_path, 'w') as file:
                yaml.dump(comp_def, file)
            print(f"Generated ComponentDefinition YAML with unique timestamp: {unique_file_path}")

    HelmTemplateRenderer.delete_temp_files([rendered_cluster_def_path, rendered_cluster_ver_path])


if __name__ == "__main__":
    """
    Running Conditions:
        1. Python 3.X environment with relevant dependency packages installed.
        2. Helm should be installed locally.
    
    Usage:
        python convert_clusterdefinition_to_componentdefinitions.py --chart-path=/PathToYourProject/kubeblocks-addons/addons/postgresql \
        --cluster-definition=clusterdefinition.yaml --cluster-version=clusterversion.yaml --output-dir=./
        
        --chart-path: Path to the Helm chart directory
        --cluster-definition: The name of cluster definition file, e.g., clusterdefinition.yaml
        --cluster-version: The name of cluster version file, e.g., clusterversion.yaml
        --output-dir: Output directory for the generated ComponentDefinition YAML files
    """
    main()
