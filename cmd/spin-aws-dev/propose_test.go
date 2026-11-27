package main

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

const deploymentMain = `module "spin" {
  source       = "github.com/spin-stack/spin-terraform-aws?ref=v20261101.01"
  spin_version = "stable"
}
`

// git runs git in dir, failing the test when it fails.
func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v: %s", args, err, out)
	}
	return string(out)
}

// deployment is spin-stack/spinbox.dev-deploy with main.tf as given and a lock, on a remote the
// fake gh clones; open is gh pr list's answer, and tofu, when lock is true, moves the lock. It
// returns the remote, the calls, and git's global configuration.
func deployment(t *testing.T, mainTF, open string, lock bool) (origin, calls, global string) {
	t.Helper()
	global = filepath.Join(t.TempDir(), "gitconfig")
	t.Setenv("GIT_CONFIG_GLOBAL", global)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	t.Setenv("GITHUB_SHA", "abc1234def5678")
	t.Setenv("GITHUB_REF_TYPE", "branch")
	t.Setenv("GITHUB_REF_NAME", "main")
	t.Setenv("GITHUB_SERVER_URL", "https://github.com")
	t.Setenv("GITHUB_REPOSITORY", "spin-stack/spin-terraform-aws")
	t.Setenv("APP_SLUG", "spin-stack-release")
	t.Setenv("REPOSITORY", "spin-stack/spinbox.dev-deploy")

	seed := t.TempDir()
	git(t, seed, "init", "-q", "-b", "main")
	put(t, filepath.Join(seed, "main.tf"), mainTF, 0o644)
	put(t, filepath.Join(seed, ".terraform.lock.hcl"), "# the lock\n", 0o644)
	git(t, seed, "add", ".")
	git(t, seed, "-c", "user.name=seed", "-c", "user.email=seed@example.com", "commit", "-q", "-m", "seed")
	origin = filepath.Join(t.TempDir(), "origin.git")
	git(t, seed, "clone", "-q", "--bare", seed, origin)

	dir := t.TempDir()
	put(t, filepath.Join(dir, "prs.json"), open, 0o644)
	calls = fakes(t, map[string]string{
		"gh": `case "$1 $2" in
"auth setup-git") ;;
"api /users/"*) echo '{"login":"spin-stack-release[bot]","id":42}';;
"repo clone") git clone -q ` + origin + ` "$4";;
"pr list") cat ` + filepath.Join(dir, "prs.json") + `;;
"pr create"|"pr edit") ;;
*) exit 3;;
esac`,
	})
	moves := ""
	if lock {
		moves = `echo 'provider "registry.opentofu.org/spin-stack/spin" {}' >> .terraform.lock.hcl`
	}
	tofu := filepath.Join(dir, "tofu")
	put(t, tofu, "#!/bin/sh\necho \"tofu $*\" >> "+calls+"\necho 'OpenTofu has been successfully initialized!'\n"+moves+"\n", 0o755)
	t.Setenv("TOFU", tofu)
	return origin, calls, global
}

const proposalBody = "Moves the installation to spin-stack/spin-terraform-aws at %s (abc1234def5678). The release it runs is " +
	"its spin_version's - a release, or a channel the catalog moves - and not this pull request's. Read the plan before " +
	"merging; merging changes nothing until the apply is run."

