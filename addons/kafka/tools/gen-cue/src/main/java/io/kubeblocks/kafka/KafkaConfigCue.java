package io.kubeblocks.kafka;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.common.config.internals.BrokerSecurityConfigs;
import org.apache.kafka.coordinator.group.GroupCoordinatorConfig;
import org.apache.kafka.coordinator.transaction.TransactionLogConfigs;
import org.apache.kafka.coordinator.transaction.TransactionStateManagerConfigs;
import org.apache.kafka.network.SocketServerConfigs;
import org.apache.kafka.raft.QuorumConfig;
import org.apache.kafka.security.PasswordEncoderConfigs;
import org.apache.kafka.server.config.DelegationTokenManagerConfigs;
import org.apache.kafka.server.config.AbstractKafkaConfig;
import org.apache.kafka.server.config.KRaftConfigs;
import org.apache.kafka.server.config.QuotaConfigs;
import org.apache.kafka.server.config.ReplicationConfigs;
import org.apache.kafka.server.config.ServerConfigs;
import org.apache.kafka.server.config.ShareGroupConfig;
import org.apache.kafka.server.config.ZkConfigs;
import org.apache.kafka.server.log.remote.storage.RemoteLogManagerConfig;
import org.apache.kafka.server.metrics.MetricConfigs;
import org.apache.kafka.storage.internals.log.CleanerConfig;
import org.apache.kafka.storage.internals.log.LogConfig;

import java.io.IOException;
import java.io.OutputStream;
import java.io.PrintStream;
import java.lang.reflect.Field;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeSet;
import java.util.function.Supplier;

