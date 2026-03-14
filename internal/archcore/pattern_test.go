package archcore

import "testing"

func TestLuaPatternMatch(t *testing.T) {
	re := luaPatternToRegex("^src%.demo%..+")
	t.Log(re)
	if !matchesLuaPattern("src.demo.beta", "^src%.demo%..+") {
		t.Fatalf("pattern did not match")
	}
}
