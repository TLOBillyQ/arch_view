package core

import "sort"

func patterns(ruleField []string) []string {
	return ruleField
}

func matchesAny(value string, patterns []string) bool {
	for _, pattern := range patterns {
		if matchesLuaPattern(value, pattern) {
			return true
		}
	}
	return false
}

func matchesRule(moduleID string, rule Rule) bool {
	return matchesAny(moduleID, rule.Match)
}

func resolveComponent(moduleID string, config Config) string {
	for _, rule := range config.ComponentRules {
		if matchesRule(moduleID, rule) {
			return rule.Component
		}
	}
	return ""
}

func resolveAbstract(moduleID string, config Config) bool {
	for _, rule := range config.AbstractRules {
		if matchesRule(moduleID, rule) {
			return true
		}
	}
	return false
}

func ClassifyModules(modules map[string]*Module, config Config) map[string]*Module {
	classified := map[string]*Module{}
	for _, moduleID := range sortedKeys(modules) {
		moduleInfo := modules[moduleID]
		classified[moduleID] = &Module{
			ModuleID:          moduleInfo.ModuleID,
			ModuleSegments:    copyStrings(moduleInfo.ModuleSegments),
			NamespaceSegments: copyStrings(moduleInfo.NamespaceSegments),
			SourcePath:        moduleInfo.SourcePath,
			SourceText:        moduleInfo.SourceText,
			InternalRequires:  copyStrings(moduleInfo.InternalRequires),
			ExternalRequires:  copyStrings(moduleInfo.ExternalRequires),
			Root:              moduleInfo.Root,
			Component:         resolveComponent(moduleID, config),
			Abstract:          resolveAbstract(moduleID, config),
		}
	}
	return classified
}

func ClassifyEdges(graph Graph, modules map[string]*Module) []ClassifiedEdge {
	classified := []ClassifiedEdge{}
	for _, edge := range graph.Edges {
		target := modules[edge.To]
		edgeType := "direct"
		if target != nil && target.Abstract {
			edgeType = "abstract"
		}
		classified = append(classified, ClassifiedEdge{From: edge.From, To: edge.To, Type: edgeType})
	}
	sort.Slice(classified, func(i, j int) bool {
		if classified[i].From == classified[j].From {
			if classified[i].To == classified[j].To {
				return classified[i].Type < classified[j].Type
			}
			return classified[i].To < classified[j].To
		}
		return classified[i].From < classified[j].From
	})
	return classified
}

func ruleAllowsEdge(edge Edge, rule Rule) bool {
	for _, allow := range rule.Allow {
		if matchesAny(edge.From, allow.From) && matchesAny(edge.To, allow.To) {
			return true
		}
	}
	return false
}

func currentCycleKeys(graph Graph) map[string][]string {
	cycleMap := map[string][]string{}
	cycles := FindCycles(graph)
	for _, cycle := range cycles {
		copied := copyStrings(cycle)
		sort.Strings(copied)
		cycleMap[joinStrings(copied, "|")] = copied
	}
	return cycleMap
}

func RunCheck(architecture *Architecture, config Config) CheckResult {
	violations := []Violation{}
	for _, moduleID := range sortedKeys(architecture.Modules) {
		moduleInfo := architecture.Modules[moduleID]
		if moduleInfo.Component == "" {
			violations = append(violations, Violation{Kind: "unclassified_module", ModuleID: moduleID, Description: "module is not covered by component_rules"})
		}
	}
	for _, edge := range architecture.Graph.Edges {
		for _, rule := range config.ForbiddenDependencyRules {
			if matchesAny(edge.From, rule.From) && matchesAny(edge.To, rule.To) && !ruleAllowsEdge(edge, rule) {
				violations = append(violations, Violation{Kind: "forbidden_dependency", Rule: rule.Name, Description: rule.Description, From: edge.From, To: edge.To})
			}
		}
	}
	currentCycles := currentCycleKeys(architecture.Graph)
	for _, key := range sortedKeys(currentCycles) {
		violations = append(violations, Violation{Kind: "unexpected_cycle", Cycle: copyStrings(currentCycles[key]), Description: "module-level circular dependency detected"})
	}
	cycleList := [][]string{}
	for _, key := range sortedKeys(currentCycles) {
		cycleList = append(cycleList, copyStrings(currentCycles[key]))
	}
	for _, entry := range architecture.ProjectionCycles {
		violations = append(violations, Violation{Kind: "projection_cycle", View: entry.View, FeedbackEdges: entry.FeedbackEdges, Description: "projection-level circular dependency detected"})
	}
	return CheckResult{OK: len(violations) == 0, Violations: violations, Cycles: cycleList, ProjectionCycles: architecture.ProjectionCycles}
}
