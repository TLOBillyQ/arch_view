package core

import "math"

const (
	canvasWidth      = 1480.0
	nodeWidth        = 188.0
	nodeHeight       = 60.0
	layerGap         = 220.0
	horizontalGap    = 100.0
	paddingX         = 72.0
	paddingTop       = 100.0
	layerLabelHeight = 28.0
)

func buildLayerRects(childLayout Layout) map[int]Rect {
	layerRects := map[int]Rect{}
	for _, layer := range childLayout.Layers {
		nodeCount := len(layer.Modules)
		totalWidth := float64(nodeCount)*nodeWidth + math.Max(0, float64(nodeCount-1))*horizontalGap
		startX := math.Max(paddingX, (canvasWidth-totalWidth)/2.0)
		layerY := paddingTop + float64(layer.Index)*layerGap
		layerRects[layer.Index] = Rect{X: startX, Y: layerY, Width: totalWidth, Height: nodeHeight}
	}
	return layerRects
}

func BuildNodeRects(childLayout Layout, displayLabels, fullNames map[string]string) (map[string]*Rect, []ViewLayer) {
	nodeRects := map[string]*Rect{}
	layerItems := []ViewLayer{}
	layerRects := buildLayerRects(childLayout)
	for _, layer := range childLayout.Layers {
		layerRect := layerRects[layer.Index]
		nodeIDs := append([]string{}, layer.Modules...)
		nodes := []LayerNode{}
		for index, nodeID := range nodeIDs {
			x := layerRect.X + float64(index)*(nodeWidth+horizontalGap)
			y := layerRect.Y + layerLabelHeight
			rect := &Rect{X: x, Y: y, Width: nodeWidth, Height: nodeHeight}
			nodeRects[nodeID] = rect
			nodes = append(nodes, LayerNode{ID: nodeID, DisplayLabel: displayLabels[nodeID], FullName: fullNames[nodeID], Rect: *rect})
		}
		layerItems = append(layerItems, ViewLayer{
			Index:    layer.Index,
			Label:    "Layer " + intToString(layer.Index),
			FullName: "Layer " + intToString(layer.Index),
			NodeIDs:  nodeIDs,
			Nodes:    nodes,
			Rect:     Rect{X: layerRect.X, Y: layerRect.Y, Width: layerRect.Width, Height: nodeHeight + layerLabelHeight},
		})
	}
	return nodeRects, layerItems
}

func BuildIndicators(nodeItems []ViewNode) []Indicator {
	indicators := []Indicator{}
	for _, node := range nodeItems {
		if len(node.IncomingDependencies) > 0 {
			tooltipLines := []string{}
			tooltip := []TooltipEntry{}
			for _, entry := range node.IncomingDependencies {
				tooltipLines = append(tooltipLines, entry.Text)
				tooltip = append(tooltip, TooltipEntry{Text: entry.Text, Cycle: entry.Cycle, Type: entry.Type})
			}
			indicators = append(indicators, Indicator{ID: node.ID + ":incoming", NodeID: node.ID, Direction: "incoming", Cycle: node.HasCycleSubtree, Count: len(tooltipLines), TooltipLines: tooltipLines, Tooltip: tooltip})
		}
		if len(node.OutgoingDependencies) > 0 {
			tooltipLines := []string{}
			tooltip := []TooltipEntry{}
			for _, entry := range node.OutgoingDependencies {
				tooltipLines = append(tooltipLines, entry.Text)
				tooltip = append(tooltip, TooltipEntry{Text: entry.Text, Cycle: entry.Cycle, Type: entry.Type})
			}
			indicators = append(indicators, Indicator{ID: node.ID + ":outgoing", NodeID: node.ID, Direction: "outgoing", Cycle: node.HasCycleSubtree, Count: len(tooltipLines), TooltipLines: tooltipLines, Tooltip: tooltip})
		}
	}
	return indicators
}

func DecorateDisplayEdges(displayEdges []GroupedEdge, nodeRects map[string]*Rect, nodeLayerMap map[string]int, childFeedbackSet map[string]bool) []GroupedEdge {
	routeInput := make([]GroupedEdge, 0, len(displayEdges))
	for _, edge := range displayEdges {
		next := edge
		next.ModuleEdges = append([]ModuleEdgeTooltip{}, edge.ModuleEdges...)
		next.Tooltip = append([]TooltipEntry{}, edge.Tooltip...)
		next.TooltipLines = append([]string{}, edge.TooltipLines...)
		next.Feedback = childFeedbackSet[edgeKey(edge.From, edge.To)]
		next.FromRect = nodeRects[edge.From]
		next.ToRect = nodeRects[edge.To]
		next.FromLayer = nodeLayerMap[edge.From]
		next.ToLayer = nodeLayerMap[edge.To]
		next.ID = edge.From + "->" + edge.To
		routeInput = append(routeInput, next)
	}
	routed := RouteEdges(routeInput)
	for index := range routed {
		routed[index].Cycle = routed[index].Feedback
		if !routed[index].Cycle {
			for _, moduleEdge := range routed[index].ModuleEdges {
				if moduleEdge.Cycle {
					routed[index].Cycle = true
					break
				}
			}
		}
	}
	return routed
}

func CanvasSize(layerItems []ViewLayer) Canvas {
	return Canvas{Width: canvasWidth, Height: paddingTop + math.Max(1, float64(len(layerItems)))*layerGap + nodeHeight + 120.0}
}
