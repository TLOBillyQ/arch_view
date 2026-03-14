package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"arch_view/internal/archcore"
)

func main() {
	if len(os.Args) < 2 {
		fail("usage: archview-core analyze --request <file>")
	}
	switch os.Args[1] {
	case "analyze":
		runAnalyze(os.Args[2:])
	case "check":
		runCheck(os.Args[2:])
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
	architecture, err := archcore.Analyze(request)
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
	check, err := archcore.Check(request)
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

func mustLoadRequest(requestPath, projectRoot, configPath string) archcore.AnalyzeRequest {
	if requestPath != "" {
		payload, err := os.ReadFile(requestPath)
		if err != nil {
			fail(err.Error())
		}
		var request archcore.AnalyzeRequest
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
	var config archcore.Config
	if err := json.Unmarshal(payload, &config); err != nil {
		fail(err.Error())
	}
	return archcore.AnalyzeRequest{
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

func writeArchitecture(file *os.File, architecture *archcore.Architecture, format string) error {
	if format == "lua" {
		payload, err := archcore.EncodeLuaLiteral(architecture)
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
