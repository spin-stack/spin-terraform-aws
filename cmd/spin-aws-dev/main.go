// spin-aws-dev releases this module, proposes it to the deployments made from it, and watches the
// fresh install's account. It is the command the Taskfile runs for those steps, so what they decide
// is Go with a test, and the only programs it runs are the ones that do the job: gh, git, tofu and
// go-tools' release. Every verb that writes takes --dry-run, which reads as the verb does and says
// each write instead of making it.
//
// Exit status: 0 done, 1 done with something to act on or not done, or a program's own status when
// a program it ran failed.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"syscall"

	"github.com/spf13/cobra"
)

func main() {
	os.Exit(exit(run(), os.Stderr))
}

// exitError is an exit status a verb chose, and what it says.
type exitError struct {
	code int
	err  error
}

func (e exitError) Error() string {
	if e.err == nil {
		return fmt.Sprintf("exit status %d", e.code)
	}
	return e.err.Error()
}

func (e exitError) Unwrap() error { return e.err }

// exitCode is the status err exits with: none, a verb's own, or 1.
func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var e exitError
	if errors.As(err, &e) {
		return e.code
	}
	return 1
}

// exit says err on w, unless it is only a status, and answers the status to exit with.
func exit(err error, w io.Writer) int {
	var e exitError
	if err != nil && (!errors.As(err, &e) || e.err != nil) {
		_, _ = fmt.Fprintf(w, "spin-aws-dev: %v\n", err)
	}
	return exitCode(err)
}

// run is the command, its signal handling undone before main exits: os.Exit runs no defer.
func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return root().ExecuteContext(ctx)
}

// root is the command and its verbs, each made fresh so that its flags start at their defaults.
func root() *cobra.Command {
	c := &cobra.Command{
		Use:               "spin-aws-dev",
		Short:             "Release this module, propose it to a deployment, and watch the fresh install's account",
		SilenceUsage:      true,
		SilenceErrors:     true,
		CompletionOptions: cobra.CompletionOptions{DisableDefaultCmd: true},
	}
	c.AddCommand(releaseCmd(), proposeCmd(), freshInstallCmd())
	return c
}