public final class KafkaConfigCue {
    // these configs will be managed by kubeblocks
    private static final Set<String> DISABLED_CONFIGS = Set.of(
            "advertised.listeners",
            "process.roles",
            "ssl.keystore.type",
            "node.id",
            "controller.quorum.bootstrap.servers",
            "controller.quorum.voters",
            "listeners",
            "controller.listener.names",
            "inter.broker.listener.name",
            "listener.security.protocol.map"
        );
    private static final Set<String> SHARED_KRAFT_CONFIGS = Set.of(
            KRaftConfigs.PROCESS_ROLES_CONFIG,
            KRaftConfigs.NODE_ID_CONFIG,
            KRaftConfigs.CONTROLLER_LISTENER_NAMES_CONFIG,
            KRaftConfigs.SASL_MECHANISM_CONTROLLER_PROTOCOL_CONFIG,
            KRaftConfigs.SERVER_MAX_STARTUP_TIME_MS_CONFIG);
    private static final Set<String> BROKER_KRAFT_CONFIGS = Set.of(
            KRaftConfigs.INITIAL_BROKER_REGISTRATION_TIMEOUT_MS_CONFIG,
            KRaftConfigs.BROKER_HEARTBEAT_INTERVAL_MS_CONFIG,
            KRaftConfigs.BROKER_SESSION_TIMEOUT_MS_CONFIG);
    private static final Set<String> CONTROLLER_KRAFT_CONFIGS = Set.of(
            KRaftConfigs.METADATA_LOG_DIR_CONFIG,
            KRaftConfigs.METADATA_SNAPSHOT_MAX_INTERVAL_MS_CONFIG,
            KRaftConfigs.METADATA_SNAPSHOT_MAX_NEW_RECORD_BYTES_CONFIG,
            KRaftConfigs.METADATA_LOG_SEGMENT_MIN_BYTES_CONFIG,
            KRaftConfigs.METADATA_LOG_SEGMENT_BYTES_CONFIG,
            KRaftConfigs.METADATA_LOG_SEGMENT_MILLIS_CONFIG,
            KRaftConfigs.METADATA_MAX_RETENTION_BYTES_CONFIG,
            KRaftConfigs.METADATA_MAX_RETENTION_MILLIS_CONFIG,
            KRaftConfigs.METADATA_MAX_IDLE_INTERVAL_MS_CONFIG,
            KRaftConfigs.MIGRATION_ENABLED_CONFIG,
            KRaftConfigs.MIGRATION_METADATA_MIN_BATCH_SIZE_CONFIG,
            KRaftConfigs.ELR_ENABLED_CONFIG);
    private static final Set<String> CONTROLLER_SERVER_CONFIGS = Set.of(
            "delete.topic.enable");
    private static final List<ScopedConfigSource> SOURCES = List.of(
            new ScopedConfigSource(Scope.BROKER, RemoteLogManagerConfig::configDef),
            new ScopedConfigSource(Scope.BROKER, () -> ZkConfigs.CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> withoutConfigs(ServerConfigs.CONFIG_DEF, CONTROLLER_SERVER_CONFIGS)),
            new ScopedConfigSource(Scope.CONTROLLER, () -> filteredConfigDef(ServerConfigs.CONFIG_DEF, CONTROLLER_SERVER_CONFIGS)),
            new ScopedConfigSource(Scope.SHARED, () -> filteredConfigDef(KRaftConfigs.CONFIG_DEF, SHARED_KRAFT_CONFIGS)),
            new ScopedConfigSource(Scope.BROKER, () -> filteredConfigDef(KRaftConfigs.CONFIG_DEF, BROKER_KRAFT_CONFIGS)),
            new ScopedConfigSource(Scope.CONTROLLER, () -> filteredConfigDef(KRaftConfigs.CONFIG_DEF, CONTROLLER_KRAFT_CONFIGS)),
            new ScopedConfigSource(Scope.SHARED, () -> SocketServerConfigs.CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> ReplicationConfigs.CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> GroupCoordinatorConfig.GROUP_COORDINATOR_CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> GroupCoordinatorConfig.NEW_GROUP_CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> GroupCoordinatorConfig.OFFSET_MANAGEMENT_CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> GroupCoordinatorConfig.CONSUMER_GROUP_CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> GroupCoordinatorConfig.SHARE_GROUP_CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> CleanerConfig.CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> LogConfig.SERVER_CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> ShareGroupConfig.CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> TransactionLogConfigs.CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> TransactionStateManagerConfigs.CONFIG_DEF),
            new ScopedConfigSource(Scope.CONTROLLER, () -> QuorumConfig.CONFIG_DEF),
            new ScopedConfigSource(Scope.SHARED, () -> MetricConfigs.CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> QuotaConfigs.CONFIG_DEF),
            new ScopedConfigSource(Scope.SHARED, () -> BrokerSecurityConfigs.CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> DelegationTokenManagerConfigs.CONFIG_DEF),
            new ScopedConfigSource(Scope.BROKER, () -> PasswordEncoderConfigs.CONFIG_DEF)
            // new ScopedConfigSource(Scope.TOPIC, LogConfig::configDefCopy)
    );

    private KafkaConfigCue() {
    }

    public static void main(String[] args) throws IOException {
        CliOptions options = CliOptions.parse(args);
        String cue = render();

        if (options.output() == null) {
            System.out.print(cue);
        } else {
            Files.writeString(options.output(), cue, StandardCharsets.UTF_8);
        }
    }

    static String render() {
        StringBuilder out = new StringBuilder();
        out.append("package kafka\n\n");
        out.append("// Generated from Kafka ConfigDef metadata, using tools/gen-cue.\n");
        out.append("// Dotted Kafka property names are intentionally kept as flat quoted fields.\n\n");

        Map<Scope, Map<String, ConfigDef.ConfigKey>> keys = collectConfigKeys(SOURCES);
        validateScopedConfigsMatchKafka(keys, AbstractKafkaConfig.CONFIG_DEF);
        renderScopedDefinitions(out, keys, DISABLED_CONFIGS);

        return out.toString();
    }

    static String renderForTest(String definitionName, ConfigDef configDef) {
        StringBuilder out = new StringBuilder();
        renderDefinition(out, definitionName, configDef, Set.of());
        return out.toString();
    }

    static String renderForTest(String definitionName, ConfigDef configDef, Set<String> disabledConfigs) {
        StringBuilder out = new StringBuilder();
        renderDefinition(out, definitionName, configDef, disabledConfigs);
        return out.toString();
    }

