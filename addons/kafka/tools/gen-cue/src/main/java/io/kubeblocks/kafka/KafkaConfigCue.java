package io.kubeblocks.kafka;

import org.apache.kafka.clients.admin.AdminClientConfig;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.server.config.AbstractKafkaConfig;
import org.apache.kafka.storage.internals.log.LogConfig;
import org.apache.kafka.streams.StreamsConfig;

import java.io.IOException;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;
import java.util.TreeSet;
import java.util.function.Supplier;

public final class KafkaConfigCue {
    private static final LinkedHashMap<String, ConfigSource> SOURCES = new LinkedHashMap<>();

    static {
        SOURCES.put("broker", new ConfigSource("Broker", () -> new ConfigDef(AbstractKafkaConfig.CONFIG_DEF)));
        SOURCES.put("topic", new ConfigSource("Topic", LogConfig::configDefCopy));
        // SOURCES.put("producer", new ConfigSource("Producer", ProducerConfig::configDef));
        // SOURCES.put("consumer", new ConfigSource("Consumer", ConsumerConfig::configDef));
        // SOURCES.put("admin", new ConfigSource("Admin", AdminClientConfig::configDef));
        // SOURCES.put("streams", new ConfigSource("Streams", StreamsConfig::configDef));
    }

    private KafkaConfigCue() {
    }

    public static void main(String[] args) throws IOException {
        CliOptions options = CliOptions.parse(args);
        String cue = render(options.includes());

        if (options.output() == null) {
            System.out.print(cue);
        } else {
            Files.writeString(options.output(), cue, StandardCharsets.UTF_8);
        }
    }

    static String render(List<String> includes) {
        StringBuilder out = new StringBuilder();
        out.append("package kafka\n\n");
        out.append("// Generated from Kafka ConfigDef metadata.\n");
        out.append("// Dotted Kafka property names are intentionally kept as flat quoted fields.\n\n");

        for (String include : includes) {
            ConfigSource source = SOURCES.get(include);
            if (source == null) {
                throw new IllegalArgumentException(
                        "Unknown config set '" + include + "'. Known sets: " + SOURCES.keySet());
            }
            renderDefinition(out, source.definitionName(), source.configDef());
            out.append('\n');
        }

        return out.toString();
    }

    static String renderForTest(String definitionName, ConfigDef configDef) {
        StringBuilder out = new StringBuilder();
        renderDefinition(out, definitionName, configDef);
        return out.toString();
    }

    private static void renderDefinition(StringBuilder out, String definitionName, ConfigDef configDef) {
        out.append("#").append(definitionName).append(": {\n");
        Set<String> names = new TreeSet<>(configDef.configKeys().keySet());
        for (String name : names) {
            ConfigDef.ConfigKey key = configDef.configKeys().get(name);
            renderKey(out, key);
        }
        out.append("}\n");
    }

    private static void renderKey(StringBuilder out, ConfigDef.ConfigKey key) {
        if (key.internalConfig) {
            return;
        }

        renderComment(out, key);
        out.append('\t').append(cueString(key.name));
        if (key.hasDefault()) {
            out.append("?");
        }
        out.append(": ");

        String constraint = baseConstraint(key);
        String validatorConstraint = validatorConstraint(key);
        String defaultValue = key.hasDefault() ? defaultValue(key) : null;

        if (defaultValue != null) {
            out.append("*").append(defaultValue).append(" | ");
        }
        out.append(constraint);
        if (!validatorConstraint.isEmpty()) {
            out.append(" & ").append(validatorConstraint);
        }
        if (key.hasDefault() && key.defaultValue == null) {
            out.append(" | null");
        }
        out.append("\n\n");
    }

    private static void renderComment(StringBuilder out, ConfigDef.ConfigKey key) {
        if (key.validator != null && validatorConstraint(key).isEmpty()) {
            out.append('\t').append("// validator: ").append(oneLine(key.validator.toString())).append('\n');
        }
        if (key.documentation != null && !key.documentation.isBlank()) {
            out.append('\t').append("// ").append(oneLine(stripHtml(key.documentation))).append('\n');
        }
    }

