package archcore

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func moduleFromPath(logicalRoot, filesystemRoot, path string) *ScanModule {
	normalizedRoot := normalizePath(logicalRoot)
	normalizedFSRoot := normalizePath(filesystemRoot)
	normalizedPath := normalizePath(path)

	prefix := normalizedFSRoot + "/"
	if !strings.HasPrefix(normalizedPath, prefix) || !strings.HasSuffix(normalizedPath, ".lua") {
		return nil
	}
	modulePath := strings.TrimSuffix(strings.TrimPrefix(normalizedPath, prefix), ".lua")
	rootSegments := splitString(normalizedRoot, "/")
	pathSegments := splitString(modulePath, "/")
	if len(pathSegments) > 0 && pathSegments[len(pathSegments)-1] == "init" {
		pathSegments = pathSegments[:len(pathSegments)-1]
	}
	fullSegments := append(copyStrings(rootSegments), pathSegments...)
	return &ScanModule{
		Root:              normalizedRoot,
		ModuleID:          strings.Join(fullSegments, "."),
		ModuleSegments:    fullSegments,
		NamespaceSegments: pathSegments,
		SourcePath:        normalizedPath,
	}
}

func collectLuaFiles(root string) ([]string, error) {
	files := []string{}
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if strings.HasSuffix(strings.ToLower(d.Name()), ".lua") {
			files = append(files, normalizePath(path))
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(files)
	return files, nil
}

func Scan(config Config, projectRoot string) (*ScanResult, error) {
	projectRoot = normalizePath(projectRoot)
	modules := map[string]*ScanModule{}
	moduleIDs := map[string]bool{}

	for _, root := range config.SourceRoots {
		logicalRoot := normalizePath(root)
		filesystemRoot := resolvePath(projectRoot, root)
		if _, err := os.Stat(filesystemRoot); err != nil {
			return nil, fmt.Errorf("directory does not exist: %s", filesystemRoot)
		}
		files, err := collectLuaFiles(filesystemRoot)
		if err != nil {
			return nil, err
		}
		for _, path := range files {
			resolved := moduleFromPath(logicalRoot, filesystemRoot, path)
			if resolved == nil {
				continue
			}
			content, err := os.ReadFile(path)
			if err != nil {
				return nil, err
			}
			resolved.SourceText = string(content)
			modules[resolved.ModuleID] = resolved
			moduleIDs[resolved.ModuleID] = true
		}
	}

	moduleList := sortedKeys(modules)
	return &ScanResult{
		Modules:     modules,
		ModuleIDs:   moduleIDs,
		ModuleList:  moduleList,
		ProjectRoot: projectRoot,
	}, nil
}
