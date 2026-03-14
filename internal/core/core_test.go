package core

import (
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func sampleConfig() Config {
	return Config{
		SourceRoots:              []string{"src"},
		ComponentRules:           []Rule{{Name: "demo", Match: []string{"^src%.demo$", "^src%.demo%..+"}, Component: "demo"}},
		AbstractRules:            []Rule{},
		ForbiddenDependencyRules: []Rule{},
	}
}

func TestScanTreatsInitAsPackageEntry(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "src/demo/pkg/init.lua"), "return {}\n")
	writeFile(t, filepath.Join(root, "src/demo/pkg/child.lua"), "return {}\n")
	result, err := Scan(sampleConfig(), root)
	if err != nil {
		t.Fatal(err)
	}
	if !result.ModuleIDs["src.demo.pkg"] {
		t.Fatalf("expected init.lua to map to package module id")
	}
	if result.ModuleIDs["src.demo.pkg.init"] {
		t.Fatalf("did not expect foo.init module id")
	}
}

func TestExtractCollectsStaticRequiresAndSkipsForwardingShim(t *testing.T) {
	scanResult := &ScanResult{
		ModuleIDs:  map[string]bool{"src.demo.a": true, "src.demo.b": true, "src.demo.c": true},
		ModuleList: []string{"src.demo.a", "src.demo.b", "src.demo.c"},
		Modules: map[string]*ScanModule{
			"src.demo.a": {ModuleID: "src.demo.a", ModuleSegments: []string{"src", "demo", "a"}, NamespaceSegments: []string{"demo", "a"}, SourcePath: "src/demo/a.lua", SourceText: "local b = require(\"src.demo.b\")\nrequire 'src.demo.c'\nrequire 'external.pkg'\n", Root: "src"},
			"src.demo.b": {ModuleID: "src.demo.b", ModuleSegments: []string{"src", "demo", "b"}, NamespaceSegments: []string{"demo", "b"}, SourcePath: "src/demo/b.lua", SourceText: "return {}\n", Root: "src"},
			"src.demo.c": {ModuleID: "src.demo.c", ModuleSegments: []string{"src", "demo", "c"}, NamespaceSegments: []string{"demo", "c"}, SourcePath: "src/demo/c.lua", SourceText: "return require('src.demo.b')\n", Root: "src"},
		},
	}
	_, modules := Extract(scanResult)
	if len(modules["src.demo.a"].InternalRequires) != 2 {
		t.Fatalf("expected 2 internal requires, got %d", len(modules["src.demo.a"].InternalRequires))
	}
	if len(modules["src.demo.a"].ExternalRequires) != 1 || modules["src.demo.a"].ExternalRequires[0] != "external.pkg" {
		t.Fatalf("unexpected external requires: %#v", modules["src.demo.a"].ExternalRequires)
	}
	if len(modules["src.demo.c"].InternalRequires) != 0 {
		t.Fatalf("forwarding shim should not create internal requires")
	}
}

func TestAnalyzeBuildsViewsAndCheck(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "src/demo/pkg/init.lua"), "local beta = require(\"src.demo.beta\")\nreturn beta\n")
	writeFile(t, filepath.Join(root, "src/demo/pkg/child.lua"), "return {}\n")
	writeFile(t, filepath.Join(root, "src/demo/beta.lua"), "return {}\n")
	architecture, err := Analyze(AnalyzeRequest{ProjectRoot: root, ConfigPath: filepath.Join(root, "arch_view.config.json"), Config: sampleConfig()})
	if err != nil {
		t.Fatal(err)
	}
	if !architecture.Check.OK {
		t.Fatalf("expected check ok, got %#v", architecture.Check)
	}
	if architecture.Views["root"] == nil {
		t.Fatalf("expected root view")
	}
	if architecture.Views["demo.pkg"] == nil {
		t.Fatalf("expected nested package view")
	}
	if architecture.Modules["src.demo.pkg"].Component != "demo" {
		t.Fatalf("expected classified module")
	}
}
