package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

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
	_ = fs.Parse(args)
	if *requestPath == "" {
		fail("missing --request")
	}
	payload, err := os.ReadFile(*requestPath)
	if err != nil {
		fail(err.Error())
	}
	var request archcore.AnalyzeRequest
	if err := json.Unmarshal(payload, &request); err != nil {
		fail(err.Error())
	}
	architecture, err := archcore.Analyze(request)
	if err != nil {
		fail(err.Error())
	}
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(architecture); err != nil {
		fail(err.Error())
	}
}

func runCheck(args []string) {
	fs := flag.NewFlagSet("check", flag.ExitOnError)
	requestPath := fs.String("request", "", "request file")
	_ = fs.Parse(args)
	if *requestPath == "" {
		fail("missing --request")
	}
	payload, err := os.ReadFile(*requestPath)
	if err != nil {
		fail(err.Error())
	}
	var request archcore.AnalyzeRequest
	if err := json.Unmarshal(payload, &request); err != nil {
		fail(err.Error())
	}
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
