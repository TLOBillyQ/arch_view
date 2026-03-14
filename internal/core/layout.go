package core

import (
	"sort"
	"strings"
)

func normalizeEdges(nodes []string, edges []Edge) []Edge {
	nodeSet := listToSet(nodes)
	normalizedMap := map[string]Edge{}
	for _, edge := range edges {
		if edge.From != "" && edge.To != "" && nodeSet[edge.From] && nodeSet[edge.To] {
			normalizedMap[edgeKey(edge.From, edge.To)] = Edge{From: edge.From, To: edge.To}
		}
	}
	return sortedEdges(normalizedMap)
}

func outgoingMap(nodes []string, edges []Edge) map[string]map[string]bool {
	outgoing := map[string]map[string]bool{}
	for _, node := range nodes {
		outgoing[node] = map[string]bool{}
	}
	for _, edge := range edges {
		if outgoing[edge.From] == nil {
			outgoing[edge.From] = map[string]bool{}
		}
		outgoing[edge.From][edge.To] = true
	}
	return outgoing
}

func incomingMap(nodes []string, edges []Edge) map[string]map[string]bool {
	incoming := map[string]map[string]bool{}
	for _, node := range nodes {
		incoming[node] = map[string]bool{}
	}
	for _, edge := range edges {
		if incoming[edge.To] == nil {
			incoming[edge.To] = map[string]bool{}
		}
		incoming[edge.To][edge.From] = true
	}
	return incoming
}

func indegreeMap(nodes []string, edges []Edge) map[string]int {
	indegree := map[string]int{}
	for _, node := range nodes {
		indegree[node] = 0
	}
	for _, edge := range edges {
		indegree[edge.To] = indegree[edge.To] + 1
	}
	return indegree
}

func sortedZeroIndegree(indegree map[string]int) []string {
	available := []string{}
	for _, node := range sortedKeys(indegree) {
		if indegree[node] == 0 {
			available = append(available, node)
		}
	}
	return available
}

func topologicalOrder(nodes []string, edges []Edge) []string {
	outgoing := outgoingMap(nodes, edges)
	indegree := indegreeMap(nodes, edges)
	queue := sortedZeroIndegree(indegree)
	ordered := []string{}
	for len(queue) > 0 {
		node := queue[0]
		queue = queue[1:]
		ordered = append(ordered, node)
		nextNodes := sortedKeys(outgoing[node])
		for _, dep := range nextNodes {
			nextCount := indegree[dep] - 1
			indegree[dep] = nextCount
			if nextCount == 0 {
				queue = append(queue, dep)
				sort.Strings(queue)
			}
		}
	}
	return ordered
}

func isDAG(nodes []string, edges []Edge) bool {
	return len(nodes) == len(topologicalOrder(nodes, edges))
}

func stronglyConnectedComponents(nodes []string, edges []Edge) [][]string {
	outgoing := outgoingMap(nodes, edges)
	index := 0
	stack := []string{}
	onStack := map[string]bool{}
	indices := map[string]int{}
	lowLink := map[string]int{}
	components := [][]string{}

	var strongConnect func(string)
	strongConnect = func(node string) {
		index++
		indices[node] = index
		lowLink[node] = index
		stack = append(stack, node)
		onStack[node] = true

		for _, nextNode := range sortedKeys(outgoing[node]) {
			if indices[nextNode] == 0 {
				strongConnect(nextNode)
				if lowLink[nextNode] < lowLink[node] {
					lowLink[node] = lowLink[nextNode]
				}
			} else if onStack[nextNode] && indices[nextNode] < lowLink[node] {
				lowLink[node] = indices[nextNode]
			}
		}

		if lowLink[node] == indices[node] {
			component := []string{}
			for {
				popped := stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				onStack[popped] = false
				component = append(component, popped)
				if popped == node {
					break
				}
			}
			sort.Strings(component)
			components = append(components, component)
		}
	}

	for _, node := range nodes {
		if indices[node] == 0 {
			strongConnect(node)
		}
	}

	sort.Slice(components, func(i, j int) bool {
		return strings.Join(components[i], "|") < strings.Join(components[j], "|")
	})
	return components
}