    static String renderScopedDefinitionsForTest(ConfigDef shared, ConfigDef controller, ConfigDef broker) {
        List<ScopedConfigSource> sources = List.of(
                new ScopedConfigSource(Scope.SHARED, () -> shared),
                new ScopedConfigSource(Scope.CONTROLLER, () -> controller),
                new ScopedConfigSource(Scope.BROKER, () -> broker));
        StringBuilder out = new StringBuilder();
        renderScopedDefinitions(out, collectConfigKeys(sources), Set.of());
        return out.toString();
    }

    private static void renderScopedDefinitions(
            StringBuilder out,
            Map<Scope, Map<String, ConfigDef.ConfigKey>> keys,
            Set<String> disabledConfigs) {
        validateDisabledConfigs(disabledConfigs, keys);
        renderDefinition(out, "Shared", keys.get(Scope.SHARED), disabledConfigs);
        out.append('\n');
        renderRoleDefinition(out, "Controller", keys.get(Scope.CONTROLLER), disabledConfigs);
        out.append('\n');
        renderRoleDefinition(out, "Broker", keys.get(Scope.BROKER), disabledConfigs);
        out.append('\n');
        out.append("#Combined: #Controller & #Broker\n");
    }

    private static Map<Scope, Map<String, ConfigDef.ConfigKey>> collectConfigKeys(List<ScopedConfigSource> sources) {
        Map<Scope, Map<String, ConfigDef.ConfigKey>> keys = new EnumMap<>(Scope.class);
        for (Scope scope : Scope.values()) {
            keys.put(scope, new LinkedHashMap<>());
        }
        for (ScopedConfigSource source : sources) {
            for (Map.Entry<String, ConfigDef.ConfigKey> entry : source.configDef().configKeys().entrySet()) {
                keys.get(source.scope()).putIfAbsent(entry.getKey(), entry.getValue());
            }
        }
        return keys;
    }

    private static void validateDisabledConfigs(
            Set<String> disabledConfigs,
            Map<Scope, Map<String, ConfigDef.ConfigKey>> keys) {
        Set<String> knownConfigs = new TreeSet<>();
        for (Map<String, ConfigDef.ConfigKey> scopedKeys : keys.values()) {
            knownConfigs.addAll(scopedKeys.keySet());
        }
        Set<String> unknownConfigs = new TreeSet<>(disabledConfigs);
        unknownConfigs.removeAll(knownConfigs);
        if (!unknownConfigs.isEmpty()) {
            throw new IllegalStateException("Disabled configs are not defined by Kafka: " + unknownConfigs);
        }
    }

    private static void validateScopedConfigsMatchKafka(
            Map<Scope, Map<String, ConfigDef.ConfigKey>> keys,
            ConfigDef kafkaConfigDef) {
        Set<String> scopedConfigs = configNames(keys);
        Set<String> kafkaConfigs = new TreeSet<>(kafkaConfigDef.configKeys().keySet());

        Set<String> unclassifiedConfigs = new TreeSet<>(kafkaConfigs);
        unclassifiedConfigs.removeAll(scopedConfigs);
        Set<String> unknownConfigs = new TreeSet<>(scopedConfigs);
        unknownConfigs.removeAll(kafkaConfigs);

        if (!unclassifiedConfigs.isEmpty() || !unknownConfigs.isEmpty()) {
            throw new IllegalStateException(
                    "Scoped Kafka configs do not match AbstractKafkaConfig.CONFIG_DEF. "
                            + "Unclassified Kafka configs: " + unclassifiedConfigs
                            + "; unknown scoped configs: " + unknownConfigs);
        }
    }

    private static Set<String> configNames(Map<Scope, Map<String, ConfigDef.ConfigKey>> keys) {
        Set<String> names = new TreeSet<>();
        for (Map<String, ConfigDef.ConfigKey> scopedKeys : keys.values()) {
            names.addAll(scopedKeys.keySet());
        }
        return names;
    }

    private static void renderRoleDefinition(
        StringBuilder out,
        String definitionName,
        Map<String, ConfigDef.ConfigKey> keys,
        Set<String> disabledConfigs) {
        out.append("#").append(definitionName).append(": #Shared & {\n");
        renderKeys(out, keys, disabledConfigs);
        out.append("\t...\n");
        out.append("}\n");
    }

