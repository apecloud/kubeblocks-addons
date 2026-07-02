# kafka-config-cue

Standalone CLI that reads public Kafka `ConfigDef` providers and emits CUE
constraint schemas.

## Usage

```bash
mvn test
mvn compile exec:java -Dexec.args="--output kafka_config_schema.cue"
```

Pick a Kafka version with:

```bash
mvn -Dkafka.version=3.9.0 compile exec:java -Dexec.args="--include broker,topic,group --output kafka_config_schema.cue"
```

The first version intentionally ignores Kafka configs that require private
methods or reflection, such as Connect worker `DistributedConfig`.
