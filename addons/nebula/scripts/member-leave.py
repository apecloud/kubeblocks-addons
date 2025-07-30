#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from nebula3.gclient.net import ConnectionPool
from nebula3.Config import Config
from kubernetes import client, config
import os
import json
import time
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

def init_k8s_client():
    try:
        config.load_incluster_config()  # 集群内部使用
    except:
        config.load_kube_config()       # 集群外部使用
    return client.CoreV1Api()

def update_configmap(cli, data):
    cluster_name = os.getenv("CLUSTER_NAME")
    namespace = os.getenv("CLUSTER_NAMESPACE")

    body = client.V1ConfigMap(
        metadata=client.V1ObjectMeta(name=cluster_name, namespace=namespace),
        data={"member-leave": json.dumps(data)}
    )
    try:
        cli.patch_namespaced_config_map(cluster_name, namespace, body)
        logging.info("成功更新ConfigMap:"+cluster_name)
        return True
    except client.exceptions.ApiException as e:
        logging.error(f"更新ConfigMap失败: {e}")
        return False

def get_member_leave_info(cli,pod_fqdn):
    """获取ConfigMap"""
    try:
        cluster_name = os.getenv("CLUSTER_NAME")
        namespace = os.getenv("CLUSTER_NAMESPACE")
        cm = cli.read_namespaced_config_map(cluster_name, namespace)
        if not cm.data:
            return {}, {}
        member_leave_str = cm.data.get("member-leave", "{}")
        member_leave = json.loads(member_leave_str)
        if not member_leave:
            return {}, {}
        return member_leave, json.loads(member_leave.get(pod_fqdn,"{}"))
    except client.exceptions.ApiException as e:
        if e.status == 404:
            try:
                cli.create_namespaced_config_map(namespace, client.V1ConfigMap(
                    metadata=client.V1ObjectMeta(name=cluster_name), data={}))
            except client.exceptions.ApiException as e:
                logging.error(f"创建ConfigMap失败: {e}")
                return None,None
            return {}, {}
        logging.error(f"获取ConfigMap失败: {e}")
        return None,None

def get_job_info(member_leave_info, space):
    if not member_leave_info:
        return {}
    return member_leave_info.get(space)

def get_spaces(nebula_client):
    stmt = "SHOW SPACES"
    spaces_result = nebula_client.execute(stmt)
    if not spaces_result.is_succeeded():
        logging.error("获取space列表失败:" + spaces_result.error_msg())
        return None
    spaces=[]
    for row in spaces_result.rows():
        if row.values:  # 检查是否有值
            spaces.append(str(row.values[0].get_sVal(),"utf-8"))
    logging.info(f"找到 {len(spaces)} 个space: {spaces}")
    return spaces

def remove_host(nebula_client,host_to_remove):
    drop_host_cmd = f"DROP HOSTS {host_to_remove}"
    drop_result = nebula_client.execute(drop_host_cmd)
    if not drop_result.is_succeeded():
        logging.error(f"删除host失败: {host_to_remove}, Msg: " + drop_result.error_msg())
        if "No hosts" in drop_result.error_msg():
            logging.info("Host不存在，已经被删除")
            return True
        return False
    logging.info(f"成功删除host: {host_to_remove}")
    return True

def balance_leader(nebula_client):
    balance_leader_cmd = "SUBMIT JOB BALANCE LEADER"
    balance_leader_result = nebula_client.execute( balance_leader_cmd)
    if not balance_leader_result.is_succeeded():
        logging.error("平衡leader失败:" + balance_leader_result.error_msg())
    else:
        logging.info("已触发leader平衡")

def remove_host_data(nebula_client,space, host_to_remove):
    balance_cmd = f"USE {space}; SUBMIT JOB BALANCE DATA REMOVE {host_to_remove}"
    balance_result = nebula_client.execute( balance_cmd)
    logging.info(f"提交BALANCE DATA REMOVE命令: {balance_cmd}")
    if not balance_result.is_succeeded():
        logging.error(f"在space {space} 上执行BALANCE DATA REMOVE失败:" + balance_result.error_msg())
        return None
    return balance_result.row_values(0)[0].as_int()

def show_job(nebula_client,space, job_id):
    job_status_cmd = f"use {space};SHOW JOB {job_id}"
    status_result = nebula_client.execute(job_status_cmd)
    if not status_result.is_succeeded():
        logging.error("检查作业状态失败:" + status_result.error_msg())
        return None
    return status_result.row_values(0)[2].as_string()

def host_has_removed(nebula_client, pod_fqdn):
    hosts_result = nebula_client.execute("show hosts")
    if not hosts_result.is_succeeded():
        logging.error("获取hosts失败:" + hosts_result.error_msg())
        return False
    for row in hosts_result.rows():
        if row.values:  # 检查是否有值
            host = str(row.values[0].get_sVal(), "utf-8")
            if host == pod_fqdn:
                return False
    return True

