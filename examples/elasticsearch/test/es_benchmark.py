#!/usr/bin/env python3
"""
Elasticsearch Benchmark Tool
```bash
pip install "elasticsearch==8.12.0"
python3 examples/elasticsearch/es_benchmark.py \
  --host 127.0.0.1 \
  --port 9200 \
  --doc-count 5000 \
  --bulk-size 200 \
  --search-count 200
```
"""

import time
import random
import argparse
from elasticsearch import Elasticsearch
from elasticsearch.helpers import bulk

def parse_args():
    parser = argparse.ArgumentParser(description='Elasticsearch Benchmark Tool')
    parser.add_argument('--host', default='localhost', help='Elasticsearch host')
    parser.add_argument('--port', type=int, default=9200, help='Elasticsearch port')
    parser.add_argument('--index', default='benchmark_index', help='Index name for testing')
    parser.add_argument('--doc-count', type=int, default=1000, help='Number of documents to index')
    parser.add_argument('--bulk-size', type=int, default=100, help='Bulk request size')
    parser.add_argument('--search-count', type=int, default=100, help='Number of search operations')
    return parser.parse_args()

def generate_doc(doc_id):
    return {
        'id': doc_id,
        'name': f'Document {doc_id}',
        'value': random.randint(1, 1000),
        'timestamp': int(time.time())
    }

def run_benchmark(args):
    es = Elasticsearch(
        [{'host': args.host, 'port': args.port, 'scheme': 'http'}],
        request_timeout=30,
        api_key=None,
        basic_auth=None,
        headers={
            'Accept': 'application/vnd.elasticsearch+json; compatible-with=8',
            'Content-Type': 'application/vnd.elasticsearch+json; compatible-with=8'
        }
    )

    # Create index
    start = time.time()
    es.options(ignore_status=400).indices.create(index=args.index)
    create_time = time.time() - start

    # Bulk index documents
    docs = (generate_doc(i) for i in range(args.doc_count))
    start = time.time()
    success, _ = bulk(es, docs, index=args.index, chunk_size=args.bulk_size)
    index_time = time.time() - start
    index_rate = args.doc_count / index_time

    # Refresh index
    es.indices.refresh(index=args.index)

    # Search performance
    search_times = []
    for _ in range(args.search_count):
        query = {'query': {'match': {'name': f'Document {random.randint(0, args.doc_count-1)}'}}}
        start = time.time()
        es.search(index=args.index, body=query)
        search_times.append(time.time() - start)

    avg_search_time = sum(search_times) / len(search_times)

    # Print results
    print(f"\nBenchmark Results:")
    print(f"Index creation time: {create_time:.4f}s")
    print(f"Indexed {args.doc_count} docs in {index_time:.4f}s ({index_rate:.2f} docs/s)")
    print(f"Average search time: {avg_search_time:.4f}s")
    print(f"Total operations: {args.doc_count + args.search_count}")

    # Cleanup
    es.indices.delete(index=args.index)

if __name__ == '__main__':
    args = parse_args()
    print(f"Starting Elasticsearch benchmark with settings:")
    print(f"  Host: {args.host}:{args.port}")
    print(f"  Index: {args.index}")
    print(f"  Documents: {args.doc_count}")
    print(f"  Bulk size: {args.bulk_size}")
    print(f"  Search operations: {args.search_count}")

    run_benchmark(args)
