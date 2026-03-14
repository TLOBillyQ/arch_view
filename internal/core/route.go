package core

import (
	"math"
	"sort"
	"strconv"
)

const (
	sameLayerLaneStep        = 30.0
	crossLayerLaneStep       = 22.0
	nodePortStep             = 24.0
	nodeEdgeGap              = 14.0
	centerExclusionHalfWidth = 20.0
)

type routeIndexInfo struct {
	Index    int
	Count    int
	GroupKey string
}

func copyPoint(point []float64) []float64 {
	return []float64{point[0], point[1]}
}

func buildIndexMap(edgeGroups map[string][]map[string]string) map[string]routeIndexInfo {
	result := map[string]routeIndexInfo{}
	for groupKey, edges := range edgeGroups {
		sort.Slice(edges, func(i, j int) bool {
			if edges[i]["sort_key"] == edges[j]["sort_key"] {
				return edges[i]["id"] < edges[j]["id"]
			}
			return edges[i]["sort_key"] < edges[j]["sort_key"]
		})
		count := len(edges)
		for index, entry := range edges {
			result[entry["id"]] = routeIndexInfo{Index: index + 1, Count: count, GroupKey: groupKey}
		}
	}
	return result
}

type routeBuckets struct {
	Outgoing map[string]routeIndexInfo
	Incoming map[string]routeIndexInfo
	Lanes    map[string]routeIndexInfo
}

func bucketize(edges []GroupedEdge) routeBuckets {
	outgoing := map[string][]map[string]string{}
	incoming := map[string][]map[string]string{}
	laneGroups := map[string][]map[string]string{}
	for _, edge := range edges {
		outgoing[edge.From] = append(outgoing[edge.From], map[string]string{"id": edge.ID, "sort_key": edge.To})
		incoming[edge.To] = append(incoming[edge.To], map[string]string{"id": edge.ID, "sort_key": edge.From})
		laneKey := strconv.Itoa(edge.FromLayer) + "->" + strconv.Itoa(edge.ToLayer)
		laneGroups[laneKey] = append(laneGroups[laneKey], map[string]string{"id": edge.ID, "sort_key": edge.From + "->" + edge.To})
	}
	return routeBuckets{
		Outgoing: buildIndexMap(outgoing),
		Incoming: buildIndexMap(incoming),
		Lanes:    buildIndexMap(laneGroups),
	}
}

func portOffset(indexInfo routeIndexInfo, ok bool) float64 {
	if !ok {
		return 0.0
	}
	count := indexInfo.Count
	offset := (float64(indexInfo.Index) - float64(count+1)/2.0) * nodePortStep
	if count > 1 && math.Abs(offset) < 0.001 {
		return nodePortStep * 0.5
	}
	return offset
}

func laneOffset(indexInfo routeIndexInfo, ok bool, sameLayer bool) float64 {
	if !ok {
		return 0.0
	}
	step := crossLayerLaneStep
	if sameLayer {
		step = sameLayerLaneStep
	}
	return float64(indexInfo.Index-1) * step
}

func nodeCenterX(rect *Rect) float64 { return rect.X + rect.Width/2.0 }
func nodeCenterY(rect *Rect) float64 { return rect.Y + rect.Height/2.0 }

func edgeHorizontalBias(edge GroupedEdge, indexInfo routeIndexInfo, ok bool) float64 {
	fromCenter := nodeCenterX(edge.FromRect)
	toCenter := nodeCenterX(edge.ToRect)
	if toCenter > fromCenter {
		return 1.0
	}
	if toCenter < fromCenter {
		return -1.0
	}
	if ok && float64(indexInfo.Index) <= float64(indexInfo.Count)/2.0 {
		return -1.0
	}
	return 1.0
}

func clamp(value, minimum, maximum float64) float64 {
	if value < minimum {
		return minimum
	}
	if value > maximum {
		return maximum
	}
	return value
}

func signed(value float64) float64 {
	if value < 0 {
		return -1.0
	}
	return 1.0
}

func crossLayerPortOffset(rect *Rect, rawOffset, preferredDirection float64) float64 {
	maxOffset := math.Max(0.0, rect.Width/2.0-nodeEdgeGap-6.0)
	offset := clamp(rawOffset, -maxOffset, maxOffset)
	minimumOffset := math.Min(maxOffset, centerExclusionHalfWidth)
	if minimumOffset > 0.0 && math.Abs(offset) < minimumOffset {
		direction := preferredDirection
		if math.Abs(offset) >= 0.001 {
			direction = offset
		}
		offset = signed(direction) * minimumOffset
	}
	return offset
}