func selfLoop(component []string, edges []Edge) bool {
	memberSet := listToSet(component)
	for _, edge := range edges {
		if edge.From == edge.To && memberSet[edge.From] {
			return true
		}
	}
	return false
}

func cyclicComponent(component []string, edges []Edge) bool {
	return len(component) > 1 || selfLoop(component, edges)
}

func exactFeedbackEdges(nodes []string, edges []Edge) []Edge {
	edgeValues := append([]Edge{}, edges...)
	for removeCount := 0; removeCount <= len(edgeValues); removeCount++ {
		indices := make([]int, removeCount)
		var choose func(start, depth int) []Edge
		choose = func(start, depth int) []Edge {
			if depth == removeCount {
				removed := map[int]bool{}
				for _, index := range indices {
					removed[index] = true
				}
				remaining := []Edge{}
				subset := []Edge{}
				for index, edge := range edgeValues {
					if removed[index] {
						subset = append(subset, edge)
					} else {
						remaining = append(remaining, edge)
					}
				}
				if isDAG(nodes, remaining) {
					return subset
				}
				return nil
			}
			for i := start; i < len(edgeValues); i++ {
				indices[depth] = i
				if result := choose(i+1, depth+1); result != nil {
					return result
				}
			}
			return nil
		}
		if result := choose(0, 0); result != nil {
			return result
		}
	}
	return []Edge{}
}

func removeNode(edges []Edge, node string) []Edge {
	remaining := []Edge{}
	for _, edge := range edges {
		if edge.From != node && edge.To != node {
			remaining = append(remaining, edge)
		}
	}
	return remaining
}

func greedyOrder(nodes []string, edges []Edge) []string {
	remaining := map[string]bool{}
	for _, node := range nodes {
		remaining[node] = true
	}
	activeEdges := append([]Edge{}, edges...)
	left := []string{}
	right := []string{}
	remainingNodes := func() []string { return sortedKeys(remaining) }

	for len(remaining) > 0 {
		currentNodes := remainingNodes()
		incoming := incomingMap(currentNodes, activeEdges)
		outgoing := outgoingMap(currentNodes, activeEdges)
		sources := []string{}
		sinks := []string{}
		for _, node := range currentNodes {
			if len(incoming[node]) == 0 {
				sources = append(sources, node)
			}
			if len(outgoing[node]) == 0 {
				sinks = append(sinks, node)
			}
		}
		if len(sources) > 0 {
			node := sources[0]
			delete(remaining, node)
			activeEdges = removeNode(activeEdges, node)
			left = append(left, node)
		} else if len(sinks) > 0 {
			node := sinks[0]
			delete(remaining, node)
			activeEdges = removeNode(activeEdges, node)
			right = append(right, node)
		} else {
			sort.Slice(currentNodes, func(i, j int) bool {
				leftScore := len(sortedKeys(outgoing[currentNodes[i]])) - len(sortedKeys(incoming[currentNodes[i]]))
				rightScore := len(sortedKeys(outgoing[currentNodes[j]])) - len(sortedKeys(incoming[currentNodes[j]]))
				if leftScore == rightScore {
					return currentNodes[i] < currentNodes[j]
				}
				return leftScore < rightScore
			})
			node := currentNodes[len(currentNodes)-1]
			delete(remaining, node)
			activeEdges = removeNode(activeEdges, node)
			left = append(left, node)
		}
	}
	ordered := append([]string{}, left...)
	for index := len(right) - 1; index >= 0; index-- {
		ordered = append(ordered, right[index])
	}
	return ordered
}

func heuristicFeedbackEdges(nodes []string, edges []Edge) []Edge {
	order := greedyOrder(nodes, edges)
	indexByNode := map[string]int{}
	for index, node := range order {
		indexByNode[node] = index + 1
	}
	feedback := []Edge{}
	for _, edge := range edges {
		if indexByNode[edge.From] >= indexByNode[edge.To] {
			feedback = append(feedback, edge)
		}
	}
	return feedback
}

func componentInternalEdges(component []string, edges []Edge) []Edge {
	memberSet := listToSet(component)
	internal := []Edge{}
	for _, edge := range edges {
		if memberSet[edge.From] && memberSet[edge.To] {
			internal = append(internal, edge)
		}
	}
	return internal
}

