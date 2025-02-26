from pymilvus import connections, FieldSchema, CollectionSchema, Collection,utility
from pymilvus.orm.types import DataType

## Step 1: Connect to Milvus
connections.connect(
alias="default",
host="localhost", # Replace with your Milvus host
port="19530" # Replace with your Milvus port
)

## Step 2: Define the Collection Schema
fields = [
FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True), # Primary key field
FieldSchema(name="vector", dtype=DataType.FLOAT_VECTOR, dim=128) # Vector field
]
schema = CollectionSchema(fields=fields, description="Example collection")

## Step 3: Create the Collection
collection_name = "example_collection"
collection = Collection(name=collection_name, schema=schema)
print(f"Collection '{collection_name}' created successfully!")


## Step 4: List all collections
collections = utility.list_collections()
print("Existing collections:", collections)

## Step 5: Disconnect when done
connections.disconnect(alias="default")