    private static void renderDefinition(
            StringBuilder out,
            String definitionName,
            ConfigDef configDef,
            Set<String> disabledConfigs) {
        renderDefinition(out, definitionName, configDef.configKeys(), disabledConfigs);
    }

    private static void renderDefinition(
            StringBuilder out,
            String definitionName,
            Map<String, ConfigDef.ConfigKey> keys,
            Set<String> disabledConfigs) {
        out.append("#").append(definitionName).append(": {\n");
        renderKeys(out, keys, disabledConfigs);
        out.append("}\n");
    }

    private static void renderKeys(
            StringBuilder out,
            Map<String, ConfigDef.ConfigKey> keys,
            Set<String> disabledConfigs) {
        Set<String> names = new TreeSet<>(keys.keySet());
        for (String name : names) {
            ConfigDef.ConfigKey key = keys.get(name);
            renderKey(out, key, disabledConfigs.contains(name));
        }
    }

    private static void renderKey(StringBuilder out, ConfigDef.ConfigKey key, boolean disabled) {
        if (key.internalConfig) {
            return;
        }

        renderComment(out, key);
        out.append('\t');
        if (disabled) {
            out.append("// ");
        }
        out.append(cueString(key.name));
        if (key.hasDefault()) {
            out.append("?");
        }
        out.append(": ");

        String constraint = constraint(key);

        if (key.hasDefault()) {
            out.append("*").append(defaultValue(key)).append(" | ");
        }
        out.append(constraint);
        if (key.hasDefault() && key.defaultValue == null) {
            out.append(" | null");
        }
        out.append("\n\n");
    }

    private static void renderComment(StringBuilder out, ConfigDef.ConfigKey key) {
        if (key.validator != null && !handlesValidator(key)) {
            out.append('\t').append("// validator: ").append(oneLine(key.validator.toString())).append('\n');
        }
        if (key.documentation != null && !key.documentation.isBlank()) {
            out.append('\t').append("// ").append(oneLine(stripHtml(key.documentation))).append('\n');
        }
    }

    private static String constraint(ConfigDef.ConfigKey key) {
        if (key.type == ConfigDef.Type.LIST) {
            String elementConstraint = listElementConstraint(key);
            return "[..." + elementConstraint + "]";
        }
        if (isRangeValidator(key.validator) && isNumeric(key.type)) {
            return numericConstraint(key.type, key.validator);
        }
        if (isEnumValidator(key.validator) && isStringLike(key.type)) {
            return scalarType(key.type) + " & (" + enumConstraint(enumValues(key.validator)) + ")";
        }
        return scalarType(key.type);
    }

    private static String scalarType(ConfigDef.Type type) {
        return switch (type) {
            case BOOLEAN -> "bool";
            case STRING, PASSWORD, CLASS -> "string";
            case INT -> "int & >=" + Integer.MIN_VALUE + " & <=" + Integer.MAX_VALUE;
            case SHORT -> "int & >=" + Short.MIN_VALUE + " & <=" + Short.MAX_VALUE;
            case LONG -> "int & >=" + Long.MIN_VALUE + " & <=" + Long.MAX_VALUE;
            case DOUBLE -> "number";
            case LIST -> "[...string]";
        };
    }

    private static String listElementConstraint(ConfigDef.ConfigKey key) {
        if (key.validator == null) {
            return "string";
        }

        if (isEnumValidator(key.validator)) {
            return "(" + enumConstraint(enumValues(key.validator)) + ")";
        }
        return "string";
    }

    private static boolean handlesValidator(ConfigDef.ConfigKey key) {
        if (key.validator == null) {
            return false;
        }
        if (key.type == ConfigDef.Type.LIST) {
            return isEnumValidator(key.validator);
        }
        return (isEnumValidator(key.validator) && isStringLike(key.type))
                || (isRangeValidator(key.validator) && isNumeric(key.type));
    }

