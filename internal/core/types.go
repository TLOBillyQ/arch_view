package core

type AllowRule struct {
	From []string `json:"from,omitempty"`
	To   []string `json:"to,omitempty"`
}

type Rule struct {
	Name        string      `json:"name,omitempty"`
	Description string      `json:"description,omitempty"`
	Match       []string    `json:"match,omitempty"`
	Component   string      `json:"component,omitempty"`
	From        []string    `json:"from,omitempty"`
	To          []string    `json:"to,omitempty"`
	Allow       []AllowRule `json:"allow,omitempty"`
}

type Config struct {
	SourceRoots              []string `json:"source_roots"`
	ComponentRules           []Rule   `json:"component_rules,omitempty"`
	AbstractRules            []Rule   `json:"abstract_rules,omitempty"`
	ForbiddenDependencyRules []Rule   `json:"forbidden_dependency_rules,omitempty"`
}

type AnalyzeRequest struct {
	ProjectRoot string `json:"project_root"`
	ConfigPath  string `json:"config_path,omitempty"`
	Config      Config `json:"config"`
}

type Edge struct {
	From string `json:"from"`
	To   string `json:"to"`
}

type ScanModule struct {
	ModuleID          string   `json:"module_id"`
	ModuleSegments    []string `json:"module_segments"`
	NamespaceSegments []string `json:"namespace_segments"`
	SourcePath        string   `json:"source_path"`
	SourceText        string   `json:"source_text"`
	Root              string   `json:"root"`
}

type ScanResult struct {
	Modules     map[string]*ScanModule `json:"modules"`
	ModuleIDs   map[string]bool        `json:"module_ids"`
	ModuleList  []string               `json:"module_list"`
	ProjectRoot string                 `json:"project_root"`
}

type Module struct {
	ModuleID          string   `json:"module_id"`
	ModuleSegments    []string `json:"module_segments"`
	NamespaceSegments []string `json:"namespace_segments"`
	SourcePath        string   `json:"source_path"`
	SourceText        string   `json:"source_text"`
	InternalRequires  []string `json:"internal_requires"`
	ExternalRequires  []string `json:"external_requires"`
	Root              string   `json:"root"`
	Component         string   `json:"component,omitempty"`
	Abstract          bool     `json:"abstract"`
}

type Graph struct {
	Nodes []string `json:"nodes"`
	Edges []Edge   `json:"edges"`
}

type LayerGroup struct {
	Index   int      `json:"index"`
	Modules []string `json:"modules"`
}

type Layout struct {
	Layers        []LayerGroup   `json:"layers"`
	ModuleToLayer map[string]int `json:"module_to_layer"`
	ModuleToLevel map[string]int `json:"module_to_level"`
	FeedbackEdges []Edge         `json:"feedback_edges"`
	AcyclicEdges  []Edge         `json:"acyclic_edges"`
}

type ClassifiedEdge struct {
	From string `json:"from"`
	To   string `json:"to"`
	Type string `json:"type"`
}

type ModuleEdgeTooltip struct {
	From  string `json:"from,omitempty"`
	To    string `json:"to,omitempty"`
	Type  string `json:"type,omitempty"`
	Cycle bool   `json:"cycle,omitempty"`
	Text  string `json:"text,omitempty"`
}

type GroupedEdge struct {
	From         string              `json:"from"`
	To           string              `json:"to"`
	Type         string              `json:"type,omitempty"`
	Count        int                 `json:"count,omitempty"`
	ModuleEdges  []ModuleEdgeTooltip `json:"module_edges,omitempty"`
	Tooltip      []TooltipEntry      `json:"tooltip,omitempty"`
	TooltipLines []string            `json:"tooltip_lines,omitempty"`
	Arrowhead    string              `json:"arrowhead,omitempty"`
	Feedback     bool                `json:"feedback,omitempty"`
	Cycle        bool                `json:"cycle,omitempty"`
	FromRect     *Rect               `json:"from_rect,omitempty"`
	ToRect       *Rect               `json:"to_rect,omitempty"`
	FromLayer    int                 `json:"from_layer,omitempty"`
	ToLayer      int                 `json:"to_layer,omitempty"`
	ID           string              `json:"id,omitempty"`
	RoutePoints  [][]float64         `json:"route_points,omitempty"`
}

type Violation struct {
	Kind          string                   `json:"kind"`
	Rule          string                   `json:"rule,omitempty"`
	Description   string                   `json:"description,omitempty"`
	From          string                   `json:"from,omitempty"`
	To            string                   `json:"to,omitempty"`
	ModuleID      string                   `json:"module_id,omitempty"`
	View          string                   `json:"view,omitempty"`
	Cycle         []string                 `json:"cycle,omitempty"`
	FeedbackEdges []ProjectionFeedbackEdge `json:"feedback_edges,omitempty"`
}

