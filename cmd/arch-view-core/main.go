package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"arch_view/internal/core"
)

func main() {
	if len(os.Args) < 2 {
		fail("usage: arch-view-core analyze --request <file>")
	}
	switch os.Args[1] {
	case "analyze":
		runAnalyze(os.Args[2:])
	case "check":
		runCheck(os.Args[2:])
	case "export-viewer":
		runExportViewer(os.Args[2:])
	default:
		fail("unknown command: " + os.Args[1])
	}
}

func runAnalyze(args []string) {
	fs := flag.NewFlagSet("analyze", flag.ExitOnError)
	requestPath := fs.String("request", "", "request file")
	outPath := fs.String("out", "", "output file")
	projectRoot := fs.String("project-root", "", "project root")
	configPath := fs.String("config", "", "config file")
	format := fs.String("format", "json", "output format: json|lua")
	_ = fs.Parse(args)
	request := mustLoadRequest(*requestPath, *projectRoot, *configPath)
	architecture, err := core.Analyze(request)
	if err != nil {
		fail(err.Error())
	}

	if *outPath != "" {
		mustMkdir(filepath.Dir(*outPath))
		file, err := os.Create(*outPath)
		if err != nil {
			fail(err.Error())
		}
		defer file.Close()
		if err := writeArchitecture(file, architecture, *format); err != nil {
			fail(err.Error())
		}
		return
	}

	if err := writeArchitecture(os.Stdout, architecture, *format); err != nil {
		fail(err.Error())
	}
}

func runCheck(args []string) {
	fs := flag.NewFlagSet("check", flag.ExitOnError)
	requestPath := fs.String("request", "", "request file")
	projectRoot := fs.String("project-root", "", "project root")
	configPath := fs.String("config", "", "config file")
	_ = fs.Parse(args)
	request := mustLoadRequest(*requestPath, *projectRoot, *configPath)
	check, err := core.Check(request)
	if err != nil {
		fail(err.Error())
	}
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(check); err != nil {
		fail(err.Error())
	}
}

func fail(message string) {
	fmt.Fprintln(os.Stderr, message)
	os.Exit(1)
}

func mustLoadRequest(requestPath, projectRoot, configPath string) core.AnalyzeRequest {
	if requestPath != "" {
		payload, err := os.ReadFile(requestPath)
		if err != nil {
			fail(err.Error())
		}
		var request core.AnalyzeRequest
		if err := json.Unmarshal(payload, &request); err != nil {
			fail(err.Error())
		}
		return request
	}

	if projectRoot == "" || configPath == "" {
		fail("missing --request or --project-root/--config")
	}

	payload, err := os.ReadFile(configPath)
	if err != nil {
		fail(err.Error())
	}
	var config core.Config
	if err := json.Unmarshal(payload, &config); err != nil {
		fail(err.Error())
	}
	return core.AnalyzeRequest{
		ProjectRoot: projectRoot,
		ConfigPath:  configPath,
		Config:      config,
	}
}

func mustMkdir(path string) {
	if path == "" || path == "." {
		return
	}
	if err := os.MkdirAll(path, 0o755); err != nil {
		fail(err.Error())
	}
}

func writeArchitecture(file *os.File, architecture *core.Architecture, format string) error {
	if format == "lua" {
		payload, err := core.EncodeLuaLiteral(architecture)
		if err != nil {
			return err
		}
		_, err = file.WriteString("return " + payload + "\n")
		return err
	}
	encoder := json.NewEncoder(file)
	encoder.SetEscapeHTML(false)
	return encoder.Encode(architecture)
}

func runExportViewer(args []string) {
	fs := flag.NewFlagSet("export-viewer", flag.ExitOnError)
	requestPath := fs.String("request", "", "request file")
	projectRoot := fs.String("project-root", "", "project root")
	configPath := fs.String("config", "", "config file")
	outDir := fs.String("out-dir", "", "output directory")
	assetRoot := fs.String("asset-root", "", "viewer asset root directory")
	_ = fs.Parse(args)

	if *outDir == "" {
		fail("missing --out-dir")
	}

	if *assetRoot == "" {
		fail("missing --asset-root")
	}

	request := mustLoadRequest(*requestPath, *projectRoot, *configPath)
	architecture, err := core.Analyze(request)
	if err != nil {
		fail(err.Error())
	}

	mustMkdir(*outDir)

	if err := copyViewerAssets(*assetRoot, *outDir); err != nil {
		fail(err.Error())
	}

	archJsonPath := filepath.Join(*outDir, "architecture.json")
	if err := writeArchitectureFile(archJsonPath, architecture); err != nil {
		fail(err.Error())
	}

	archDataJsPath := filepath.Join(*outDir, "architecture_data.js")
	if err := writeArchitectureDataJs(archDataJsPath, architecture); err != nil {
		fail(err.Error())
	}

	encoder := json.NewEncoder(os.Stdout)
	encoder.SetEscapeHTML(false)
	encoder.Encode(map[string]string{
		"out_dir":      *outDir,
		"index_path":   filepath.Join(*outDir, "index.html"),
		"asset_root":   *assetRoot,
		"project_root": request.ProjectRoot,
	})
}

func copyViewerAssets(assetRoot, outDir string) error {
	files := []string{"index.html", "script.js", "styles.css"}
	for _, name := range files {
		src := filepath.Join(assetRoot, name)
		dst := filepath.Join(outDir, name)
		if err := copyFile(src, dst); err != nil {
			return fmt.Errorf("failed to copy %s: %w", name, err)
		}
	}
	return nil
}

func copyFile(src, dst string) error {
	srcFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}

	dstFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer dstFile.Close()

	_, err = dstFile.ReadFrom(srcFile)
	return err
}

func writeArchitectureFile(path string, architecture *core.Architecture) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", "  ")
	return encoder.Encode(architecture)
}

func writeArchitectureDataJs(path string, architecture *core.Architecture) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", "  ")

	if _, err := file.WriteString("window.ARCH_VIEW_DATA = "); err != nil {
		return err
	}
	if err := encoder.Encode(architecture); err != nil {
		return err
	}
	_, err = file.WriteString(";\n")
	return err
}
