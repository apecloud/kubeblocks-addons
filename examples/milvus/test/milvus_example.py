import argparse
import random
import time
import os
import sys
import warnings

"""
Milvus Example Script
--------------------
This script demonstrates basic and advanced features of Milvus, including:
- Collection creation with scalar and vector fields
- Data insertion and indexing
- Vector search with scalar filtering
- Scalar querying and upserting

Requirements:
    pip install -r requirements.txt

If you see Protobuf version warnings, you can suppress them by setting:
    export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
or by downgrading protobuf:
    pip install "protobuf>=5.27.2,<6.0.0"
"""

# Suppress the known Protobuf version mismatch warning if it occurs
# This is a common issue where pymilvus gencode (5.x) is one version older than protobuf runtime (6.x)
os.environ.setdefault("PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION", "python")

try:
    import numpy as np
except ImportError:
    print("❌ Error: numpy is required but not installed.")
    print("Please install it with: pip install numpy")
    sys.exit(1)

try:
    from pymilvus import (
        connections,
        utility,
        FieldSchema,
        CollectionSchema,
        DataType,
        Collection,
    )
except ImportError:
    print("❌ Error: pymilvus is required but not installed.")
    print("Please install it with: pip install pymilvus")
    sys.exit(1)

def check_dependencies():
    """Check if required dependencies are installed and versions are compatible"""
    print("🔍 Checking dependencies...")

    # Check numpy
    try:
        import numpy as np
        print(f"✅ numpy: {np.__version__}")
    except ImportError:
        print("❌ Error: numpy is required")
        return False

    # Check pymilvus
    try:
        import pymilvus
        print(f"✅ pymilvus: {pymilvus.__version__}")
    except ImportError:
        print("❌ Error: pymilvus is required")
        return False

    # Check protobuf version if possible
    try:
        import google.protobuf
        print(f"✅ protobuf: {google.protobuf.__version__}")
    except ImportError:
        pass

    return True

# 1. Connect to Milvus
def connect_to_milvus(host, port):
    print(f"\n--- Step 1: Connecting to Milvus at {host}:{port} ---")
    connections.connect("default", host=host, port=port)
    print("Connected successfully.")

# 2. Create Collection
def create_collection(collection_name, dim):
    print(f"\n--- Step 2: Creating collection '{collection_name}' ---")
    if utility.has_collection(collection_name):
        print(f"Collection '{collection_name}' already exists. Dropping it...")
        utility.drop_collection(collection_name)

    fields = [
        FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
        FieldSchema(name="count", dtype=DataType.INT64),
        FieldSchema(name="description", dtype=DataType.VARCHAR, max_length=500),
        FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=dim)
    ]

    schema = CollectionSchema(fields, "Example Milvus collection for testing")
    collection = Collection(collection_name, schema)
    print(f"Collection '{collection_name}' created with schema:")
    for field in fields:
        print(f" - {field.name}: {field.dtype}")
    return collection

# 3. Insert data
def insert_data(collection, num_entities, dim, batch_size=500):
    print(f"\n--- Step 3: Inserting {num_entities} entities in batches of {batch_size} ---")

    total_inserted = 0
    all_pks = []

    for i in range(0, num_entities, batch_size):
        end = min(i + batch_size, num_entities)
        current_batch_size = end - i

        # 1. count field
        counts = [j for j in range(i, end)]
        # 2. description field
        descriptions = [f"entity_{j}" for j in range(i, end)]
        # 3. embedding field
        embeddings = np.random.random((current_batch_size, dim)).tolist()

        data = [counts, descriptions, embeddings]

        try:
            mr = collection.insert(data)
            all_pks.extend(mr.primary_keys)
            total_inserted += mr.insert_count
            print(f" - Inserted batch {i//batch_size + 1}: {mr.insert_count} entities (Total: {total_inserted}/{num_entities})")
        except Exception as e:
            print(f"❌ Error during batch insertion at index {i}: {e}")
            raise e

    print(f"Successfully inserted {total_inserted} entities.")
    return all_pks

# 4. Create Index
def create_index(collection, field_name):
    print(f"\n--- Step 4: Creating index on field '{field_name}' ---")
    index_params = {
        "index_type": "IVF_FLAT",
        "metric_type": "L2",
        "params": {"nlist": 128}
    }
    collection.create_index(field_name, index_params)
    print(f"Index created on field '{field_name}'.")

# 5. Load Collection
def load_collection(collection):
    print("\n--- Step 5: Loading collection into memory ---")
    collection.load()
    print("Collection loaded.")

