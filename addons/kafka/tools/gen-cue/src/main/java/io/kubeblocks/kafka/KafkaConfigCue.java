package io.kubeblocks.kafka;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.server.config.AbstractKafkaConfig;
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
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.TreeSet;
import java.util.function.Supplier;

public final class KafkaConfigCue {
    private static final List<ConfigSource> SOURCES = List.of(
            new ConfigSource("Broker", () -> new ConfigDef(AbstractKafkaConfig.CONFIG_DEF)),
            new ConfigSource("Topic", LogConfig::configDefCopy));

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
        out.append("// Generated from Kafka ConfigDef metadata.\n");
        out.append("// Dotted Kafka property names are intentionally kept as flat quoted fields.\n\n");

        for (ConfigSource source : SOURCES) {
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

        String constraint = constraint(key);
        String defaultValue = key.hasDefault() ? defaultValue(key) : null;

        if (defaultValue != null) {
            out.append("*").append(defaultValue).append(" | ");
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
            return new NumericRange(numberString(min), numberString(max));
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

    private static String numberString(Number number) {
        return number == null ? null : number.toString();
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

    record ConfigSource(String definitionName, Supplier<ConfigDef> supplier) {
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
