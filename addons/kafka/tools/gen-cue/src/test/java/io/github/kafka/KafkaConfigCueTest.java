package io.kubeblocks.kafka;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.server.config.AbstractKafkaConfig;
import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertEquals;
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
    void rendersDisabledConfigAsCommentedField() {
        ConfigDef def = new ConfigDef()
            .define("enabled.string", ConfigDef.Type.STRING, "x", ConfigDef.Importance.MEDIUM, "Enabled")
            .define("disabled.string", ConfigDef.Type.STRING, "y", ConfigDef.Importance.MEDIUM, "Disabled");

        String cue = KafkaConfigCue.renderForTest("Test", def, Set.of("disabled.string"));

        assertTrue(cue.contains("\"enabled.string\"?: *\"x\" | string"));
        assertTrue(cue.contains("// \"disabled.string\"?: *\"y\" | string"));
    }

    @Test
    void rendersScopedSchemas() {
        ConfigDef shared = new ConfigDef()
            .define("shared.string", ConfigDef.Type.STRING, "shared", ConfigDef.Importance.HIGH, "Shared");
        ConfigDef controller = new ConfigDef()
            .define("controller.string", ConfigDef.Type.STRING, "controller", ConfigDef.Importance.HIGH, "Controller");
        ConfigDef broker = new ConfigDef()
            .define("broker.string", ConfigDef.Type.STRING, "broker", ConfigDef.Importance.HIGH, "Broker");

        String cue = KafkaConfigCue.renderScopedDefinitionsForTest(shared, controller, broker);

        assertTrue(cue.contains("#Shared: {"));
        assertTrue(cue.contains("#Controller: #Shared & {"));
        assertTrue(cue.contains("#Broker: #Shared & {"));
        assertTrue(cue.contains("#Combined: #Controller & #Broker"));
        assertTrue(section(cue, "#Shared:", "#Controller:").contains("\"shared.string\""));
        assertTrue(section(cue, "#Controller:", "#Broker:").contains("\"controller.string\""));
        assertTrue(section(cue, "#Broker:", "#Combined:").contains("\"broker.string\""));
        assertTrue(section(cue, "#Controller:", "#Broker:").contains("\t...\n"));
        assertTrue(section(cue, "#Broker:", "#Combined:").contains("\t...\n"));
    }

    @Test
    void rendersRealKafkaSources() {
        String cue = KafkaConfigCue.render();

        assertFalse(cue.contains("#Topic"));
        assertFalse(cue.contains("#KafkaParameter"));
        assertFalse(cue.contains("#Combimed"));
        assertTrue(cue.contains("#Shared"));
        assertTrue(cue.contains("#Controller"));
        assertTrue(cue.contains("#Broker"));
        assertTrue(cue.contains("#Combined: #Controller & #Broker"));
        assertTrue(section(cue, "#Shared:", "#Controller:").contains("\"num.network.threads\""));
        assertTrue(section(cue, "#Controller:", "#Broker:").contains("\"controller.quorum.voters\""));
        assertTrue(section(cue, "#Controller:", "#Broker:").contains("\"metadata.log.dir\""));
        assertTrue(section(cue, "#Controller:", "#Broker:").contains("\"delete.topic.enable\""));
        assertTrue(section(cue, "#Broker:", "#Combined:").contains("\"log.retention.ms\""));
        assertTrue(section(cue, "#Broker:", "#Combined:").contains("\"group.initial.rebalance.delay.ms\""));
        assertFalse(section(cue, "#Broker:", "#Combined:").contains("\"delete.topic.enable\""));
        assertTrue(cue.contains("// \"advertised.listeners\"?: *null | string | null"));
        assertTrue(cue.contains("// \"process.roles\"?: *[] | [...(\"broker\" | \"controller\")]"));
        assertTrue(cue.contains("// \"ssl.keystore.type\"?: *\"JKS\" | string"));
        assertEquals(nonInternalKafkaConfigNames(), renderedConfigNames(cue));
    }

    private static String section(String text, String start, String end) {
        int startIndex = text.indexOf(start);
        int endIndex = text.indexOf(end, startIndex + start.length());
        assertTrue(startIndex >= 0, "missing start marker: " + start);
        assertTrue(endIndex >= 0, "missing end marker: " + end);
        return text.substring(startIndex, endIndex);
    }

    private static Set<String> renderedConfigNames(String cue) {
        Pattern fieldPattern = Pattern.compile("(?m)^\\s*(?://\\s*)?\"([^\"]+)\"\\??\\s*:");
        Matcher matcher = fieldPattern.matcher(cue);
        Set<String> names = new HashSet<>();
        while (matcher.find()) {
            names.add(matcher.group(1));
        }
        return names;
    }

    private static Set<String> nonInternalKafkaConfigNames() {
        Set<String> names = new HashSet<>();
        for (ConfigDef.ConfigKey key : AbstractKafkaConfig.CONFIG_DEF.configKeys().values()) {
            if (!key.internalConfig) {
                names.add(key.name);
            }
        }
        return names;
    }
}
