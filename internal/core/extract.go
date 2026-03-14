package core

import (
	"regexp"
	"sort"
	"strings"
)

var (
	requirePatterns = []*regexp.Regexp{
		mustCompile(`require\s*\(\s*"([^"]+)"\s*\)`),
		mustCompile(`require\s*\(\s*'([^']+)'\s*\)`),
		mustCompile(`require\s+"([^"]+)"`),
		mustCompile(`require\s+'([^']+)'`),
	}
	forwardRequireDouble = mustCompile(`^return require\(\s*"([^"]+)"\s*\)$`)
	forwardRequireSingle = mustCompile(`^return require\(\s*'([^']+)'\s*\)$`)
	lineCommentPattern   = mustCompile(`--[^\n]*`)
)

func stripLineComment(line string) string {
	if idx := strings.Index(line, "--"); idx >= 0 {
		return line[:idx]
	}
	return line
}

func collectRequiresFromLine(line string, sink map[string]bool) {
	clean := stripLineComment(line)
	for _, pattern := range requirePatterns {
		matches := pattern.FindAllStringSubmatch(clean, -1)
		for _, match := range matches {
			if len(match) > 1 {
				sink[match[1]] = true
			}
		}
	}
}

func forwardingShimTarget(text string) string {
	normalized := lineCommentPattern.ReplaceAllString(text, "")
	normalized = strings.Join(strings.Fields(normalized), " ")
	if match := forwardRequireDouble.FindStringSubmatch(normalized); len(match) > 1 {
		return match[1]
	}
	if match := forwardRequireSingle.FindStringSubmatch(normalized); len(match) > 1 {
		return match[1]
	}
	return ""
}

func Extract(scanResult *ScanResult) (Graph, map[string]*Module) {
	modules := map[string]*Module{}
	edgeMap := map[string]Edge{}
	for _, moduleID := range scanResult.ModuleList {
		sourceModule := scanResult.Modules[moduleID]
		internalRequires := map[string]bool{}
		externalRequires := map[string]bool{}
		if forwardingShimTarget(sourceModule.SourceText) == "" {
			for _, line := range strings.Split(sourceModule.SourceText, "\n") {
				lineRequires := map[string]bool{}
				collectRequiresFromLine(line, lineRequires)
				for dep := range lineRequires {
					if dep == moduleID {
						continue
					}
					if scanResult.ModuleIDs[dep] {
						internalRequires[dep] = true
						edgeMap[edgeKey(moduleID, dep)] = Edge{From: moduleID, To: dep}
					} else {
						externalRequires[dep] = true
					}
				}
			}
		}
		modules[moduleID] = &Module{
			ModuleID:          moduleID,
			ModuleSegments:    copyStrings(sourceModule.ModuleSegments),
			NamespaceSegments: copyStrings(sourceModule.NamespaceSegments),
			SourcePath:        sourceModule.SourcePath,
			SourceText:        sourceModule.SourceText,
			InternalRequires:  sortedStringMapKeysOfBool(internalRequires),
			ExternalRequires:  sortedStringMapKeysOfBool(externalRequires),
			Root:              sourceModule.Root,
		}
	}

	edges := sortedEdges(edgeMap)
	sort.Slice(edges, func(i, j int) bool {
		if edges[i].From == edges[j].From {
			return edges[i].To < edges[j].To
		}
		return edges[i].From < edges[j].From
	})
	return Graph{Nodes: copyStrings(scanResult.ModuleList), Edges: edges}, modules
}
