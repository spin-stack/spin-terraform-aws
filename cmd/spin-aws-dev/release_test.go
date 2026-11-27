package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// releasing is a repository whose Gate run on abc1234 answers runs, whose origin has tags, and
// whose go-tools release answers name (or refuses, when name is empty); it returns the calls and
// the file gh release create's notes land in.
func releasing(t *testing.T, runs, tags, name string) (calls, notes string) {
	t.Helper()
	t.Setenv("GITHUB_SHA", "abc1234")
	t.Setenv("GITHUB_REPOSITORY", "spin-stack/spin-terraform-aws")
	t.Setenv("GITHUB_SERVER_URL", "https://github.com")
	dir := t.TempDir()
	notes = filepath.Join(dir, "notes")
	put(t, filepath.Join(dir, "runs.json"), runs, 0o644)
	put(t, filepath.Join(dir, "tags"), tags, 0o644)
	answer := "echo " + name
	if name == "" {
		answer = "echo 'release: abc1234 is released already, as v20261126.10' >&2; exit 1"
	}
	calls = fakes(t, map[string]string{
		"gh": `case "$1 $2" in
"api repos/spin-stack/spin-terraform-aws/commits/abc1234/check-runs?check_name=Gate") cat ` + filepath.Join(dir, "runs.json") + `;;
"release create") cat > ` + notes + `;;
*) exit 3;;
esac`,
		"git": `case "$1" in
fetch) ;;
ls-remote) cat ` + filepath.Join(dir, "tags") + `;;
*) exit 3;;
esac`,
		"release": answer,
	})
	return calls, notes
}

const gatePassed = `{"total_count":2,"check_runs":[{"conclusion":"success"},{"conclusion":"failure"}]}`

const tags = `1111 refs/tags/v20261126.9
2222 refs/tags/v20261126.10
3333 refs/tags/v20261125.99
4444 refs/tags/v1.2.3
5555 refs/tags/screens-v20261201.01
6666 refs/tags/v20261201.01-rc
`

func TestReleaseTagsTheCommitGatePassedOnWithNotesSinceTheNewestRelease(t *testing.T) {
	calls, notes := releasing(t, gatePassed, tags, "v20261127.01")
	stdout, stderr, status := verb(t, "release")
	if status != 0 {
		t.Fatalf("exit %d: %s", status, stderr)
	}
	if got := read(t, calls); !strings.Contains(got, "release abc1234\n") || !strings.Contains(got, "git fetch --quiet --tags origin\n") ||
		!strings.HasSuffix(got, "gh release create v20261127.01 -R spin-stack/spin-terraform-aws --target abc1234 --title v20261127.01 --notes-file -\n") {
		t.Errorf("ran:\n%s", got)
	}
	want := "## Using this release\n\n```hcl\nmodule \"spin\" {\n" +
		"  source       = \"github.com/spin-stack/spin-terraform-aws?ref=v20261127.01\"\n" +
		"  spin_version = \"stable\" # or \"edge\", or a release: v<YYYYMMDD>.<N>\n}\n```\n\n" +
		"`spin_version` names a spin release or a channel, which the module resolves through the image catalog (the `spin` provider), " +
		"whatever release of the module this is. How an installation takes it is the README's \"Updating\".\n\n" +
		"What changed since v20261126.10: https://github.com/spin-stack/spin-terraform-aws/compare/v20261126.10...v20261127.01\n"
	if got := read(t, notes); got != want {
		t.Errorf("notes:\n%s\nwant:\n%s", got, want)
	}
	if stdout != "Released v20261127.01 at abc1234\n" {
		t.Errorf("stdout %q", stdout)
	}
}

func TestTheFirstReleaseHasNothingToCompareWith(t *testing.T) {
	_, notes := releasing(t, gatePassed, "4444 refs/tags/v1.2.3\n", "v20261127.01")
	if _, stderr, status := verb(t, "release"); status != 0 {
		t.Fatalf("exit %d: %s", status, stderr)
	}
	if got := read(t, notes); !strings.HasSuffix(got, "README's \"Updating\".\n") || strings.Contains(got, "What changed") {
		t.Errorf("notes:\n%s", got)
	}
}

func TestNothingIsReleasedUnlessGatePassed(t *testing.T) {
	for _, c := range []struct{ runs, says string }{
		{`{"check_runs":[{"conclusion":"failure"},{"conclusion":"success"}]}`, "(failure)"},
		{`{"check_runs":[{"conclusion":null}]}`, "(no run)"},
		{`{"total_count":0,"check_runs":[]}`, "(no run)"},
	} {
		calls, _ := releasing(t, c.runs, tags, "v20261127.01")
		_, stderr, status := verb(t, "release")
		if status != 1 || !strings.Contains(stderr, "Gate has not passed on abc1234 "+c.says+": nothing is released") {
			t.Errorf("%s: exit %d: %s", c.runs, status, stderr)
		}
		if got := read(t, calls); strings.Contains(got, "release create") || strings.Contains(got, "release abc1234") {
			t.Errorf("%s: ran:\n%s", c.runs, got)
		}
	}
}

func TestACommitReleasedAlreadyIsNotReleasedAgain(t *testing.T) {
	calls, _ := releasing(t, gatePassed, tags, "")
	_, stderr, status := verb(t, "release")
	if status != 1 || !strings.Contains(stderr, "is released already") {
		t.Errorf("exit %d: %s", status, stderr)
	}
	if got := read(t, calls); strings.Contains(got, "release create") {
		t.Errorf("ran:\n%s", got)
	}
}

func TestADryRunNamesTheReleaseAndMakesNone(t *testing.T) {
	calls, _ := releasing(t, gatePassed, tags, "v20261127.01")
	stdout, stderr, status := verb(t, "release", "--dry-run")
	if status != 0 {
		t.Fatalf("exit %d: %s", status, stderr)
	}
	if got := read(t, calls); strings.Contains(got, "release create") {
		t.Errorf("ran:\n%s", got)
	}
	if !strings.Contains(stdout, "dry run, not run: gh release create v20261127.01 -R spin-stack/spin-terraform-aws --target abc1234") ||
		!strings.Contains(stdout, "compare/v20261126.10...v20261127.01") || strings.Contains(stdout, "Released") {
		t.Errorf("stdout:\n%s", stdout)
	}
}