    private static String baseConstraint(ConfigDef.ConfigKey key) {
        if (key.type == ConfigDef.Type.LIST) {
            String elementConstraint = listElementConstraint(key);
            return "[..." + elementConstraint + "]";
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

        String validator = key.validator.toString();
        if (looksLikeEnum(validator)) {
            return "(" + enumConstraint(enumValues(validator)) + ")";
        }
        return "string";
    }

    private static String validatorConstraint(ConfigDef.ConfigKey key) {
        if (key.validator == null || key.type == ConfigDef.Type.LIST) {
            return "";
        }

        String validator = key.validator.toString();
        if (looksLikeEnum(validator) && isStringLike(key.type)) {
            return "(" + enumConstraint(enumValues(validator)) + ")";
        }
        if (looksLikeRange(validator) && isNumeric(key.type)) {
            return rangeConstraint(validator);
        }
        return "";
    }

    private static boolean isStringLike(ConfigDef.Type type) {
        return type == ConfigDef.Type.STRING || type == ConfigDef.Type.PASSWORD || type == ConfigDef.Type.CLASS;
    }

    private static boolean isNumeric(ConfigDef.Type type) {
        return type == ConfigDef.Type.INT || type == ConfigDef.Type.SHORT || type == ConfigDef.Type.LONG
                || type == ConfigDef.Type.DOUBLE;
    }

    private static boolean looksLikeEnum(String value) {
        return value.startsWith("[") && value.endsWith("]") && !value.contains("...");
    }

    private static boolean looksLikeRange(String value) {
        return value.startsWith("[") && value.endsWith("]") && value.contains("...");
    }

    private static List<String> enumValues(String validator) {
        String inner = validator.substring(1, validator.length() - 1).trim();
        if (inner.isEmpty()) {
            return List.of();
        }
        return Arrays.stream(inner.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .toList();
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

    private static String rangeConstraint(String validator) {
        String inner = validator.substring(1, validator.length() - 1);
        String[] rawParts = inner.split(",", -1);
        List<String> parts = Arrays.stream(rawParts).map(String::trim).toList();
        List<String> constraints = new ArrayList<>();
        if (!parts.isEmpty() && !parts.get(0).isEmpty() && !parts.get(0).equals("...")) {
            constraints.add(">=" + parts.get(0));
        }
        String upper = parts.get(parts.size() - 1);
        if (!upper.isEmpty() && !upper.equals("...")) {
            constraints.add("<=" + upper);
        }
        return String.join(" & ", constraints);
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

    record ConfigSource(String definitionName, Supplier<ConfigDef> supplier) {
        ConfigDef configDef() {
            return supplier.get();
        }
    }

    record CliOptions(List<String> includes, Path output) {
        static CliOptions parse(String[] args) {
            List<String> includes = new ArrayList<>(SOURCES.keySet());
            Path output = null;

            for (int i = 0; i < args.length; i++) {
                String arg = args[i];
                switch (arg) {
                    case "--help", "-h" -> {
                        usage(System.out);
                        System.exit(0);
                    }
                    case "--include" -> {
                        if (++i >= args.length) {
                            throw new IllegalArgumentException("--include requires a comma-separated value");
                        }
                        includes = parseIncludes(args[i]);
                    }
                    case "--output", "-o" -> {
                        if (++i >= args.length) {
                            throw new IllegalArgumentException("--output requires a path");
                        }
                        output = Path.of(args[i]);
                    }
                    default -> {
                        if (arg.startsWith("--include=")) {
                            includes = parseIncludes(arg.substring("--include=".length()));
                        } else if (arg.startsWith("--output=")) {
                            output = Path.of(arg.substring("--output=".length()));
                        } else {
                            throw new IllegalArgumentException("Unknown argument: " + arg);
                        }
                    }
                }
            }

            return new CliOptions(includes, output);
        }

        private static List<String> parseIncludes(String value) {
            List<String> includes = Arrays.stream(value.split(","))
                    .map(String::trim)
                    .filter(s -> !s.isEmpty())
                    .map(s -> s.toLowerCase(Locale.ROOT))
                    .toList();
            for (String include : includes) {
                if (!SOURCES.containsKey(include)) {
                    throw new IllegalArgumentException(
                            "Unknown config set '" + include + "'. Known sets: " + SOURCES.keySet());
                }
            }
            return includes;
        }

        private static void usage(OutputStream out) {
            PrintStream print = new PrintStream(out, true, StandardCharsets.UTF_8);
            print.println(
                    "Usage: kafka-config-cue [--include broker,topic,producer,consumer,admin,streams] [--output FILE]");
        }
    }
}
