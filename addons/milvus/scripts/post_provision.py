import os

from pymilvus import MilvusClient

TLS_ENABLED = os.environ.get("TLS_ENABLED", "").lower() in ("true", "1", "yes")
TLS_CA_PATH = "/etc/pki/tls/ca.pem"

def _uri():
    if TLS_ENABLED:
        return "https://localhost:19530"
    return "http://localhost:19530"

def _client(token: str) -> MilvusClient:
    kwargs = {"uri": _uri(), "token": token}
    if TLS_ENABLED:
        kwargs["secure"] = True
        kwargs["server_pem_path"] = TLS_CA_PATH
        kwargs["server_name"] = "localhost"
    return MilvusClient(**kwargs)

def can_auth(username: str, password: str) -> bool:
    try:
        client = _client(f"{username}:{password}")
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

    client = _client(f"{username}:{old_password}")
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