package archcore

import "sort"

type childInfo struct {
	ExactModule       string
	DescendantModules map[string]bool
}

func collectScopedModules(modules map[string]*Module, prefixSegments []string) map[string]*Module {
	scoped := map[string]*Module{}
	for _, moduleID := range sortedKeys(modules) {
		moduleInfo := modules[moduleID]
		if startsWithSegments(moduleInfo.NamespaceSegments, prefixSegments) && len(moduleInfo.NamespaceSegments) > len(prefixSegments) {
			scoped[moduleID] = moduleInfo
		}
	}
	return scoped
}

func moduleToChild(scopedModules map[string]*Module, prefixSegments []string) map[string]string {
	result := map[string]string{}
	for moduleID, moduleInfo := range scopedModules {
		result[moduleID] = moduleInfo.NamespaceSegments[len(prefixSegments)]
	}
	return result
}

func childToInfo(scopedModules map[string]*Module, prefixSegments []string, moduleChildMap map[string]string) map[string]*childInfo {
	childInfoMap := map[string]*childInfo{}
	for moduleID, moduleInfo := range scopedModules {
		childName := moduleChildMap[moduleID]
		info := childInfoMap[childName]
		if info == nil {
			info = &childInfo{DescendantModules: map[string]bool{}}
		}
		if len(moduleInfo.NamespaceSegments) == len(prefixSegments)+1 {
			info.ExactModule = moduleID
		} else {
			info.DescendantModules[moduleID] = true
		}
		childInfoMap[childName] = info
	}
	return childInfoMap
}

func moduleToNode(childInfoMap map[string]*childInfo) map[string]string {
	moduleNodeMap := map[string]string{}
	for _, childName := range sortedKeys(childInfoMap) {
		info := childInfoMap[childName]
		if info.ExactModule != "" {
			moduleNodeMap[info.ExactModule] = childName
		}
		for _, moduleID := range sortedKeys(info.DescendantModules) {
			moduleNodeMap[moduleID] = childName
		}
	}
	return moduleNodeMap
}

func nodeToModules(moduleNodeMap map[string]string) map[string][]string {
	nodeModules := map[string][]string{}
	for _, moduleID := range sortedKeys(moduleNodeMap) {
		nodeID := moduleNodeMap[moduleID]
		nodeModules[nodeID] = append(nodeModules[nodeID], moduleID)
	}
	for nodeID := range nodeModules {
		sort.Strings(nodeModules[nodeID])
	}
	return nodeModules
}

func nodeComponent(modules map[string]*Module, moduleIDs []string) string {
	componentName := ""
	for _, moduleID := range moduleIDs {
		nextComponent := modules[moduleID].Component
		if componentName == "" {
			componentName = nextComponent
		} else if componentName != nextComponent {
			return "mixed"
		}
	}
	return componentName
}

func nodeAbstract(modules map[string]*Module, moduleIDs []string) bool {
	for _, moduleID := range moduleIDs {
		if modules[moduleID].Abstract {
			return true
		}
	}
	return false
}

func moduleFeedbackSet(layout Layout) map[string]bool {
	involved := map[string]bool{}
	for _, edge := range layout.FeedbackEdges {
		involved[edge.From] = true
		involved[edge.To] = true
	}
	return involved
}

func buildBreadcrumb(prefixSegments []string) []Breadcrumb {
	breadcrumb := []Breadcrumb{{Key: "root", Label: "src"}}
	current := []string{}
	for _, segment := range prefixSegments {
		current = append(current, segment)
		breadcrumb = append(breadcrumb, Breadcrumb{Key: viewKey(current), Label: segment})
	}
	return breadcrumb
}

func displayLabelForNode(nodeID string, childInfoMap map[string]*childInfo, modules map[string]*Module) string {
	info := childInfoMap[nodeID]
	if info != nil && info.ExactModule != "" && len(info.DescendantModules) == 0 {
		sourceFileName := sourceFilenameBase(modules[info.ExactModule].SourcePath)
		if sourceFileName != "" {
			return sourceFileName
		}
	}
	return nodeID
}

func fullNameForNode(nodeID string, prefixSegments []string, childInfoMap map[string]*childInfo) string {
	info := childInfoMap[nodeID]
	if info != nil && info.ExactModule != "" && len(info.DescendantModules) == 0 {
		return stripSrcPrefix(info.ExactModule)
	}
	fullName := append(copyStrings(prefixSegments), nodeID)
	return joinStrings(fullName, ".")
}

type groupedPair struct {
	From        string
	To          string
	Type        string
	Count       int
	ModuleEdges []ModuleEdgeTooltip
}

type internalEdgeEntry struct {
	From       string
	To         string
	ModuleFrom string
	ModuleTo   string
	Type       string
	Cycle      bool
	Text       string
}