def host_is_none(nebula_client, pod_fqdn):
    hosts_result = nebula_client.execute("show hosts")
    if not hosts_result.is_succeeded():
        logging.error("获取hosts失败:" + hosts_result.error_msg())
        return False
    for row in hosts_result.rows():
        if row.values:  # 检查是否有值
            host = str(row.values[0].get_sVal(), "utf-8")
            if host != pod_fqdn:
                continue
            leader_count = row.values[3].get_iVal()
            leader_distribution = str(row.values[4].get_sVal(),"utf-8")
            partition_distribution = str(row.values[5].get_sVal(),"utf-8")
            return leader_count == 0 and leader_distribution == "No valid partition" and partition_distribution == "No valid partition"

def remove_storage_host(graphd_host, graphd_port, user, password, pod_fqdn,host_to_remove):
    # 配置连接
    config = Config()
    config.max_connection_pool_size = 10
    connection_pool = ConnectionPool()
    nebula_client = None
    try:
        # 初始化连接池
        if not connection_pool.init([(graphd_host, graphd_port)], config):
            logging.error("连接池初始化失败")
            return False

        # 获取连接
        nebula_client = connection_pool.get_session(user, password)
        logging.info(f"成功连接到NebulaGraph: {graphd_host}:{graphd_port}")

        # 1. 获取所有space
        spaces = get_spaces(nebula_client)
        cli = init_k8s_client()
        member_leave, host_member_leave_info = get_member_leave_info(cli,pod_fqdn)

        if host_has_removed(nebula_client, pod_fqdn):
            logging.info(f"Host {pod_fqdn} 已经被删除，跳过处理")
            if pod_fqdn in member_leave:
                del member_leave[pod_fqdn]
                update_configmap(cli, member_leave)
            return True

        # 2. 对每个space执行BALANCE DATA REMOVE
        can_remove_host = True
        for space in spaces:
            logging.info(f"正在处理space: {space}, host: {host_to_remove}")
            time.sleep(1)
            job_info = get_job_info(host_member_leave_info, space)
            job_id = job_info.get("job_id", None)
            job_status = job_info.get("status", None)
            logging.info(f"job_id: {job_id}, job_status: {job_status}")
            if not job_status or job_status == "REMOVED":
                job_id = remove_host_data(nebula_client, space, host_to_remove)
                if not job_id:
                    if host_is_none(nebula_client,pod_fqdn):
                        continue
                    can_remove_host = False
                    continue
                can_remove_host = False
                logging.info(f"已提交BALANCE DATA REMOVE作业, Job ID: {job_id}")
            elif job_status in ["FINISHED"]:
                logging.info(f"作业 {job_id} 完成, 状态: {job_status}")
                continue
            elif job_status in ["FAILED", "STOPPED"]:
                logging.info(f"作业 {job_id} 失败, 状态: {job_status}")
                can_remove_host = False
                recover_job_cmd = f"USE {space}; RECOVER JOB {job_id}"
                try:
                    logging.info(f"正在恢复作业 {job_id}...")
                    nebula_client.execute(recover_job_cmd)
                except Exception as e:
                    logging.error(f"恢复作业 {job_id} 失败: {e}")
            job_status = show_job(nebula_client, space, job_id)
            logging.info(f"job_status: {job_status}")
            if job_status not in ["FINISHED"]:
                can_remove_host = False
            host_member_leave_info[space] = {
                "job_id": job_id,
                "status": job_status,
            }
        member_leave[pod_fqdn] = json.dumps(host_member_leave_info)
        # 3. 删除host
        if can_remove_host:
            if not remove_host(nebula_client, host_to_remove):
                return False
            # 4. 平衡leader
            del member_leave[pod_fqdn]
            update_configmap(cli, member_leave)
            balance_leader(nebula_client)
            return True
        logging.info(member_leave)
        update_configmap(cli, member_leave)
        return False
    except Exception as e:
        logging.error("发生错误:" + str(e))
        return False
    finally:
        if nebula_client is not None:
            nebula_client.release()
        connection_pool.close()

if __name__ == "__main__":
    # 从环境变量获取配置
    graphd_host = os.getenv("GRAPHD_SVC_NAME", "graphd")
    graphd_port = int(os.getenv("GRAPHD_SVC_PORT", "9669"))
    user = os.getenv("NEBULA_ROOT_USER", "root")
    password = os.getenv("NEBULA_ROOT_PASSWORD", "nebula")
    pod_name = os.getenv("KB_LEAVE_MEMBER_POD_NAME", "")
    cluster_domain= os.getenv("CLUSTER_DOMAIN", "cluster.local")
    namespace = os.getenv("CLUSTER_NAMESPACE", "kubeblocks-cloud-ns")
    component_name= os.getenv("COMPONENT_NAME", "")
    pod_fqdn = f"{pod_name}.{component_name}-headless.{namespace}.svc.{cluster_domain}"
    host_to_remove = "\""+pod_fqdn + "\":9779"  # storaged默认端口

    if not host_to_remove:
        logging.error("必须指定要移除的host (通过POD_FQDN环境变量)")
        exit(1)

    success = remove_storage_host(graphd_host, graphd_port, user, password,pod_fqdn, host_to_remove)
    exit(0 if success else 1)
