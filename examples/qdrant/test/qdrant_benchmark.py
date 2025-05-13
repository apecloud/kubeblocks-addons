import time
import random
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct


## > pip install qdrant-client
## > pip install pytest
## > python examples/qdrant/test/qdrant_benchmark.py

class QdrantBenchmark:
    def __init__(self, host="localhost", port=6333):
        self.client = QdrantClient(url=f"http://{host}:{port}")
        self.collection_name = "benchmark_collection"
        self.vector_size = 128  # Use larger vector size for testing
        self.batch_sizes = [10, 100, 1000]  # Test different batch sizes
        self.query_counts = [10, 100, 1000]  # Test different query counts

    def setup_collection(self):
        """Create test collection"""
        if self.client.collection_exists(self.collection_name):
            self.client.delete_collection(self.collection_name)

        self.client.create_collection(
            collection_name=self.collection_name,
            vectors_config=VectorParams(
                size=self.vector_size,
                distance=Distance.COSINE
            ),
        )

    def generate_vectors(self, count):
        """Generate random vector data"""
        return [
            PointStruct(
                id=idx,
                vector=[random.random() for _ in range(self.vector_size)],
                payload={"id": idx}
            )
            for idx in range(count)
        ]

    def benchmark_insert(self, total_points=10000):
        """Test insertion performance"""
        print(f"\n=== Insert Benchmark (Total: {total_points} points) ===")

        for batch_size in self.batch_sizes:
            points = self.generate_vectors(total_points)

            start_time = time.time()
            for i in range(0, total_points, batch_size):
                batch = points[i:i+batch_size]
                self.client.upsert(
                    collection_name=self.collection_name,
                    points=batch,
                    wait=True
                )

            duration = time.time() - start_time
            print(f"Batch size {batch_size}: {total_points/duration:.2f} points/sec")

    def benchmark_search(self, query_count=100):
        """Test search performance"""
        print(f"\n=== Search Benchmark ({query_count} queries) ===")

        # Generate query vectors
        query_vectors = [
            [random.random() for _ in range(self.vector_size)]
            for _ in range(query_count)
        ]

        start_time = time.time()
        for vector in query_vectors:
            self.client.search(
                collection_name=self.collection_name,
                query_vector=vector,
                limit=10
            )

        duration = time.time() - start_time
        print(f"Query performance: {query_count/duration:.2f} queries/sec")

    def run(self):
        """Run all benchmarks"""
        print("Starting Qdrant Benchmark...")
        self.setup_collection()

        self.benchmark_insert()
        self.benchmark_search()

        print("\nBenchmark completed!")

if __name__ == "__main__":
    benchmark = QdrantBenchmark()
    benchmark.run()