func buildPairMap(entries []internalEdgeEntry) map[string]*groupedPair {
	pairMap := map[string]*groupedPair{}
	for _, entry := range entries {
		key := edgeKey(entry.From, entry.To)
		existing := pairMap[key]
		if existing == nil {
			existing = &groupedPair{From: entry.From, To: entry.To, Type: entry.Type}
			pairMap[key] = existing
		}
		existing.Count++
		if entry.Type == "abstract" {
			existing.Type = "abstract"
		}
		existing.ModuleEdges = append(existing.ModuleEdges, ModuleEdgeTooltip{
			From:  entry.ModuleFrom,
			To:    entry.ModuleTo,
			Type:  entry.Type,
			Cycle: entry.Cycle,
			Text:  entry.Text,
		})
	}
	return pairMap
}

func appendSortedEntries(edge *groupedPair) GroupedEdge {
	sort.Slice(edge.ModuleEdges, func(i, j int) bool {
		if edge.ModuleEdges[i].From == edge.ModuleEdges[j].From {
			if edge.ModuleEdges[i].To == edge.ModuleEdges[j].To {
				return edge.ModuleEdges[i].Type < edge.ModuleEdges[j].Type
			}
			return edge.ModuleEdges[i].To < edge.ModuleEdges[j].To
		}
		return edge.ModuleEdges[i].From < edge.ModuleEdges[j].From
	})
	tooltipLines := []string{}
	tooltip := []TooltipEntry{}
	for _, moduleEdge := range edge.ModuleEdges {
		text := moduleEdge.Text + " (1)"
		tooltipLines = append(tooltipLines, text)
		tooltip = append(tooltip, TooltipEntry{Text: text, Cycle: moduleEdge.Cycle, Type: moduleEdge.Type})
	}
	return GroupedEdge{From: edge.From, To: edge.To, Type: edge.Type, Count: edge.Count, ModuleEdges: edge.ModuleEdges, TooltipLines: tooltipLines, Tooltip: tooltip, Arrowhead: map[bool]string{true: "closed-triangle", false: "standard"}[edge.Type == "abstract"]}
}

type edgeMaps struct {
	ClassifiedEdges []GroupedEdge
	CycleEdges      []Edge
	DisplayEdges    []GroupedEdge
	OutgoingByNode  map[string][]DependencyEntry
	IncomingByNode  map[string][]DependencyEntry
}

func buildEdgeMaps(architecture *Architecture, scopedModules map[string]*Module, moduleNodeMap map[string]string, moduleFeedback map[string]bool) edgeMaps {
	internalEntries := []internalEdgeEntry{}
	cycleEntries := []internalEdgeEntry{}
	outgoingByNode := map[string][]DependencyEntry{}
	incomingByNode := map[string][]DependencyEntry{}
	for _, edge := range architecture.ClassifiedEdges {
		fromIn := scopedModules[edge.From] != nil
		toIn := scopedModules[edge.To] != nil
		if !(fromIn || toIn) {
			continue
		}
		fromNode := ""
		toNode := ""
		if fromIn {
			fromNode = moduleNodeMap[edge.From]
		}
		if toIn {
			toNode = moduleNodeMap[edge.To]
		}
		text := stripSrcPrefix(edge.From) + " -> " + stripSrcPrefix(edge.To)
		cycle := moduleFeedback[edge.From] || moduleFeedback[edge.To]
		if fromNode != "" && toNode != "" && fromNode != toNode {
			entry := internalEdgeEntry{From: fromNode, To: toNode, ModuleFrom: edge.From, ModuleTo: edge.To, Type: edge.Type, Cycle: cycle, Text: text}
			internalEntries = append(internalEntries, entry)
			if edge.Type != "abstract" {
				cycleEntries = append(cycleEntries, entry)
			}
		}
		if fromNode != "" {
			outgoingByNode[fromNode] = append(outgoingByNode[fromNode], DependencyEntry{Direction: "outgoing", From: edge.From, To: edge.To, Text: text + " (1)", Type: edge.Type, Cycle: cycle})
		}
		if toNode != "" {
			incomingByNode[toNode] = append(incomingByNode[toNode], DependencyEntry{Direction: "incoming", From: edge.From, To: edge.To, Text: text + " (1)", Type: edge.Type, Cycle: cycle})
		}
	}
	pairMap := buildPairMap(internalEntries)
	cyclePairMap := buildPairMap(cycleEntries)
	classifiedEdges := []GroupedEdge{}
	for _, key := range sortedKeys(pairMap) {
		classifiedEdges = append(classifiedEdges, appendSortedEntries(pairMap[key]))
	}
	cycleEdgeList := []Edge{}
	for _, key := range sortedKeys(cyclePairMap) {
		edge := cyclePairMap[key]
		cycleEdgeList = append(cycleEdgeList, Edge{From: edge.From, To: edge.To})
	}
	sort.Slice(classifiedEdges, func(i, j int) bool {
		if classifiedEdges[i].From == classifiedEdges[j].From {
			return classifiedEdges[i].To < classifiedEdges[j].To
		}
		return classifiedEdges[i].From < classifiedEdges[j].From
	})
	for nodeID := range outgoingByNode {
		sort.Slice(outgoingByNode[nodeID], func(i, j int) bool {
			if outgoingByNode[nodeID][i].To == outgoingByNode[nodeID][j].To {
				return outgoingByNode[nodeID][i].From < outgoingByNode[nodeID][j].From
			}
			return outgoingByNode[nodeID][i].To < outgoingByNode[nodeID][j].To
		})
	}
	for nodeID := range incomingByNode {
		sort.Slice(incomingByNode[nodeID], func(i, j int) bool {
			if incomingByNode[nodeID][i].From == incomingByNode[nodeID][j].From {
				return incomingByNode[nodeID][i].To < incomingByNode[nodeID][j].To
			}
			return incomingByNode[nodeID][i].From < incomingByNode[nodeID][j].From
		})
	}
	return edgeMaps{ClassifiedEdges: classifiedEdges, CycleEdges: cycleEdgeList, DisplayEdges: append([]GroupedEdge{}, classifiedEdges...), OutgoingByNode: outgoingByNode, IncomingByNode: incomingByNode}
}