type CheckResult struct {
	OK               bool                     `json:"ok"`
	Violations       []Violation              `json:"violations"`
	Cycles           [][]string               `json:"cycles"`
	ProjectionCycles []ProjectionCycleSummary `json:"projection_cycles"`
}

type Breadcrumb struct {
	Key   string `json:"key"`
	Label string `json:"label"`
}

type Rect struct {
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

type LayerNode struct {
	ID           string `json:"id"`
	DisplayLabel string `json:"display_label"`
	FullName     string `json:"full_name"`
	Rect         Rect   `json:"rect"`
}

type ViewLayer struct {
	Index    int         `json:"index"`
	Label    string      `json:"label"`
	FullName string      `json:"full_name"`
	NodeIDs  []string    `json:"node_ids"`
	Nodes    []LayerNode `json:"nodes"`
	Rect     Rect        `json:"rect"`
}

type TooltipEntry struct {
	Text  string `json:"text"`
	Cycle bool   `json:"cycle,omitempty"`
	Type  string `json:"type,omitempty"`
}

type DependencyEntry struct {
	Direction string `json:"direction"`
	From      string `json:"from"`
	To        string `json:"to"`
	Text      string `json:"text"`
	Type      string `json:"type,omitempty"`
	Cycle     bool   `json:"cycle,omitempty"`
}

type Indicator struct {
	ID           string         `json:"id"`
	NodeID       string         `json:"node_id"`
	Direction    string         `json:"direction"`
	Cycle        bool           `json:"cycle,omitempty"`
	Count        int            `json:"count"`
	TooltipLines []string       `json:"tooltip_lines"`
	Tooltip      []TooltipEntry `json:"tooltip"`
}

type ViewNode struct {
	ID                   string            `json:"id"`
	Label                string            `json:"label"`
	DisplayLabel         string            `json:"display_label"`
	FullName             string            `json:"full_name"`
	ChildName            string            `json:"child_name"`
	SourceFileName       string            `json:"source_file_name,omitempty"`
	Layer                int               `json:"layer"`
	Leaf                 bool              `json:"leaf"`
	Drillable            bool              `json:"drillable"`
	Component            string            `json:"component,omitempty"`
	Abstract             bool              `json:"abstract"`
	HasCycleSubtree      bool              `json:"has_cycle_subtree"`
	Cycle                bool              `json:"cycle"`
	ModuleIDs            []string          `json:"module_ids"`
	Rect                 *Rect             `json:"rect,omitempty"`
	ViewKey              string            `json:"view_key,omitempty"`
	IncomingDependencies []DependencyEntry `json:"incoming_dependencies"`
	OutgoingDependencies []DependencyEntry `json:"outgoing_dependencies"`
	ModuleID             string            `json:"module_id,omitempty"`
	SourcePath           string            `json:"source_path,omitempty"`
	SourceText           string            `json:"source_text,omitempty"`
	InternalRequires     []string          `json:"internal_requires,omitempty"`
	ExternalRequires     []string          `json:"external_requires,omitempty"`
}

type Canvas struct {
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

type View struct {
	Key             string        `json:"key"`
	Label           string        `json:"label"`
	Title           string        `json:"title"`
	Breadcrumb      []Breadcrumb  `json:"breadcrumb"`
	Canvas          Canvas        `json:"canvas"`
	Layers          []ViewLayer   `json:"layers"`
	Nodes           []ViewNode    `json:"nodes"`
	Edges           []GroupedEdge `json:"edges"`
	ClassifiedEdges []GroupedEdge `json:"classified_edges"`
	DisplayEdges    []GroupedEdge `json:"display_edges"`
	Indicators      []Indicator   `json:"indicators"`
}

type ProjectionFeedbackEdge struct {
	From        string     `json:"from"`
	To          string     `json:"to"`
	ModuleEdges []MiniEdge `json:"module_edges"`
}

type MiniEdge struct {
	From string `json:"from"`
	To   string `json:"to"`
	Type string `json:"type,omitempty"`
}

type ProjectionCycleSummary struct {
	View          string                   `json:"view"`
	FeedbackEdges []ProjectionFeedbackEdge `json:"feedback_edges"`
}

type Architecture struct {
	Graph            Graph                    `json:"graph"`
	Modules          map[string]*Module       `json:"modules"`
	Layout           Layout                   `json:"layout"`
	ClassifiedEdges  []ClassifiedEdge         `json:"classified_edges"`
	Views            map[string]*View         `json:"views"`
	ProjectionCycles []ProjectionCycleSummary `json:"projection_cycles"`
	Check            CheckResult              `json:"check"`
	SchemaVersion    int                      `json:"schema_version"`
	ProjectRoot      string                   `json:"project_root"`
	ConfigPath       string                   `json:"config_path,omitempty"`
}
