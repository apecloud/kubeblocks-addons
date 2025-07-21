// used to parse tidb config documentations and convert it to configconstraints
// I find this method very unreliable. Still need many manual tuning.
// In the end, this method may not outperform using a LLM to do the same thing.

package main

import (
	"fmt"
	"io"
	"math"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/text"
)

var debug = false

func DPrintf(format string, a ...any) (n int, err error) {
	if debug {
		return fmt.Printf(format, a...)
	}
	return 0, nil
}

func main() {
	// data, err := os.ReadFile("pd.md")
	// if err != nil {
	// 	panic(err)
	// }
	// parser := goldmark.DefaultParser()
	// reader := text.NewReader(data)
	// doc := parser.Parse(reader)
	// doc.Dump(data, 0)

	// url := "https://raw.githubusercontent.com/pingcap/docs/refs/heads/release-7.5/pd-configuration-file.md"
	// url := "https://raw.githubusercontent.com/pingcap/docs/refs/heads/release-7.5/tikv-configuration-file.md"
	url := "https://raw.githubusercontent.com/pingcap/docs/refs/heads/release-7.5/tidb-configuration-file.md"
	resp, err := http.Get(url)
	if err != nil {
		panic(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		panic(err)
	}

	parser := goldmark.DefaultParser()
	reader := text.NewReader(data)
	doc := parser.Parse(reader)
	walker := walker{document: data, level: -1}
	if err = ast.Walk(doc, walker.walk); err != nil {
		panic(err)
	}
}

type walker struct {
	document       []byte
	level          int
	tableName      string
	configName     string
	configConsumed bool
}

// the general structure is:
// a level 2 heading is a table name
// follows a level 3 heading which is config name
// follows a list which is description, defaults, and constraints

func (w *walker) processConfigName(h ast.Heading) {
	for n := h.FirstChild(); n != nil; n = n.NextSibling() {
		if n.Kind() == ast.KindCodeSpan {
			t := n.FirstChild()
			w.configName = string(t.(*ast.Text).Value(w.document))
			DPrintf("current config name is %v\n", w.configName)
		}
	}
}

func (w *walker) processConfigConstraint(l ast.List) {
	var defaultValue, description string
	var min = math.NaN()
	var max = math.NaN()
	var configType = "string"
	// n is ListItem
	for n := l.FirstChild(); n != nil; n = n.NextSibling() {
		t := string(n.Text(w.document))
		if strings.Contains(t, "Default value") {
			// handle cases like "Default value: `0` (automatically adjusts the buffer size)"
			re := regexp.MustCompile(`\(.*\)`)
			defaultValue = re.ReplaceAllString(t, "")
			defaultValue = strings.Replace(defaultValue, "Default value: ", "", 1)
			defaultValue = strings.Trim(defaultValue, " ")
			defaultValue = strings.Trim(defaultValue, "`")
			if defaultValue == "true" || defaultValue == "false" {
				configType = "bool"
			}
			defaultValue = strings.Trim(defaultValue, "\"")
		} else if strings.Contains(t, "Minimum value") {
			minStr := strings.Trim(strings.Replace(t, "Minimum value: ", "", 1), "`")
			minTmp, err := strconv.ParseFloat(minStr, 32)
			if err != nil {
				DPrintf("warn: invalid min value. err: %v\n", err)
			} else {
				// check default value
				_, err := strconv.ParseFloat(defaultValue, 32)
				if err == nil {
					configType = "float"
					min = minTmp
				}
			}
		} else if strings.Contains(t, "Maximum value") {
			maxStr := strings.Trim(strings.Replace(t, "Maximum value: ", "", 1), "`")
			maxTmp, err := strconv.ParseFloat(maxStr, 32)
			if err != nil {
				DPrintf("warn: invalid max value. err: %v\n", err)
			} else {
				// check default value
				_, err := strconv.ParseFloat(defaultValue, 32)
				if err == nil {
					configType = "float"
					max = maxTmp
				}
			}
		} else {
			if description != "" {
				description = strings.TrimRight(description, ".")
				description += ". "
			}
			description += t
		}
	}
	fullName := w.configName
	if w.tableName != "" {
		fullName = w.tableName + "." + w.configName
	}
	s := fmt.Sprintf("\"%v\": %v ", fullName, configType)
	if !math.IsNaN(min) {
		s += fmt.Sprintf("& >=%v ", min)
	}
	if !math.IsNaN(max) {
		s += fmt.Sprintf("& <=%v ", max)
	}
	if defaultValue != "" {
		if configType == "string" {
			s += fmt.Sprintf("| *\"%v\"", defaultValue)
		} else {
			s += fmt.Sprintf("| *%v", defaultValue)
		}
	}
	fmt.Printf("    // %v\n", description)
	fmt.Printf("    %v\n\n", s)
	w.configConsumed = true
}

func (w *walker) walk(n ast.Node, entering bool) (ast.WalkStatus, error) {
	if entering {
		w.level++
		switch real := n.(type) {
		case *ast.Heading:
			if real.Level == 2 {
				s := string(real.Text(w.document))
				if strings.Contains(s, "title: ") {
					// ThematicBreak, skip
					return ast.WalkContinue, nil
				}
				if s == "Global configuration" {
					s = ""
				}
				// filter html tags
				re := regexp.MustCompile("<.*>.*</.*>")
				s = re.ReplaceAllString(s, "")
				s = strings.Trim(s, " ")
				w.tableName = s
				DPrintf("current table name is %s\n", w.tableName)
			}
			if real.Level == 3 {
				w.configConsumed = false
				if strings.Contains(w.tableName, "deprecated") {
					// skip process
					return ast.WalkContinue, nil
				}
				w.processConfigName(*real)
				return ast.WalkSkipChildren, nil
			}
		case *ast.List:
			if strings.Contains(w.tableName, "deprecated") {
				// skip process
				return ast.WalkContinue, nil
			}
			if w.configConsumed {
				// ignoring any list that is not directly following a config name
				// real.Dump(w.document, w.level)
				// panic("!")
				return ast.WalkContinue, nil
			}
			w.processConfigConstraint(*real)
			return ast.WalkSkipChildren, nil
		}
	} else {
		w.level--
	}
	return ast.WalkContinue, nil
}
