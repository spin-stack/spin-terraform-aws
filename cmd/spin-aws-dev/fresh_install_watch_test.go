package main

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"
)

const runURL = "https://github.com/spin-stack/spin-terraform-aws/actions/runs/9"

// account is a checkout whose hack/fresh-install-remove.sh finds the account as state says - clean,
// removable (left behind, and removed on the first try) or stuck (left behind for good) - and
// whose gh answers issues for the open issue list; it returns the calls.
func account(t *testing.T, state, issues string) string {
	t.Helper()
	t.Setenv("RUN_URL", runURL)
	t.Setenv("ALERT_ASSIGNEE", "aledbf")
	dir := t.TempDir()
	t.Chdir(dir)
	put(t, filepath.Join(dir, "state"), state, 0o644)
	put(t, filepath.Join(dir, "issues.json"), issues, 0o644)
	calls := fakes(t, map[string]string{
		"gh": `case "$1 $2" in
"issue list") cat ` + filepath.Join(dir, "issues.json") + `;;
"issue close"|"issue comment"|"issue create"|"label create") ;;
*) exit 3;;
esac`,
	})
	put(t, filepath.Join(dir, "hack", "fresh-install-remove.sh"), `echo "remove $*" >> `+calls+`
state=$(cat state)
if [ "${1:-}" = --list ]; then
  [ "$state" = clean ] && exit 0
  echo "::warning::left behind: instance i-0abc"
  echo "the bootstrap's bucket" >&2
  exit 1
fi
[ "$state" = removable ] && echo clean > state
exit 0
`, 0o644)
	return calls
}

func TestTheWatchClosesTheIssueOnceTheAccountIsClean(t *testing.T) {
	calls := account(t, "clean", `[{"number":5}]`)
	stdout, stderr, status := verb(t, "fresh-install", "watch")
	if status != 0 || stdout != "nothing of the fresh install is in the account\n" {
		t.Fatalf("exit %d: %s%s", status, stdout, stderr)
	}
	if got := read(t, calls); !strings.HasSuffix(got, "gh issue close 5 --comment The account is clean: "+runURL+"\n") || strings.Contains(got, "remove \n") {
		t.Errorf("ran:\n%s", got)
	}
}

func TestTheWatchWithNoIssueOpenClosesNone(t *testing.T) {
	calls := account(t, "clean", `[]`)
	if _, stderr, status := verb(t, "fresh-install", "watch"); status != 0 {
		t.Fatalf("exit %d: %s", status, stderr)
	}
	if got := read(t, calls); strings.Contains(got, "issue close") {
		t.Errorf("ran:\n%s", got)
	}
}

func TestTheWatchRemovesWhatWasLeftAndClosesTheIssue(t *testing.T) {
	calls := account(t, "removable", `[{"number":5}]`)
	stdout, stderr, status := verb(t, "fresh-install", "watch")
	if status != 0 {
		t.Fatalf("exit %d: %s", status, stderr)
	}
	if !strings.Contains(stdout, "::warning::the fresh install left things in the account: removing them\n") || !strings.HasSuffix(stdout, "removed\n") {
		t.Errorf("stdout:\n%s", stdout)
	}
	if got := read(t, calls); !strings.Contains(got, "remove \n") || !strings.HasSuffix(got, "gh issue close 5 --comment Removed by the watch: "+runURL+"\n") {
		t.Errorf("ran:\n%s", got)
	}
}

func TestTheWatchFailsWhileSomethingIsStillThere(t *testing.T) {
	calls := account(t, "stuck", `[{"number":5}]`)
	if _, stderr, status := verb(t, "fresh-install", "watch"); status != 1 {
		t.Errorf("exit %d: %s", status, stderr)
	}
	if got := read(t, calls); strings.Contains(got, "issue close") {
		t.Errorf("ran:\n%s", got)
	}
}

func TestADryRunWatchRemovesNothingAndClosesNothing(t *testing.T) {
	calls := account(t, "removable", `[{"number":5}]`)
	stdout, _, status := verb(t, "fresh-install", "watch", "--dry-run")
	if status != 1 || !strings.Contains(stdout, "dry run, not run: bash hack/fresh-install-remove.sh\n") {
		t.Errorf("exit %d: %s", status, stdout)
	}
	if got := read(t, calls); strings.Contains(got, "remove \n") || strings.Contains(got, "issue close") {
		t.Errorf("ran:\n%s", got)
	}
}

func TestTheReportCommentsOnTheOpenIssue(t *testing.T) {
	calls := account(t, "stuck", `[{"number":5}]`)
	stdout, stderr, status := verb(t, "fresh-install", "watch", "--report")
	if status != 0 {
		t.Fatalf("exit %d: %s", status, stderr)
	}
	if !strings.Contains(stdout, "::warning::left behind: instance i-0abc\n") {
		t.Errorf("the listing is not said:\n%s", stdout)
	}
	got := read(t, calls)
	if !strings.Contains(got, "gh label create fresh-install-left-behind --color B60205 --description The fresh install left something in AWS --force\n") ||
		!strings.Contains(got, "gh issue comment 5 --body The watch did not finish") || strings.Contains(got, "issue create") {
		t.Errorf("ran:\n%s", got)
	}
}

func TestTheReportOpensAnIssueAssignedWhenNoneIsOpen(t *testing.T) {
	calls := account(t, "stuck", `[]`)
	if _, stderr, status := verb(t, "fresh-install", "watch", "--report"); status != 0 {
		t.Fatalf("exit %d: %s", status, stderr)
	}
	if got := read(t, calls); !strings.Contains(got, "gh issue create --title The fresh install left things in AWS --label fresh-install-left-behind --assignee aledbf --body The watch did not finish") {
		t.Errorf("ran:\n%s", got)
	}
}

func TestTheIssueSaysTheListingAsAReaderReadsIt(t *testing.T) {
	var listing strings.Builder
	listing.WriteString("::warning::left behind: instance i-0abc\n::error::the bucket\n" + strings.Repeat("x", 250) + "\n")
	for i := range 70 {
		fmt.Fprintf(&listing, "line %d\n", i)
	}
	listing.WriteString("\n\n")
	var want strings.Builder
	want.WriteString("The watch did not finish removing what the fresh install left in the account, and what is there goes on " +
		"costing until it is gone. It tries again on its next run.\n\nRun: " + runURL + "\n\nStill there:\n```\n" +
		"left behind: instance i-0abc\nthe bucket\n" + strings.Repeat("x", 200) + "\n")
	for i := range 57 {
		fmt.Fprintf(&want, "line %d\n", i)
	}
	want.WriteString("```")
	if got := leftBehindBody(runURL, listing.String()); got != want.String() {
		t.Errorf("got:\n%s\nwant:\n%s", got, want.String())
	}
	if got := leftBehindBody(runURL, ""); !strings.HasSuffix(got, "Still there:\n```\n\n```") {
		t.Errorf("of nothing listed:\n%s", got)
	}
}
