package io.kubeblocks.kafka;

import org.apache.kafka.common.config.ConfigDef;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;

class KafkaConfigCueTest {
    @Test
    void rendersDefaultsTypesRangesAndEnums() {
        ConfigDef def = new ConfigDef()
            .define("required.string", ConfigDef.Type.STRING, ConfigDef.Importance.HIGH, "Required value")
            .define("optional.int", ConfigDef.Type.INT, 3, ConfigDef.Range.atLeast(1), ConfigDef.Importance.MEDIUM, "Integer value")
            .define("optional.long", ConfigDef.Type.LONG, 4L, ConfigDef.Importance.MEDIUM, "Long value")
            .define("optional.short", ConfigDef.Type.SHORT, (short) 5, ConfigDef.Importance.MEDIUM, "Short value")
            .define("enum.string", ConfigDef.Type.STRING, "a", ConfigDef.ValidString.in("a", "b"), ConfigDef.Importance.LOW, "Enum value")
            .define("enum.list", ConfigDef.Type.LIST, "a,b", ConfigDef.ValidList.in("a", "b"), ConfigDef.Importance.LOW, "List value");

        String cue = KafkaConfigCue.renderForTest("Test", def);

        assertTrue(cue.contains("\"required.string\": string"));
        assertTrue(cue.contains("\"optional.int\"?: *3 | int & >=-2147483648 & <=2147483647 & >=1"));
        assertTrue(cue.contains("\"optional.long\"?: *4 | int & >=-9223372036854775808 & <=9223372036854775807"));
        assertTrue(cue.contains("\"optional.short\"?: *5 | int & >=-32768 & <=32767"));
        assertTrue(cue.contains("\"enum.string\"?: *\"a\" | string & (\"a\" | \"b\")"));
        assertTrue(cue.contains("\"enum.list\"?: *[\"a\", \"b\"] | [...(\"a\" | \"b\")]"));
    }

    @Test
    void rendersRealKafkaSources() {
        String cue = KafkaConfigCue.render(List.of("producer", "consumer", "admin", "streams", "topic", "broker"));

        assertTrue(cue.contains("#Producer"));
        assertTrue(cue.contains("\"bootstrap.servers\""));
        assertTrue(cue.contains("\"retention.ms\""));
        assertTrue(cue.contains("\"application.id\""));
        assertTrue(cue.contains("\"num.network.threads\""));
    }
}