func topPort(rect *Rect, rawOffset, preferredDirection float64) (float64, float64) {
	offset := crossLayerPortOffset(rect, rawOffset, preferredDirection)
	return nodeCenterX(rect) + offset, rect.Y - nodeEdgeGap
}

func bottomPort(rect *Rect, rawOffset, preferredDirection float64) (float64, float64) {
	offset := crossLayerPortOffset(rect, rawOffset, preferredDirection)
	return nodeCenterX(rect) + offset, rect.Y + rect.Height + nodeEdgeGap
}

func leftPort(rect *Rect, rawOffset float64) (float64, float64) {
	maxOffset := math.Max(0.0, rect.Height/2.0-nodeEdgeGap-6.0)
	offset := clamp(rawOffset, -maxOffset, maxOffset)
	return rect.X - nodeEdgeGap, nodeCenterY(rect) + offset
}

func rightPort(rect *Rect, rawOffset float64) (float64, float64) {
	maxOffset := math.Max(0.0, rect.Height/2.0-nodeEdgeGap-6.0)
	offset := clamp(rawOffset, -maxOffset, maxOffset)
	return rect.X + rect.Width + nodeEdgeGap, nodeCenterY(rect) + offset
}

func routeSameLayer(edge GroupedEdge, buckets routeBuckets) [][]float64 {
	fromInfo, hasFrom := buckets.Outgoing[edge.ID]
	toInfo, hasTo := buckets.Incoming[edge.ID]
	laneInfo, hasLane := buckets.Lanes[edge.ID]
	fromOffset := portOffset(fromInfo, hasFrom)
	toOffset := portOffset(toInfo, hasTo)
	lane := laneOffset(laneInfo, hasLane, true)
	var fromX, fromY, toX, toY, laneX float64
	if nodeCenterX(edge.ToRect) >= nodeCenterX(edge.FromRect) {
		fromX, fromY = rightPort(edge.FromRect, fromOffset)
		toX, toY = leftPort(edge.ToRect, toOffset)
		laneX = ((fromX + toX) / 2.0) + lane
	} else {
		fromX, fromY = leftPort(edge.FromRect, fromOffset)
		toX, toY = rightPort(edge.ToRect, toOffset)
		laneX = ((fromX + toX) / 2.0) - lane
	}
	return [][]float64{{fromX, fromY}, {laneX, fromY}, {laneX, toY}, {toX, toY}}
}

func routeCrossLayer(edge GroupedEdge, buckets routeBuckets) [][]float64 {
	fromInfo, hasFrom := buckets.Outgoing[edge.ID]
	toInfo, hasTo := buckets.Incoming[edge.ID]
	laneInfo, hasLane := buckets.Lanes[edge.ID]
	fromOffset := portOffset(fromInfo, hasFrom)
	toOffset := portOffset(toInfo, hasTo)
	lane := laneOffset(laneInfo, hasLane, false)
	hBias := edgeHorizontalBias(edge, fromInfo, hasFrom)
	var startX, startY, endX, endY float64
	if edge.ToLayer > edge.FromLayer {
		startX, startY = bottomPort(edge.FromRect, fromOffset, hBias)
		endX, endY = topPort(edge.ToRect, toOffset, hBias)
	} else {
		startX, startY = topPort(edge.FromRect, fromOffset, hBias)
		endX, endY = bottomPort(edge.ToRect, toOffset, hBias)
	}
	laneY := ((startY + endY) / 2.0) + lane
	return [][]float64{{startX, startY}, {startX, laneY}, {endX, laneY}, {endX, endY}}
}

func RouteEdges(edges []GroupedEdge) []GroupedEdge {
	buckets := bucketize(edges)
	routed := make([]GroupedEdge, 0, len(edges))
	for _, edge := range edges {
		points := routeCrossLayer(edge, buckets)
		if edge.FromLayer == edge.ToLayer {
			points = routeSameLayer(edge, buckets)
		}
		copied := make([][]float64, len(points))
		for i, point := range points {
			copied[i] = copyPoint(point)
		}
		next := edge
		next.RoutePoints = copied
		routed = append(routed, next)
	}
	return routed
}