func componentFeedbackEdges(component []string, edges []Edge) []Edge {
	internal := componentInternalEdges(component, edges)
	if !cyclicComponent(component, internal) {
		return []Edge{}
	}
	if len(component) <= 8 && len(internal) <= 12 {
		return exactFeedbackEdges(component, internal)
	}
	return heuristicFeedbackEdges(component, internal)
}

func feedbackEdgeList(nodes []string, edges []Edge) []Edge {
	components := stronglyConnectedComponents(nodes, edges)
	feedbackMap := map[string]Edge{}
	for _, component := range components {
		feedback := componentFeedbackEdges(component, edges)
		for _, edge := range feedback {
			feedbackMap[edgeKey(edge.From, edge.To)] = Edge{From: edge.From, To: edge.To}
		}
	}
	return sortedEdges(feedbackMap)
}

func topologicalLevels(nodes []string, edges []Edge) map[string]int {
	outgoing := outgoingMap(nodes, edges)
	incoming := incomingMap(nodes, edges)
	indegree := indegreeMap(nodes, edges)
	queue := sortedZeroIndegree(indegree)
	levels := map[string]int{}
	for _, node := range nodes {
		levels[node] = 1
	}
	for len(queue) > 0 {
		node := queue[0]
		queue = queue[1:]
		nodeLevel := levels[node]
		for _, dep := range sortedKeys(outgoing[node]) {
			nextLevel := nodeLevel + 1
			if nextLevel > levels[dep] {
				levels[dep] = nextLevel
			}
			nextCount := indegree[dep] - 1
			indegree[dep] = nextCount
			if nextCount == 0 {
				queue = append(queue, dep)
				sort.Strings(queue)
			}
		}
		roots := sortedKeys(incoming[node])
		if len(roots) > 0 {
			maxLevel := levels[node]
			for _, rootNode := range roots {
				candidate := levels[rootNode] + 1
				if candidate > maxLevel {
					maxLevel = candidate
				}
			}
			levels[node] = maxLevel
		}
	}
	return levels
}

func FindCycles(graph Graph) [][]string {
	nodes := append([]string{}, graph.Nodes...)
	sort.Strings(nodes)
	edges := normalizeEdges(nodes, graph.Edges)
	cycles := [][]string{}
	for _, component := range stronglyConnectedComponents(nodes, edges) {
		if cyclicComponent(component, edges) {
			cycles = append(cycles, component)
		}
	}
	return cycles
}

func AssignLayers(graph Graph) Layout {
	nodes := append([]string{}, graph.Nodes...)
	sort.Strings(nodes)
	edges := normalizeEdges(nodes, graph.Edges)
	feedbackEdges := feedbackEdgeList(nodes, edges)
	feedbackSet := map[string]bool{}
	for _, edge := range feedbackEdges {
		feedbackSet[edgeKey(edge.From, edge.To)] = true
	}
	acyclicEdges := []Edge{}
	for _, edge := range edges {
		if !feedbackSet[edgeKey(edge.From, edge.To)] {
			acyclicEdges = append(acyclicEdges, edge)
		}
	}
	moduleToLevel := topologicalLevels(nodes, acyclicEdges)
	moduleToLayer := map[string]int{}
	layerGroups := map[int][]string{}
	for _, node := range nodes {
		layerIndex := moduleToLevel[node] - 1
		moduleToLayer[node] = layerIndex
		layerGroups[layerIndex] = append(layerGroups[layerIndex], node)
	}
	groupedLayers := []LayerGroup{}
	layerIndices := make([]int, 0, len(layerGroups))
	for index := range layerGroups {
		layerIndices = append(layerIndices, index)
	}
	sort.Ints(layerIndices)
	for _, layerIndex := range layerIndices {
		sort.Strings(layerGroups[layerIndex])
		groupedLayers = append(groupedLayers, LayerGroup{Index: layerIndex, Modules: layerGroups[layerIndex]})
	}
	return Layout{
		Layers:        groupedLayers,
		ModuleToLayer: moduleToLayer,
		ModuleToLevel: moduleToLevel,
		FeedbackEdges: feedbackEdges,
		AcyclicEdges:  acyclicEdges,
	}
}
