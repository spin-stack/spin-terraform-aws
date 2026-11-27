package main

import (
	"cmp"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
)

func releaseCmd() *cobra.Command {
	var dry bool
	c := &cobra.Command{
		Use:   "release",
		Short: "Cut this module's next release: GITHUB_SHA, once Gate passed on it, as the next v<YYYYMMDD>.<NN>",
		Long: `Tag GITHUB_SHA as the next v<YYYYMMDD>.<NN> today, in UTC, with its GitHub release in
GITHUB_REPOSITORY, as GH_TOKEN (.github/workflows/release.yml says why). Only a commit Gate passed
on is released, and go-tools' release, on go tool task's PATH, names it and refuses a commit a
release names already.`,
		Args: cobra.NoArgs,
		RunE: func(c *cobra.Command, _ []string) error {
			e, err := env("GITHUB_SHA", "GITHUB_REPOSITORY", "GITHUB_SERVER_URL")
			if err != nil {
				return err
			}
			return release(programsOf(c, dry), e["GITHUB_SHA"], e["GITHUB_REPOSITORY"], e["GITHUB_SERVER_URL"])
		},
	}
	c.Flags().BoolVar(&dry, "dry-run", false, "name the release and write its notes, and make neither the tag nor the release")
	return c
}

func release(p programs, sha, repo, server string) error {
	// Only a commit Gate passed on: a release is what an installation that follows them is proposed
	// next, and nothing after this looks at the commit again. The latest Gate run, so a run again
	// that passed is the one that counts.
	runs, err := p.read("gh", "api", "repos/"+repo+"/commits/"+sha+"/check-runs?check_name=Gate")
	if err != nil {
		return err
	}
	if gate, err := latestConclusion(runs); err != nil {
		return err
	} else if gate != "success" {
		return exitError{code: 1, err: fmt.Errorf("Gate has not passed on %s (%s): nothing is released", sha, cmp.Or(gate, "no run"))}
	}

	// go-tools' release counts from every tag there is, so all of them are fetched first.
	if err := p.run("git", "fetch", "--quiet", "--tags", "origin"); err != nil {
		return err
	}
	version, err := p.read("release", sha)
	if err != nil {
		return err
	}
	tags, err := p.read("git", "ls-remote", "--tags", "--refs", "origin", "refs/tags/v*")
	if err != nil {
		return err
	}
	notes := releaseNotes(version, newestRelease(tags), server, repo)

	// The tag is made by the release, at the commit, in one call: no tag without its release.
	if err := p.write(notes, "gh", "release", "create", version, "-R", repo, "--target", sha,
		"--title", version, "--notes-file", "-"); err != nil {
		return err
	}
	if !p.dry {
		say(p, "Released %s at %s", version, sha)
	}
	return nil
}

// latestConclusion is the conclusion of the first check run the API lists, or nothing when there
// is none or it has not concluded.
func latestConclusion(raw string) (string, error) {
	var runs struct {
		CheckRuns []struct {
			Conclusion *string `json:"conclusion"`
		} `json:"check_runs"`
	}
	if err := json.Unmarshal([]byte(raw), &runs); err != nil {
		return "", fmt.Errorf("reading Gate's check runs: %w", err)
	}
	if len(runs.CheckRuns) == 0 || runs.CheckRuns[0].Conclusion == nil {
		return "", nil
	}
	return *runs.CheckRuns[0].Conclusion, nil
}

var releaseName = regexp.MustCompile(`^v([0-9]{8})\.([0-9]+)$`)

// newestRelease is the newest release among git ls-remote's tag lines, by ship-it's order
// (edit.Newer): the day, then the number, a longer number the later. Nothing when there is none.
func newestRelease(lsRemote string) string {
	type named struct {
		day  string
		n    uint64
		name string
	}
	var newest *named
	for l := range strings.Lines(lsRemote) {
		_, ref, _ := strings.Cut(strings.TrimSpace(l), "refs/tags/")
		m := releaseName.FindStringSubmatch(ref)
		if m == nil {
			continue
		}
		n, err := strconv.ParseUint(m[2], 10, 64)
		if err != nil {
			continue
		}
		r := named{day: m[1], n: n, name: ref}
		if newest == nil || cmp.Or(cmp.Compare(r.day, newest.day), cmp.Compare(r.n, newest.n), cmp.Compare(r.name, newest.name)) > 0 {
			newest = &r
		}
	}
	if newest == nil {
		return ""
	}
	return newest.name
}

// releaseNotes are the notes of the release named version: how a configuration takes it, and what
// changed since previous when there is one.
func releaseNotes(version, previous, server, repo string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "## Using this release\n\n```hcl\nmodule \"spin\" {\n")
	fmt.Fprintf(&b, "  source       = \"github.com/spin-stack/spin-terraform-aws?ref=%s\"\n", version)
	fmt.Fprintf(&b, "  spin_version = \"stable\" # or \"edge\", or a release: v<YYYYMMDD>.<N>\n}\n```\n\n")
	b.WriteString("`spin_version` names a spin release or a channel, which the module resolves through the image catalog " +
		"(the `spin` provider), whatever release of the module this is. How an installation takes it is the README's \"Updating\".\n")
	if previous != "" {
		fmt.Fprintf(&b, "\nWhat changed since %s: %s/%s/compare/%s...%s\n", previous, server, repo, previous, version)
	}
	return b.String()
}