    private static boolean isStringLike(ConfigDef.Type type) {
        return type == ConfigDef.Type.STRING || type == ConfigDef.Type.PASSWORD || type == ConfigDef.Type.CLASS;
    }

    private static boolean isNumeric(ConfigDef.Type type) {
        return type == ConfigDef.Type.INT || type == ConfigDef.Type.SHORT || type == ConfigDef.Type.LONG
                || type == ConfigDef.Type.DOUBLE;
    }

    private static boolean isEnumValidator(ConfigDef.Validator validator) {
        return validator instanceof ConfigDef.ValidString || validator instanceof ConfigDef.ValidList;
    }

    private static boolean isRangeValidator(ConfigDef.Validator validator) {
        return validator instanceof ConfigDef.Range;
    }

    private static List<String> enumValues(ConfigDef.Validator validator) {
        if (validator instanceof ConfigDef.ValidList) {
            validator = readTypedField(validator, "validString", ConfigDef.ValidString.class);
        }
        return readStringListField(validator, "validStrings");
    }

    private static String enumConstraint(List<String> values) {
        if (values.isEmpty()) {
            return "string";
        }
        List<String> quoted = new ArrayList<>();
        for (String value : values) {
            quoted.add(cueString(value));
        }
        return String.join(" | ", quoted);
    }

    private static String numericConstraint(ConfigDef.Type type, ConfigDef.Validator validator) {
        String scalar = scalarType(type);
        if (type == ConfigDef.Type.DOUBLE) {
            String range = NumericRange.fromValidator(validator).toCueConstraint();
            if (range.isEmpty()) {
                return scalar;
            }
            return scalar + " & " + range;
        }
        NumericRange range = NumericRange.forType(type).merge(NumericRange.fromValidator(validator));
        String rangeConstraint = range.toCueConstraint();
        if (rangeConstraint.isEmpty()) {
            return scalar;
        }
        return "int & " + rangeConstraint;
    }

    private record NumericRange(String lower, String upper) {
        static NumericRange forType(ConfigDef.Type type) {
            return switch (type) {
                case INT -> new NumericRange(String.valueOf(Integer.MIN_VALUE), String.valueOf(Integer.MAX_VALUE));
                case SHORT -> new NumericRange(String.valueOf(Short.MIN_VALUE), String.valueOf(Short.MAX_VALUE));
                case LONG -> new NumericRange(String.valueOf(Long.MIN_VALUE), String.valueOf(Long.MAX_VALUE));
                default -> new NumericRange(null, null);
            };
        }

        static NumericRange fromValidator(ConfigDef.Validator validator) {
            Number min = readTypedField(validator, "min", Number.class);
            Number max = readTypedField(validator, "max", Number.class);
            return new NumericRange(min == null ? null : min.toString(), max == null ? null : max.toString());
        }

        NumericRange merge(NumericRange other) {
            return new NumericRange(maxLower(lower, other.lower), minUpper(upper, other.upper));
        }

        String toCueConstraint() {
            List<String> constraints = new ArrayList<>();
            if (lower != null) {
                constraints.add(">=" + lower);
            }
            if (upper != null) {
                constraints.add("<=" + upper);
            }
            return String.join(" & ", constraints);
        }

        private static String maxLower(String left, String right) {
            if (left == null) {
                return right;
            }
            if (right == null) {
                return left;
            }
            return new BigDecimal(left).compareTo(new BigDecimal(right)) >= 0 ? left : right;
        }

        private static String minUpper(String left, String right) {
            if (left == null) {
                return right;
            }
            if (right == null) {
                return left;
            }
            return new BigDecimal(left).compareTo(new BigDecimal(right)) <= 0 ? left : right;
        }
    }

    private static List<String> readStringListField(Object target, String name) {
        Object value = readField(target, name);
        if (!(value instanceof List<?> list)) {
            throw new IllegalStateException(
                    "Kafka validator field is not a list: " + target.getClass().getName() + "." + name);
        }
        List<String> values = new ArrayList<>();
        for (Object item : list) {
            values.add(Objects.toString(item, ""));
        }
        return List.copyOf(values);
    }

