package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
)

// proposeBranch is the one branch per deployment, rewritten by each run: the pull request on it is
// the newest.
const proposeBranch = "spin-terraform-aws/next"

func proposeCmd() *cobra.Command {
	var dry bool
	c := &cobra.Command{
		Use:   "propose",
		Short: "Propose this commit to a deployment: a pull request in REPOSITORY moving its module to this ref",
		Long: `Open or rewrite the pull request in REPOSITORY (spin-stack/<deployment>) that moves its module's
ref to the one GitHub's GITHUB_* variables name: the release's tag, or the commit on main. As the
app GH_TOKEN and APP_SLUG are, with the OpenTofu at TOFU (.github/workflows/propose.yml says why
and how).`,
		Args: cobra.NoArgs,
		RunE: func(c *cobra.Command, _ []string) error {
			e, err := env("GITHUB_REF_TYPE", "GITHUB_SHA", "GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "APP_SLUG", "REPOSITORY", "TOFU")
			if err != nil {
				return err
			}
			ref := moduleRef(e["GITHUB_REF_TYPE"], os.Getenv("GITHUB_REF_NAME"), e["GITHUB_SHA"])
			if ref == "" {
				return errors.New("not set: GITHUB_REF_NAME, which names the tag")
			}
			return propose(programsOf(c, dry), proposal{
				ref: ref, sha: e["GITHUB_SHA"], commit: e["GITHUB_SERVER_URL"] + "/" + e["GITHUB_REPOSITORY"] + "/commit/" + e["GITHUB_SHA"],
				app: e["APP_SLUG"], repository: e["REPOSITORY"], tofu: e["TOFU"],
			})
		},
	}
	c.Flags().BoolVar(&dry, "dry-run", false, "move the module in a clone and say the commit, push and pull request it would make")
	return c
}

// moduleRef is the ref a deployment names: a release's tag, which is what its users follow, or the
// commit on main, by its short name.
func moduleRef(refType, refName, sha string) string {
	if refType == "tag" {
		return refName
	}
	return sha[:min(len(sha), 7)]
}

type proposal struct {
	ref, sha, commit string
	app              string // the app's slug, whose bot commits
	repository       string // spin-stack/<deployment>
	tofu             string
}

func (o proposal) title() string { return "module " + o.ref }

func (o proposal) body() string {
	return "Moves the installation to spin-stack/spin-terraform-aws at " + o.ref + " (" + o.sha + "). The release it runs is " +
		"its spin_version's - a release, or a channel the catalog moves - and not this pull request's. Read the plan " +
		"before merging; merging changes nothing until the apply is run."
}

func propose(p programs, o proposal) error {
	if err := p.write("", "gh", "auth", "setup-git"); err != nil {
		return err
	}
	bot := o.app + "[bot]"
	user, err := p.read("gh", "api", "/users/"+bot)
	if err != nil {
		return err
	}
	var account struct {
		ID int64 `json:"id"`
	}
	if err := json.Unmarshal([]byte(user), &account); err != nil || account.ID == 0 {
		return fmt.Errorf("reading %s's id from %q: %v", bot, user, err)
	}
	if err := p.write("", "git", "config", "--global", "user.name", bot); err != nil {
		return err
	}
	if err := p.write("", "git", "config", "--global", "user.email", strconv.FormatInt(account.ID, 10)+"+"+bot+"@users.noreply.github.com"); err != nil {
		return err
	}

	tmp, err := os.MkdirTemp("", "propose-")
	if err != nil {
		return err
	}
	defer func() { _ = os.RemoveAll(tmp) }()
	clone := filepath.Join(tmp, "deployment")
	if err := p.run("gh", "repo", "clone", o.repository, clone, "--", "--quiet", "--depth", "1"); err != nil {
		return err
	}
	d := p.in(clone)
	mainTF := filepath.Join(clone, "main.tf")
	raw, err := os.ReadFile(mainTF)
	if err != nil {
		return err
	}
	if err := os.WriteFile(mainTF, []byte(withModuleRef(string(raw), o.ref)), 0o644); err != nil {
		return err
	}
	// A provider the module at ref requires and the deployment's lock has not - spin's, when the
	// catalog came - refuses its plan's init, which is -lockfile=readonly: the lock moves with the
	// ref. A provider the lock has stays at its version.
	init := d
	init.out = nil
	if err := init.run(o.tofu, "init", "-backend=false", "-input=false", "-no-color"); err != nil {
		return err
	}
	if changed, err := changed(d); err != nil {
		return err
	} else if !changed {
		say(p, "%s is at %s already", o.repository, o.ref)
		return nil
	}
	if p.dry {
		if err := d.run("git", "diff"); err != nil {
			return err
		}
	}

	if err := d.write("", "git", "checkout", "-q", "-b", proposeBranch); err != nil {
		return err
	}
	if err := d.write("", "git", "commit", "-q", "-a", "-m", o.title(),
		"-m", "spin-stack/spin-terraform-aws at "+o.commit+". Read the plan before merging."); err != nil {
		return err
	}
	if err := d.write("", "git", "push", "-q", "--force", "origin", proposeBranch); err != nil {
		return err
	}
	// Everything named, nothing inferred from the shallow clone. A pull request open already was
	// just rewritten: its title and body say what it holds now.
	list, err := d.read("gh", "pr", "list", "-R", o.repository, "--head", proposeBranch, "--state", "open", "--json", "number")
	if err != nil {
		return err
	}
	open, err := firstNumber(list)
	if err != nil {
		return err
	}
	if open == "" {
		return d.write("", "gh", "pr", "create", "-R", o.repository, "--head", proposeBranch, "--base", "main",
			"--title", o.title(), "--body", o.body())
	}
	return d.write("", "gh", "pr", "edit", open, "-R", o.repository, "--title", o.title(), "--body", o.body())
}

// changed is whether the clone's tracked files differ from its commit.
func changed(d programs) (bool, error) {
	err := d.command("git", "diff", "--quiet").Run()
	var exit *exec.ExitError
	if errors.As(err, &exit) && exit.ExitCode() == 1 {
		return true, nil
	}
	return false, failed(err, "git", []string{"diff", "--quiet"})
}

var moduleSource = regexp.MustCompile(`(github\.com/spin-stack/spin-terraform-aws\?ref=)[^"\n]+`)

// withModuleRef is main.tf with this module's source at ref: the first on each line, as sed moved it.
func withModuleRef(mainTF, ref string) string {
	var b strings.Builder
	for l := range strings.Lines(mainTF) {
		if m := moduleSource.FindStringSubmatchIndex(l); m != nil {
			l = l[:m[3]] + ref + l[m[1]:]
		}
		b.WriteString(l)
	}
	return b.String()
}

// firstNumber is the number of the first of gh's --json number list, or nothing when it is empty.
func firstNumber(raw string) (string, error) {
	var items []struct {
		Number int `json:"number"`
	}
	if err := json.Unmarshal([]byte(raw), &items); err != nil {
		return "", fmt.Errorf("reading gh's list %q: %w", raw, err)
	}
	if len(items) == 0 {
		return "", nil
	}
	return strconv.Itoa(items[0].Number), nil
}