# 6. Search (Vector search with scalar filtering)
def search_with_filtering(collection, dim):
    print("\n--- Step 6: Vector search with scalar filtering ---")
    search_params = {
        "metric_type": "L2",
        "params": {"nprobe": 10}
    }

    # Generate a random query vector
    query_vectors = np.random.random((1, dim)).tolist()

    # Search for top 5 entities where count > 500
    expr = "count > 500"
    print(f"Searching for entities where {expr}...")

    start_time = time.time()
    results = collection.search(
        data=query_vectors,
        anns_field="embedding",
        param=search_params,
        limit=5,
        expr=expr,
        output_fields=["count", "description"]
    )
    end_time = time.time()

    print(f"Search completed in {end_time - start_time:.4f} seconds.")
    for hits in results:
        for hit in hits:
            print(f" - Hit: {hit.id}, Distance: {hit.distance:.4f}, Count: {hit.entity.get('count')}, Description: {hit.entity.get('description')}")

# 7. Query (Scalar query)
def scalar_query(collection):
    print("\n--- Step 7: Scalar query ---")
    expr = "count in [1, 2, 3]"
    print(f"Querying for entities where {expr}...")

    results = collection.query(
        expr=expr,
        output_fields=["id", "count", "description"]
    )

    for result in results:
        print(f" - Result: {result}")

# 8. Upsert (Update or Insert)
def upsert_data(collection, dim):
    print("\n--- Step 8: Upserting data ---")
    # Query for an existing ID
    res = collection.query(expr="count == 10", output_fields=["id"])
    if not res:
        print("Entity with count == 10 not found, skipping upsert example.")
        return

    target_id = res[0]["id"]
    print(f"Upserting entity with id {target_id}...")

    # New data for the existing ID
    new_counts = [10]
    new_descriptions = ["updated_entity_10"]
    new_embeddings = np.random.random((1, dim)).tolist()

    # Upsert requires primary keys if they are not auto-generated,
    # but since auto_id=True, we might need to handle it differently depending on Milvus version.
    # In many versions, upsert on auto_id collections might not be directly supported without providing the ID.
    try:
        data = [[target_id], new_counts, new_descriptions, new_embeddings]
        collection.upsert(data)
        print(f"Successfully upserted entity {target_id}.")
    except Exception as e:
        print(f"Upsert failed (this might be expected on some Milvus versions with auto_id=True): {e}")

# 9. Drop Collection
def drop_collection(collection_name):
    print(f"\n--- Step 9: Dropping collection '{collection_name}' ---")
    utility.drop_collection(collection_name)
    print("Collection dropped.")

def main():
    parser = argparse.ArgumentParser(description="Milvus Example Script")
    parser.add_argument("--host", default="localhost", help="Milvus host (default: localhost)")
    parser.add_argument("--port", default="19530", help="Milvus port (default: 19530)")
    parser.add_argument("--collection", default="test_collection", help="Collection name")
    parser.add_argument("--dim", type=int, default=128, help="Vector dimension")
    parser.add_argument("--num", type=int, default=1000, help="Number of entities to insert")
    parser.add_argument("--batch-size", type=int, default=500, help="Batch size for insertion (to avoid message size limits)")
    parser.add_argument("--no-cleanup", action="store_true", help="Do not drop collection after test")
    parser.add_argument("--skip-deps", action="store_true", help="Skip dependency check")

    args = parser.parse_args()

    if not args.skip_deps:
        if not check_dependencies():
            sys.exit(1)

    try:
        connect_to_milvus(args.host, args.port)

        collection = create_collection(args.collection, args.dim)

        insert_data(collection, args.num, args.dim, args.batch_size)

        create_index(collection, "embedding")

        load_collection(collection)

        search_with_filtering(collection, args.dim)

        scalar_query(collection)

        upsert_data(collection, args.dim)

        print("\nAll tests completed successfully!")

    except Exception as e:
        print(f"\n❌ Test failed with an error: {e}")
        if "Message size too large" in str(e):
            print("\n💡 Tip: This error usually occurs when the insertion batch size is too large for the Milvus broker.")
            print(f"Try reducing the batch size with: python milvus_example.py --batch-size 200")

        import traceback
        # Only show full traceback if needed, otherwise keep it clean
        # traceback.print_exc()
    finally:
        if not args.no_cleanup:
            drop_collection(args.collection)
        else:
            print(f"\nSkipping cleanup. Collection '{args.collection}' remains.")

if __name__ == "__main__":
    main()
