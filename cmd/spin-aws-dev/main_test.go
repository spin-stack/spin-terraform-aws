package main

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func put(t *testing.T, path, body string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), mode); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		t.Fatal(err)
	}
	return string(b)
}

// fakes puts programs on the PATH, each a shell script that records its arguments in calls, a line
// each, and runs its body; it returns the file the calls are in.
func fakes(t *testing.T, programs map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	calls := filepath.Join(dir, "calls")
	for name, body := range programs {
		put(t, filepath.Join(dir, name), "#!/bin/sh\necho \""+name+" $*\" >> "+calls+"\n"+body+"\n", 0o755)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return calls
}

// verb runs the command with args, and says what it wrote and the status it exits with.
func verb(t *testing.T, args ...string) (stdout, stderr string, status int) {
	t.Helper()
	c := root()
	c.SetArgs(append([]string{}, args...))
	var o, e bytes.Buffer
	c.SetOut(&o)
	c.SetErr(&e)
	c.SetIn(strings.NewReader(""))
	err := c.ExecuteContext(context.Background())
	return o.String(), e.String() + func() string {
		if err != nil {
			return err.Error()
		}
		return ""
	}(), exitCode(err)
}

func TestAVerbMissingItsEnvironmentNamesWhatIsMissing(t *testing.T) {
	for _, n := range []string{"GITHUB_SHA", "GITHUB_REPOSITORY", "GITHUB_SERVER_URL"} {
		t.Setenv(n, "")
	}
	calls := fakes(t, map[string]string{"gh": "", "git": "", "release": ""})
	_, stderr, status := verb(t, "release")
	if status != 1 || !strings.Contains(stderr, "not set: GITHUB_SHA, GITHUB_REPOSITORY, GITHUB_SERVER_URL") {
		t.Errorf("exit %d: %s", status, stderr)
	}
	if got := read(t, calls); got != "" {
		t.Errorf("ran %q", got)
	}
}
