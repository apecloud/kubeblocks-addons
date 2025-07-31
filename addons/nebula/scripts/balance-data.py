#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from nebula3.gclient.net import ConnectionPool
from nebula3.Config import Config
import os
import time
import logging

# 在脚本开头添加日志配置
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

def init_connection(graphd_host, graphd_port, user, password):
    """初始化Nebula连接"""
    config = Config()
    connection_pool = ConnectionPool()
    if not connection_pool.init([(graphd_host, graphd_port)], config):
        raise Exception("连接池初始化失败")
    client = connection_pool.get_session(user, password)
    return client, connection_pool

def get_all_spaces(nebula_client):
    stmt = "SHOW SPACES"
    spaces_result = nebula_client.execute(stmt)
    if not spaces_result.is_succeeded():
        logging.error("获取space列表失败:", spaces_result.error_msg())
        return None
    spaces=[]
    for row in spaces_result.rows():
        if row.values:  # 检查是否有值
            spaces.append(str(row.values[0].get_sVal(),"utf-8"))
    logging.info(f"找到 {len(spaces)} 个space: {spaces}")
    return spaces

def balance_data(client, space):
    """执行balance data并返回job id"""
    cmd = f"USE {space}; SUBMIT JOB BALANCE DATA;"
    result = client.execute(cmd)
    if not result.is_succeeded():
        logging.error(f"提交BALANCE DATA失败: {result.error_msg()}")
        return None
    return result.row_values(0)[0].as_int()

def check_job_status(client, space, job_id):
    """检查job状态"""
    cmd = f"USE {space}; SHOW JOB {job_id}"
    result = client.execute(cmd)
    if not result.is_succeeded():
        logging.error(f"检查作业状态失败: {result.error_msg()}")
        return None
    return result.row_values(0)[2].as_string()

def balance_leader(client,space):
    """执行balance leader"""
    result = client.execute(f"use {space}; SUBMIT JOB BALANCE LEADER")
    if not result.is_succeeded():
        logging.error(f"平衡{space} leader失败: {result.error_msg()}")
        return
    logging.info(f"成功执行BALANCE LEADER for space {space}")

def main():
    # 从环境变量获取配置
    graphd_host = os.getenv("GRAPHD_SVC_NAME", "graphd")
    graphd_port = int(os.getenv("GRAPHD_SVC_PORT", "9669"))
    user = os.getenv("NEBULA_ROOT_USER", "root")
    password = os.getenv("NEBULA_ROOT_PASSWORD", "nebula")

    try:
        client, connection_pool = init_connection(graphd_host, graphd_port, user, password)
        spaces = get_all_spaces(client)

        # 1. 对所有space执行balance data
        failed_spaces = {}
        job_statuses = {}
        for space in spaces:
            job_id = balance_data(client, space)
            if not job_id:
                logging.error(f"在space {space} 上提交BALANCE DATA失败")
                failed_spaces[space] = "BALANCE DATA失败"
                continue
            logging.info(f"Space {space} 已提交BALANCE DATA作业, Job ID: {job_id}")
            job_statuses[space] = job_id


        # 2. 等待所有作业完成
        while True:
            all_finished = True
            all_succeed = True
            for space, job_id in job_statuses.items():
                status = check_job_status(client, space, job_id)
                logging.info(f"Space {space} 作业 {job_id} 状态: {status}")
                if status not in ["FINISHED", "FAILED", "STOPPED", "REMOVED"]:
                    all_finished = False
                if status != "FINISHED":
                    all_succeed = False
            if not all_finished:
                time.sleep(5)
            else:
                break

        # 3. 所有balance data完成后执行balance leader
        if all_succeed:
            for space in spaces:
                balance_leader(client,space)
        if not all_succeed or len(failed_spaces) > 0:
            logging.error("有作业未成功完成，请检查日志。")
            return False
        return True

    except Exception as e:
        logging.error(f"执行失败: {str(e)}")
        return False
    finally:
        connection_pool.close()

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
