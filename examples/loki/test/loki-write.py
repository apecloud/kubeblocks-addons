import requests
import time
import random
import string
from concurrent.futures import ThreadPoolExecutor

## NOTE:
## before you start, pls forward svc
## k port-forward svc/lokicluster-gateway 8080:80

# Configuration
LOKI_URL = "http://localhost:8080"  # Update with your Loki URL
WRITE_ENDPOINT = "/loki/api/v1/push"
NUM_CLIENTS = 10  # Number of concurrent clients
NUM_LOGS_PER_CLIENT = 1000  # Number of logs per client
LOGS_BATCH_SIZE = 100  # Number of logs per batch
STREAMS = [
    {"job": "performance_test", "client": f"client_{i}"} for i in range(NUM_CLIENTS)
]

def random_string(length=10):
    """Generate a random string for log content."""
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=length))

def generate_log():
    """Generate a single log entry."""
    return {
        "timestamp": time.time_ns(),
        "line": f"Log message: {random_string()}"
    }

def send_batch(client_id, logs):
    """Send a batch of logs to Loki."""
    streams = [
        {
            "stream": STREAMS[client_id],
            "values": [[str(log["timestamp"]), log["line"]] for log in logs]
        }
    ]
    response = requests.post(
        f"{LOKI_URL}{WRITE_ENDPOINT}",
        json={"streams": streams}
    )
    response.raise_for_status()
    return len(logs)

def write_logs(client_id):
    """Generate and send logs for a single client."""
    logs = []
    total_sent = 0
    start_time = time.time()
    for _ in range(NUM_LOGS_PER_CLIENT):
        logs.append(generate_log())
        if len(logs) >= LOGS_BATCH_SIZE:
            total_sent += send_batch(client_id, logs)
            logs = []
    if logs:
        total_sent += send_batch(client_id, logs)
    return total_sent, time.time() - start_time

def main():
    """Main function to coordinate the performance test."""
    print("Starting Loki performance test...")

    # Start multiple clients
    with ThreadPoolExecutor(max_workers=NUM_CLIENTS) as executor:
        futures = [executor.submit(write_logs, i) for i in range(NUM_CLIENTS)]

    # Collect results
    total_logs = 0
    total_time = 0
    for future in futures:
        sent, duration = future.result()
        total_logs += sent
        total_time = max(total_time, duration)

    # Calculate performance metrics
    throughput = total_logs / total_time
    print(f"Performance Test Results:")
    print(f"Total logs sent: {total_logs}")
    print(f"Total time: {total_time:.2f} seconds")
    print(f"Throughput: {throughput:.2f} logs/second")

if __name__ == "__main__":
    main()