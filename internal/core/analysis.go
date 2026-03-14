package core

import "fmt"

func ValidateConfig(config Config) error {
	if len(config.SourceRoots) == 0 {
		return fmt.Errorf("source_roots must be an array")
	}
	for index, value := range config.SourceRoots {
		if value == "" {
			return fmt.Errorf("source_roots[%d] must be a non-empty string", index+1)
		}
	}
	return nil
}

func Analyze(request AnalyzeRequest) (*Architecture, error) {
	if err := ValidateConfig(request.Config); err != nil {
		return nil, err
	}
	graph, modules, layout, classifiedEdges, err := analyzeCore(request)
	if err != nil {
		return nil, err
	}
	architecture := &Architecture{
		Graph:           graph,
		Modules:         modules,
		Layout:          layout,
		ClassifiedEdges: classifiedEdges,
		SchemaVersion:   1,
		ProjectRoot:     normalizePath(request.ProjectRoot),
		ConfigPath:      normalizePath(request.ConfigPath),
	}
	architecture.Views = BuildViews(architecture)
	architecture.ProjectionCycles = CollectProjectionCycles(architecture.Views)
	architecture.Check = RunCheck(architecture, request.Config)
	return architecture, nil
}

func Check(request AnalyzeRequest) (CheckResult, error) {
	architecture, err := Analyze(request)
	if err != nil {
		return CheckResult{}, err
	}
	return architecture.Check, nil
}

func analyzeCore(request AnalyzeRequest) (Graph, map[string]*Module, Layout, []ClassifiedEdge, error) {
	scanResult, err := Scan(request.Config, request.ProjectRoot)
	if err != nil {
		return Graph{}, nil, Layout{}, nil, err
	}
	graph, extractedModules := Extract(scanResult)
	classifiedModules := ClassifyModules(extractedModules, request.Config)
	layout := AssignLayers(graph)
	classifiedEdges := ClassifyEdges(graph, classifiedModules)
	return graph, classifiedModules, layout, classifiedEdges, nil
}
