package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"

	sitter "github.com/tree-sitter/go-tree-sitter"
	java "github.com/tree-sitter/tree-sitter-java/bindings/go"
)

// source files:
// - https://raw.githubusercontent.com/apache/pulsar/v3.0.2/pulsar-broker-common/src/main/java/org/apache/pulsar/broker/ServiceConfiguration.java
// - https://raw.githubusercontent.com/apache/pulsar/v3.0.2/pulsar-proxy/src/main/java/org/apache/pulsar/proxy/server/ProxyConfiguration.java

type Field struct {
	Name         string `json:"name"`
	Type         string `json:"type"`
	DefaultValue string `json:"default_value,omitempty"`
	Doc          string `json:"doc,omitempty"`
	Dynamic      string `json:"dynamic,omitempty"`
	Category     string `json:"category,omitempty"`
	Deprecated   bool   `json:"deprecated,omitempty"`
}

type ConfigParser struct {
	source []byte
	debug  bool
	cursor *sitter.TreeCursor
}

func main() {
	debug := flag.Bool("debug", false, "Enable debug mode to print node types")
	cue := flag.Bool("cue", false, "Output cue file")
	flag.Parse()

	source, err := os.ReadFile("ServiceConfiguration.java")
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to read file: %v\n", err)
		os.Exit(1)
	}

	parser := sitter.NewParser()
	parser.SetLanguage(sitter.NewLanguage(java.Language()))

	tree := parser.ParseCtx(context.Background(), source, nil)
	if tree == nil {
		fmt.Fprintf(os.Stderr, "failed to parse java file\n")
		os.Exit(1)
	}
	defer tree.Close()

	root := tree.RootNode()
	cp := &ConfigParser{
		source: source,
		debug:  *debug,
		cursor: tree.Walk(),
	}

	fields := cp.extractFields(root)

	if *debug {
		return
	}

	if *cue {
		// TODO: write cue files
	}

	out, _ := json.Marshal(fields)
	fmt.Println(string(out))
}

func (cp *ConfigParser) nodeText(n *sitter.Node) string {
	if n == nil {
		return ""
	}
	return string(cp.source[n.StartByte():n.EndByte()])
}

func (cp *ConfigParser) extractFields(root *sitter.Node) []Field {
	var results []Field

	var walk func(*sitter.Node)
	walk = func(n *sitter.Node) {
		if cp.debug {
			cp.debugPrintNode(n, 0)
		}

		if n.Kind() == "field_declaration" {
			if field := cp.parseField(n); field != nil {
				results = append(results, *field)
			}
		}

		for _, child := range n.NamedChildren(cp.cursor) {
			walk(&child)
		}
	}

	walk(root)
	return results
}

func (cp *ConfigParser) parseField(n *sitter.Node) *Field {
	field := &Field{}

	for _, child := range n.NamedChildren(cp.cursor) {
		kind := child.Kind()

		switch kind {
		case "modifiers":
			cp.extractModifiers(&child, field)
		case "variable_declarator":
			if nameNode := child.ChildByFieldName("name"); nameNode != nil {
				field.Name = cp.nodeText(nameNode)
			}
			if valueNode := child.ChildByFieldName("value"); valueNode != nil {
				field.DefaultValue = cp.extractStringValue(valueNode)
			}
		default:
			if isTypeIdentifier(kind) {
				field.Type = cp.nodeText(&child)
			}
		}
	}

	if field.Name == "" {
		return nil
	}
	return field
}

func (cp *ConfigParser) extractModifiers(modifiers *sitter.Node, field *Field) {
	for _, child := range modifiers.NamedChildren(cp.cursor) {
		switch child.Kind() {
		case "annotation":
			nameNode := child.ChildByFieldName("name")
			if nameNode == nil || cp.nodeText(nameNode) != "FieldContext" {
				continue
			}
			field.Doc, field.Dynamic, field.Category = cp.extractFieldContextAnnotation(&child)
		case "marker_annotation":
			nameNode := child.ChildByFieldName("name")
			if nameNode == nil || cp.nodeText(nameNode) != "Deprecated" {
				continue
			}
			// it has Deprecated marker
			field.Deprecated = true
		default:
			continue
		}
	}
}

func (cp *ConfigParser) extractFieldContextAnnotation(ann *sitter.Node) (doc, dynamic, category string) {
	args := ann.ChildByFieldName("arguments")
	if args == nil {
		return
	}

	for _, pair := range args.NamedChildren(cp.cursor) {
		if pair.Kind() != "element_value_pair" {
			return
		}

		key := pair.ChildByFieldName("key")
		val := pair.ChildByFieldName("value")
		if key == nil || val == nil {
			return
		}

		keyStr := cp.nodeText(key)

		switch keyStr {
		case "doc":
			doc = cp.extractStringValue(val)
		case "dynamic":
			dynamic = cp.nodeText(val)
		case "category":
			category = cp.nodeText(val)
		}
	}

	return doc, dynamic, category
}

func isTypeIdentifier(kind string) bool {
	switch kind {
	case "type_identifier", "generic_type", "integral_type", "primitive_type",
		"scoped_type_identifier", "boolean_type", "void_type":
		return true
	}
	return false
}

func (cp *ConfigParser) extractStringValue(n *sitter.Node) string {
	if n == nil {
		return ""
	}

	if n.Kind() == "string_literal" {
		text := cp.nodeText(n)
		return strings.Trim(text, `"`)
	}

	var res strings.Builder
	for _, child := range n.NamedChildren(cp.cursor) {
		res.WriteString(cp.extractStringValue(&child))
	}

	return res.String()
}

func (cp *ConfigParser) debugPrintNode(n *sitter.Node, depth int) {
	indent := strings.Repeat("  ", depth)
	text := cp.nodeText(n)
	if len(text) > 60 {
		text = text[:60] + "..."
	}
	// text = strings.ReplaceAll(text, "\n", "\\n")
	fmt.Fprintf(os.Stdout, "%sType: %-30s Text: %q\n", indent, n.Kind(), text)

	for _, child := range n.NamedChildren(cp.cursor) {
		cp.debugPrintNode(&child, depth+1)
	}
}