    private static <T> T readTypedField(Object target, String name, Class<T> type) {
        return type.cast(readField(target, name));
    }

    private static Object readField(Object target, String name) {
        try {
            Field field = target.getClass().getDeclaredField(name);
            field.setAccessible(true);
            return field.get(target);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(
                    "Cannot read Kafka validator field " + target.getClass().getName() + "." + name, e);
        }
    }

    private static String defaultValue(ConfigDef.ConfigKey key) {
        Object value = key.defaultValue;
        if (value == null) {
            return "null";
        }
        return switch (key.type) {
            case BOOLEAN, INT, SHORT, LONG, DOUBLE -> value.toString();
            case STRING, PASSWORD, CLASS -> cueString(value.toString());
            case LIST -> listDefault(value);
        };
    }

    private static String listDefault(Object value) {
        if (value instanceof List<?> list) {
            List<String> values = new ArrayList<>();
            for (Object item : list) {
                values.add(cueString(Objects.toString(item, "")));
            }
            return "[" + String.join(", ", values) + "]";
        }
        String text = value.toString();
        if (text.isBlank()) {
            return "[]";
        }
        List<String> values = new ArrayList<>();
        for (String item : text.split(",")) {
            values.add(cueString(item.trim()));
        }
        return "[" + String.join(", ", values) + "]";
    }

    private static String cueString(String value) {
        StringBuilder escaped = new StringBuilder("\"");
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '\\' -> escaped.append("\\\\");
                case '"' -> escaped.append("\\\"");
                case '\n' -> escaped.append("\\n");
                case '\r' -> escaped.append("\\r");
                case '\t' -> escaped.append("\\t");
                default -> escaped.append(c);
            }
        }
        escaped.append('"');
        return escaped.toString();
    }

    private static String stripHtml(String value) {
        return value.replaceAll("<[^>]+>", "");
    }

    private static String oneLine(String value) {
        String text = value.replace('\n', ' ').replace('\r', ' ').replace('\t', ' ');
        return text.replaceAll("\\s+", " ").strip();
    }

    private static ConfigDef filteredConfigDef(ConfigDef source, Set<String> names) {
        ConfigDef filtered = new ConfigDef();
        for (String name : names) {
            ConfigDef.ConfigKey key = source.configKeys().get(name);
            if (key == null) {
                throw new IllegalStateException("Kafka ConfigDef no longer contains expected key: " + name);
            }
            define(filtered, key);
        }
        return filtered;
    }

    private static ConfigDef withoutConfigs(ConfigDef source, Set<String> excludedNames) {
        ConfigDef filtered = new ConfigDef();
        for (ConfigDef.ConfigKey key : source.configKeys().values()) {
            if (!excludedNames.contains(key.name)) {
                define(filtered, key);
            }
        }
        return filtered;
    }

    private static void define(ConfigDef configDef, ConfigDef.ConfigKey key) {
        configDef.define(key);
    }

    enum Scope {
        SHARED,
        CONTROLLER,
        BROKER
    }

    record ScopedConfigSource(Scope scope, Supplier<ConfigDef> supplier) {
        ConfigDef configDef() {
            return supplier.get();
        }
    }

    record CliOptions(Path output) {
        static CliOptions parse(String[] args) {
            Path output = null;

            for (int i = 0; i < args.length; i++) {
                String arg = args[i];
                switch (arg) {
                    case "--help", "-h" -> {
                        usage(System.out);
                        System.exit(0);
                    }
                    case "--output", "-o" -> {
                        if (++i >= args.length) {
                            throw new IllegalArgumentException("--output requires a path");
                        }
                        output = Path.of(args[i]);
                    }
                    default -> {
                        if (arg.startsWith("--output=")) {
                            output = Path.of(arg.substring("--output=".length()));
                        } else {
                            throw new IllegalArgumentException("Unknown argument: " + arg);
                        }
                    }
                }
            }

            return new CliOptions(output);
        }

        private static void usage(OutputStream out) {
            PrintStream print = new PrintStream(out, true, StandardCharsets.UTF_8);
            print.println("Usage: kafka-config-cue [--output FILE]");
        }
    }
}