func TestProposeCommitsTheModuleAtTheCommitAndOpensItsPullRequest(t *testing.T) {
	origin, calls, _ := deployment(t, deploymentMain, "[]", true)
	if _, stderr, status := verb(t, "propose"); status != 0 {
		t.Fatalf("exit %d: %s", status, stderr)
	}
	if got := git(t, origin, "show", "spin-terraform-aws/next:main.tf"); got != strings.Replace(deploymentMain, "v20261101.01", "abc1234", 1) {
		t.Errorf("main.tf on the branch:\n%s", got)
	}
	if got := git(t, origin, "show", "spin-terraform-aws/next:.terraform.lock.hcl"); !strings.Contains(got, "spin-stack/spin") {
		t.Errorf("the lock did not move with the ref:\n%s", got)
	}
	if got := git(t, origin, "log", "-1", "--format=%an <%ae>%n%B", "spin-terraform-aws/next"); got != "spin-stack-release[bot] <42+spin-stack-release[bot]@users.noreply.github.com>\n"+
		"module abc1234\n\nspin-stack/spin-terraform-aws at https://github.com/spin-stack/spin-terraform-aws/commit/abc1234def5678. Read the plan before merging.\n\n" {
		t.Errorf("the commit:\n%s", got)
	}
	got := read(t, calls)
	if !strings.Contains(got, "tofu init -backend=false -input=false -no-color\n") {
		t.Errorf("ran:\n%s", got)
	}
	want := "gh pr create -R spin-stack/spinbox.dev-deploy --head spin-terraform-aws/next --base main --title module abc1234 --body " +
		strings.Replace(proposalBody, "%s", "abc1234", 1) + "\n"
	if !strings.HasSuffix(got, want) {
		t.Errorf("ran:\n%s\nwant it to end:\n%s", got, want)
	}
}

func TestProposeOnATagMovesToTheTagAndRewritesThePullRequestOpenAlready(t *testing.T) {
	origin, calls, _ := deployment(t, deploymentMain, `[{"number":7}]`, false)
	t.Setenv("GITHUB_REF_TYPE", "tag")
	t.Setenv("GITHUB_REF_NAME", "v20261127.01")
	if _, stderr, status := verb(t, "propose"); status != 0 {
		t.Fatalf("exit %d: %s", status, stderr)
	}
	if got := git(t, origin, "show", "spin-terraform-aws/next:main.tf"); !strings.Contains(got, "?ref=v20261127.01\"") {
		t.Errorf("main.tf on the branch:\n%s", got)
	}
	got := read(t, calls)
	want := "gh pr edit 7 -R spin-stack/spinbox.dev-deploy --title module v20261127.01 --body " +
		strings.Replace(proposalBody, "%s", "v20261127.01", 1) + "\n"
	if !strings.HasSuffix(got, want) || strings.Contains(got, "pr create") {
		t.Errorf("ran:\n%s\nwant it to end:\n%s", got, want)
	}
}

func TestADeploymentAtTheRefAlreadyIsLeftAlone(t *testing.T) {
	origin, calls, _ := deployment(t, strings.Replace(deploymentMain, "v20261101.01", "abc1234", 1), "[]", false)
	stdout, stderr, status := verb(t, "propose")
	if status != 0 || stdout != "spin-stack/spinbox.dev-deploy is at abc1234 already\n" {
		t.Fatalf("exit %d: %s%s", status, stdout, stderr)
	}
	if got := git(t, origin, "branch", "--list"); strings.Contains(got, "next") {
		t.Errorf("pushed: %s", got)
	}
	if got := read(t, calls); strings.Contains(got, "gh pr") {
		t.Errorf("ran:\n%s", got)
	}
}

func TestADryRunProposesNothing(t *testing.T) {
	origin, calls, global := deployment(t, deploymentMain, "[]", false)
	stdout, stderr, status := verb(t, "propose", "--dry-run")
	if status != 0 {
		t.Fatalf("exit %d: %s", status, stderr)
	}
	if got := git(t, origin, "branch", "--list"); strings.Contains(got, "next") {
		t.Errorf("pushed: %s", got)
	}
	if got := read(t, calls); strings.Contains(got, "pr create") || strings.Contains(got, "pr edit") || strings.Contains(got, "setup-git") {
		t.Errorf("ran:\n%s", got)
	}
	if got := read(t, global); got != "" {
		t.Errorf("git's global configuration:\n%s", got)
	}
	if !strings.Contains(stdout, `+  source       = "github.com/spin-stack/spin-terraform-aws?ref=abc1234"`) ||
		!strings.Contains(stdout, "dry run, not run: git push -q --force origin spin-terraform-aws/next\n") ||
		!strings.Contains(stdout, "dry run, not run: gh pr create -R spin-stack/spinbox.dev-deploy") {
		t.Errorf("stdout:\n%s", stdout)
	}
}
