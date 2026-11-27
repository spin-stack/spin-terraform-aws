package main

import (
	"bytes"
	"fmt"
	"regexp"
	"strings"

	"github.com/spf13/cobra"
)

// leftBehind labels the one issue the watch keeps open while the account is not clean.
const leftBehind = "fresh-install-left-behind"

func freshInstallCmd() *cobra.Command {
	c := &cobra.Command{
		Use:   "fresh-install",
		Short: "The fresh install's steps against the account a run assumed",
	}
	c.AddCommand(freshInstallWatchCmd())
	return c
}

func freshInstallWatchCmd() *cobra.Command {
	var report, dry bool
	c := &cobra.Command{
		Use:   "watch",
		Short: "Remove what the fresh install left in the account, closing any issue once it is clean",
		Long: `Between runs nothing of the fresh install should be in the account: one that failed to remove
itself otherwise costs by the hour until the next, a week later, with only a failed run in a list
to say so. So anything found is removed as a run removes it (hack/fresh-install-remove.sh), and
the account clean closes the open issue labelled ` + leftBehind + `, saying RUN_URL.
Exit status 1: something is still there.

--report opens that issue, or comments on it, with what is still there, assigned to
ALERT_ASSIGNEE. .github/workflows/fresh-install-watch.yml runs it as a step of its own after any
failure, since a step that ran out of time reports nothing itself.`,
		Args: cobra.NoArgs,
		RunE: func(c *cobra.Command, _ []string) error {
			names := []string{"RUN_URL"}
			if report {
				names = append(names, "ALERT_ASSIGNEE")
			}
			e, err := env(names...)
			if err != nil {
				return err
			}
			p := programsOf(c, dry)
			if report {
				return reportLeftBehind(p, e["RUN_URL"], e["ALERT_ASSIGNEE"])
			}
			return watch(p, e["RUN_URL"])
		},
	}
	c.Flags().BoolVar(&report, "report", false, "open or comment on the issue with what is still in the account")
	c.Flags().BoolVar(&dry, "dry-run", false, "look, and say the removal and the issue's changes instead of making them")
	return c
}

func watch(p programs, runURL string) error {
	if clean(p) {
		say(p, "nothing of the fresh install is in the account")
		closeLeftBehind(p, "The account is clean: "+runURL)
		return nil
	}
	say(p, "::warning::the fresh install left things in the account: removing them")
	_ = p.write("", "bash", "hack/fresh-install-remove.sh")
	if clean(p) {
		say(p, "removed")
		closeLeftBehind(p, "Removed by the watch: "+runURL)
		return nil
	}
	return exitError{code: 1}
}

// clean is whether the removal finds nothing of the fresh install in the account.
func clean(p programs) bool {
	return p.run("bash", "hack/fresh-install-remove.sh", "--list") == nil
}

// closeLeftBehind closes the open issue, if there is one, saying why. The account is clean either
// way, so a failure here is said and fails nothing.
func closeLeftBehind(p programs, why string) {
	issue, err := openLeftBehind(p)
	if err == nil && issue != "" {
		err = p.write("", "gh", "issue", "close", issue, "--comment", why)
	}
	if err != nil {
		_, _ = fmt.Fprintf(p.err, "closing the issue: %v\n", err)
	}
}

func openLeftBehind(p programs) (string, error) {
	raw, err := p.read("gh", "issue", "list", "--label", leftBehind, "--state", "open", "--limit", "1", "--json", "number")
	if err != nil {
		return "", err
	}
	return firstNumber(raw)
}

func reportLeftBehind(p programs, runURL, assignee string) error {
	var listing bytes.Buffer
	list := p.command("bash", "hack/fresh-install-remove.sh", "--list")
	list.Stdout, list.Stderr = &listing, &listing
	_ = list.Run()
	if _, err := p.out.Write(listing.Bytes()); err != nil {
		return err
	}
	body := leftBehindBody(runURL, listing.String())
	_ = p.write("", "gh", "label", "create", leftBehind, "--color", "B60205", "--description", "The fresh install left something in AWS", "--force")
	if issue, err := openLeftBehind(p); err == nil && issue != "" {
		return p.write("", "gh", "issue", "comment", issue, "--body", body)
	}
	return p.write("", "gh", "issue", "create", "--title", "The fresh install left things in AWS", "--label", leftBehind,
		"--assignee", assignee, "--body", body)
}

// workflowCommand is the ::warning:: and the like a line opens with for the workflow, not a reader.
var workflowCommand = regexp.MustCompile(`^::[a-z]+::`)

// leftBehindBody is the issue's text: the run, and the removal's listing as a reader reads it, its
// first 60 lines and of each its first 200 bytes.
func leftBehindBody(runURL, listing string) string {
	lines := strings.Split(strings.TrimRight(listing, "\n"), "\n")
	lines = lines[:min(len(lines), 60)]
	for i, l := range lines {
		l = workflowCommand.ReplaceAllString(l, "")
		lines[i] = l[:min(len(l), 200)]
	}
	return "The watch did not finish removing what the fresh install left in the account, and what is there goes on " +
		"costing until it is gone. It tries again on its next run.\n\nRun: " + runURL + "\n\nStill there:\n```\n" +
		strings.TrimRight(strings.Join(lines, "\n"), "\n") + "\n```"
}
