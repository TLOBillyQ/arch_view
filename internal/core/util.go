package core

import (
	"fmt"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

func normalizePath(path string) string {
	return strings.ReplaceAll(path, "\\", "/")
}

func resolvePath(base, path string) string {
	if path == "" {
		return normalizePath(base)
	}
	if filepath.IsAbs(path) {
		return normalizePath(filepath.Clean(path))
	}
	return normalizePath(filepath.Clean(filepath.Join(base, path)))
}

func splitString(value, delimiter string) []string {
	if value == "" {
		return []string{}
	}
	return strings.Split(value, delimiter)
}

func copyStrings(values []string) []string {
	copied := make([]string, len(values))
	copy(copied, values)
	return copied
}

func joinStrings(values []string, delimiter string) string {
	return strings.Join(values, delimiter)
}

func intToString(value int) string {
	return strconv.Itoa(value)
}

func sortedKeys[T any](m map[string]T) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func edgeKey(from, to string) string {
	return from + "->" + to
}

func startsWithSegments(parts, prefix []string) bool {
	if len(prefix) > len(parts) {
		return false
	}
	for i := range prefix {
		if parts[i] != prefix[i] {
			return false
		}
	}
	return true
}

func viewKey(pathSegments []string) string {
	if len(pathSegments) == 0 {
		return "root"
	}
	return strings.Join(pathSegments, ".")
}

func stripSrcPrefix(moduleID string) string {
	if strings.HasPrefix(moduleID, "src.") {
		return moduleID[4:]
	}
	return moduleID
}

func sourceFilename(path string) string {
	if path == "" {
		return ""
	}
	normalized := normalizePath(path)
	parts := splitString(normalized, "/")
	return parts[len(parts)-1]
}

func sourceFilenameBase(path string) string {
	filename := sourceFilename(path)
	if filename == "" {
		return ""
	}
	idx := strings.LastIndex(filename, ".")
	if idx < 0 {
		return filename
	}
	return filename[:idx]
}

func sortedEdges(edgeMap map[string]Edge) []Edge {
	keys := sortedKeys(edgeMap)
	edges := make([]Edge, 0, len(keys))
	for _, key := range keys {
		edges = append(edges, edgeMap[key])
	}
	return edges
}

func listToSet(values []string) map[string]bool {
	set := map[string]bool{}
	for _, value := range values {
		set[value] = true
	}
	return set
}

func mustCompile(pattern string) *regexp.Regexp {
	return regexp.MustCompile(pattern)
}

func escapeRegexLiteral(text string) string {
	return regexp.QuoteMeta(text)
}

func luaPatternToRegex(pattern string) string {
	var builder strings.Builder
	for i := 0; i < len(pattern); i++ {
		ch := pattern[i]
		if ch == '%' {
			if i+1 >= len(pattern) {
				builder.WriteString("%")
				continue
			}
			i++
			next := pattern[i]
			switch next {
			case 'a':
				builder.WriteString("[A-Za-z]")
			case 'A':
				builder.WriteString("[^A-Za-z]")
			case 'd':
				builder.WriteString("[0-9]")
			case 'D':
				builder.WriteString("[^0-9]")
			case 's':
				builder.WriteString(`\\s`)
			case 'S':
				builder.WriteString(`\\S`)
			case 'w':
				builder.WriteString("[A-Za-z0-9]")
			case 'W':
				builder.WriteString("[^A-Za-z0-9]")
			case 'p':
				builder.WriteString(`[[:punct:]]`)
			case 'P':
				builder.WriteString(`[^[:punct:]]`)
			case 'l':
				builder.WriteString("[a-z]")
			case 'L':
				builder.WriteString("[^a-z]")
			case 'u':
				builder.WriteString("[A-Z]")
			case 'U':
				builder.WriteString("[^A-Z]")
			case 'x':
				builder.WriteString("[0-9A-Fa-f]")
			case 'X':
				builder.WriteString("[^0-9A-Fa-f]")
			default:
				builder.WriteString(escapeRegexLiteral(string(next)))
			}
			continue
		}
		switch ch {
		case '^', '$', '.', '+', '*', '?', '(', ')', '[', ']', '|':
			builder.WriteByte(ch)
		case '-':
			builder.WriteString("*?")
		default:
			builder.WriteString(escapeRegexLiteral(string(ch)))
		}
	}
	return builder.String()
}

var patternCache = map[string]*regexp.Regexp{}

func matchesLuaPattern(value, pattern string) bool {
	compiled, ok := patternCache[pattern]
	if !ok {
		compiled = regexp.MustCompile(luaPatternToRegex(pattern))
		patternCache[pattern] = compiled
	}
	return compiled.FindStringIndex(value) != nil
}

func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

func sortedStringMapKeysOfBool(m map[string]bool) []string {
	return sortedKeys(m)
}

func debugPair(values []string) string {
	return fmt.Sprintf("[%s]", strings.Join(values, ","))
}
