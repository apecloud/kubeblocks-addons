package io.kubeblocks.kafka;

import org.apache.kafka.common.config.ConfigDef;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
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
        assertTrue(cue.contains("\"optional.int\"?: *3 | int & >=1 & <=2147483647"));
        assertTrue(cue.contains("\"optional.long\"?: *4 | int & >=-9223372036854775808 & <=9223372036854775807"));
        assertTrue(cue.contains("\"optional.short\"?: *5 | int & >=-32768 & <=32767"));
        assertTrue(cue.contains("\"enum.string\"?: *\"a\" | string & (\"a\" | \"b\")"));
        assertTrue(cue.contains("\"enum.list\"?: *[\"a\", \"b\"] | [...(\"a\" | \"b\")]"));
    }

    @Test
    void rendersValidatorCommentOnlyWhenConstraintDoesNotRepresentIt() {
        ConfigDef.Validator customValidator = new ConfigDef.Validator() {
            @Override
            public void ensureValid(String name, Object value) {
            }

            @Override
            public String toString() {
                return "custom-validator";
            }
        };
        ConfigDef def = new ConfigDef()
            .define("bounded.int", ConfigDef.Type.INT, 3, ConfigDef.Range.atLeast(1), ConfigDef.Importance.MEDIUM, "Bounded")
            .define("enum.string", ConfigDef.Type.STRING, "a", ConfigDef.ValidString.in("a", "b"), ConfigDef.Importance.LOW, "Enum")
            .define("custom.string", ConfigDef.Type.STRING, "x", customValidator, ConfigDef.Importance.LOW, "Custom");

        String cue = KafkaConfigCue.renderForTest("Test", def);

        assertFalse(cue.contains("// validator: [1,...]"));
        assertFalse(cue.contains("// validator: [a,b]"));
        assertTrue(cue.contains("// validator: custom-validator"));
    }

    @Test
    void rendersRealKafkaSources() {
        String cue = KafkaConfigCue.render();

        assertTrue(cue.contains("#Topic"));
        assertTrue(cue.contains("#Broker"));
        assertTrue(cue.contains("\"retention.ms\""));
        assertTrue(cue.contains("\"num.network.threads\""));
    }
}
