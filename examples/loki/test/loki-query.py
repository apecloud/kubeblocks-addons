import requests
import time

# Configuration
LOKI_URL = "http://localhost:8080"  # Update with your Loki URL
QUERY = '{job="performance_test"}'  # Your Loki query
LIMIT = 100  # Maximum number of results to return

def query_loki():
    """Query data from Loki and return the results."""
    query_params = {
        "query": QUERY,
        "limit": LIMIT
    }

    try:
        response = requests.get(
            f"{LOKI_URL}/loki/api/v1/query",
            params=query_params
        )
        response.raise_for_status()  # Raise an exception for HTTP errors
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error querying Loki: {e}")
        return None

def process_results(results):
    """Process and print the query results."""
    if not results:
        return

    data = results.get("data", {})
    results = data.get("result", [])

    print(f"Found {len(results)} log streams:")
    for stream in results:
        stream_labels = stream.get("stream", {})
        values = stream.get("values", [])

        print(f"\nStream labels: {stream_labels}")
        print(f"Number of log entries: {len(values)}")

        # Print the first 5 log entries
        for value in values:
            timestamp = int(value[0])
            log_line = value[1]
            print(f"{time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(timestamp/1e9))} - {log_line}")

if __name__ == "__main__":
    print("Querying Loki...")
    results = query_loki()
    process_results(results)