func buildChildFeedbackSet(childLayout Layout) map[string]bool {
	childFeedbackSet := map[string]bool{}
	for _, edge := range childLayout.FeedbackEdges {
		childFeedbackSet[edgeKey(edge.From, edge.To)] = true
	}
	return childFeedbackSet
}

func subtreeCycleMap(childInfoMap map[string]*childInfo, prefixSegments []string, nestedViews map[string]*View) map[string]bool {
	result := map[string]bool{}
	for _, childName := range sortedKeys(childInfoMap) {
		info := childInfoMap[childName]
		hasCycle := false
		if !(info.ExactModule != "" && len(info.DescendantModules) == 0) {
			childPrefix := append(copyStrings(prefixSegments), childName)
			childView := nestedViews[viewKey(childPrefix)]
			if childView != nil {
				for _, node := range childView.Nodes {
					if node.Cycle || node.HasCycleSubtree {
						hasCycle = true
						break
					}
				}
				if !hasCycle {
					for _, edge := range childView.DisplayEdges {
						if edge.Cycle {
							hasCycle = true
							break
						}
					}
				}
			}
		}
		result[childName] = hasCycle
	}
	return result
}

func buildView(architecture *Architecture, prefixSegments []string) map[string]*View {
	scopedModules := collectScopedModules(architecture.Modules, prefixSegments)
	moduleChildMap := moduleToChild(scopedModules, prefixSegments)
	childInfoMap := childToInfo(scopedModules, prefixSegments, moduleChildMap)
	moduleNodeMap := moduleToNode(childInfoMap)
	nodeModules := nodeToModules(moduleNodeMap)
	childNodes := sortedKeys(nodeModules)
	childGraph := Graph{Nodes: childNodes, Edges: []Edge{}}
	childLayout := AssignLayers(Graph{Nodes: childNodes, Edges: []Edge{}})
	nodeLayerMap := map[string]int{}
	moduleFeedback := moduleFeedbackSet(architecture.Layout)
	displayLabels := map[string]string{}
	fullNames := map[string]string{}
	nodeItems := []ViewNode{}

	edgeMaps := buildEdgeMaps(architecture, scopedModules, moduleNodeMap, moduleFeedback)
	for _, edge := range edgeMaps.CycleEdges {
		childGraph.Edges = append(childGraph.Edges, Edge{From: edge.From, To: edge.To})
	}
	childLayout = AssignLayers(childGraph)
	childFeedbackSet := buildChildFeedbackSet(childLayout)
	nodeLayerMap = childLayout.ModuleToLayer
	for _, nodeID := range sortedKeys(nodeModules) {
		displayLabels[nodeID] = displayLabelForNode(nodeID, childInfoMap, architecture.Modules)
		fullNames[nodeID] = fullNameForNode(nodeID, prefixSegments, childInfoMap)
	}
	nodeRects, layerItems := BuildNodeRects(childLayout, displayLabels, fullNames)
	nestedViews := map[string]*View{}
	for _, childName := range sortedKeys(childInfoMap) {
		info := childInfoMap[childName]
		if len(info.DescendantModules) != 0 {
			childPrefix := append(copyStrings(prefixSegments), childName)
			childViews := buildView(architecture, childPrefix)
			for viewKey, view := range childViews {
				nestedViews[viewKey] = view
			}
		}
	}
	subtreeCycles := subtreeCycleMap(childInfoMap, prefixSegments, nestedViews)
	for _, nodeID := range sortedKeys(nodeModules) {
		moduleIDs := nodeModules[nodeID]
		info := childInfoMap[nodeID]
		exactModule := ""
		hasDescendants := false
		if info != nil {
			exactModule = info.ExactModule
			hasDescendants = len(info.DescendantModules) != 0
		}
		leaf := exactModule != "" && !hasDescendants
		childPrefix := append(copyStrings(prefixSegments), nodeID)
		sourceFileName := ""
		if exactModule != "" {
			sourceFileName = sourceFilenameBase(architecture.Modules[exactModule].SourcePath)
		}
		item := ViewNode{
			ID:                   nodeID,
			Label:                displayLabels[nodeID],
			DisplayLabel:         displayLabels[nodeID],
			FullName:             fullNames[nodeID],
			ChildName:            nodeID,
			SourceFileName:       sourceFileName,
			Layer:                nodeLayerMap[nodeID],
			Leaf:                 leaf,
			Drillable:            hasDescendants,
			Component:            nodeComponent(architecture.Modules, moduleIDs),
			Abstract:             nodeAbstract(architecture.Modules, moduleIDs),
			HasCycleSubtree:      false,
			Cycle:                false,
			ModuleIDs:            append([]string{}, moduleIDs...),
			Rect:                 nodeRects[nodeID],
			IncomingDependencies: append([]DependencyEntry{}, edgeMaps.IncomingByNode[nodeID]...),
			OutgoingDependencies: append([]DependencyEntry{}, edgeMaps.OutgoingByNode[nodeID]...),
		}
		if hasDescendants {
			item.ViewKey = viewKey(childPrefix)
		}
		if childFeedbackSet[edgeKey(nodeID, nodeID)] {
			item.Cycle = true
			item.HasCycleSubtree = true
		}
		if hasDescendants && subtreeCycles[nodeID] {
			item.HasCycleSubtree = true
			item.Cycle = true
		}
		if exactModule != "" {
			moduleInfo := architecture.Modules[exactModule]
			item.ModuleID = exactModule
			item.SourcePath = moduleInfo.SourcePath
			item.SourceText = moduleInfo.SourceText
			item.InternalRequires = append([]string{}, moduleInfo.InternalRequires...)
			item.ExternalRequires = append([]string{}, moduleInfo.ExternalRequires...)
			if moduleFeedback[exactModule] {
				item.Cycle = true
				item.HasCycleSubtree = true
			}
		}
		nodeItems = append(nodeItems, item)
	}
	sort.Slice(nodeItems, func(i, j int) bool {
		if nodeItems[i].Layer == nodeItems[j].Layer {
			return nodeItems[i].DisplayLabel < nodeItems[j].DisplayLabel
		}
		return nodeItems[i].Layer < nodeItems[j].Layer
	})
	displayEdges := DecorateDisplayEdges(edgeMaps.DisplayEdges, nodeRects, nodeLayerMap, childFeedbackSet)
	indicators := BuildIndicators(nodeItems)
	canvas := CanvasSize(layerItems)
	label := "src"
	if len(prefixSegments) > 0 {
		label = prefixSegments[len(prefixSegments)-1]
	}
	currentView := &View{
		Key:             viewKey(prefixSegments),
		Label:           label,
		Title:           label,
		Breadcrumb:      buildBreadcrumb(prefixSegments),
		Canvas:          canvas,
		Layers:          layerItems,
		Nodes:           nodeItems,
		Edges:           displayEdges,
		ClassifiedEdges: edgeMaps.ClassifiedEdges,
		DisplayEdges:    displayEdges,
		Indicators:      indicators,
	}
	views := map[string]*View{viewKey(prefixSegments): currentView}
	for key, view := range nestedViews {
		views[key] = view
	}
	return views
}

func BuildViews(architecture *Architecture) map[string]*View {
	return buildView(architecture, []string{})
}

func CollectProjectionCycles(views map[string]*View) []ProjectionCycleSummary {
	result := []ProjectionCycleSummary{}
	for _, key := range sortedKeys(views) {
		view := views[key]
		feedbackEdges := []ProjectionFeedbackEdge{}
		for _, edge := range view.DisplayEdges {
			if edge.Feedback {
				moduleEdges := []MiniEdge{}
				for _, me := range edge.ModuleEdges {
					moduleEdges = append(moduleEdges, MiniEdge{From: me.From, To: me.To, Type: me.Type})
				}
				feedbackEdges = append(feedbackEdges, ProjectionFeedbackEdge{From: edge.From, To: edge.To, ModuleEdges: moduleEdges})
			}
		}
		if len(feedbackEdges) > 0 {
			result = append(result, ProjectionCycleSummary{View: key, FeedbackEdges: feedbackEdges})
		}
	}
	return result
}
