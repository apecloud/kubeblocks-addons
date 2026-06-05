import os

from pymilvus import MilvusClient

uri = "http://localhost:19530"

def can_auth(username: str, password: str) -> bool:
    try:
        client = MilvusClient(uri=uri, token=f"{username}:{password}")
        client.list_users()
        return True
    except Exception:
        return False

def main():
    username = "root"
    new_password = os.environ["MILVUS_ROOT_PASSWORD"]
    old_password = "Milvus"
    if can_auth(username, new_password):
        print(f"password for root is already in sync")
        return

    client = MilvusClient(uri=uri, token=f"{username}:{old_password}")
    client.update_password(
        user_name=username,
        old_password=old_password,
        new_password=new_password,
    )
    if not can_auth(username, new_password):
        raise RuntimeError("password update completed but verification failed")
    print(f"updated password for user {username}")

if __name__ == "__main__":
    main()