package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
)

// programs runs what a verb runs, in dir: what reads always, and what writes - to GitHub, to a
// remote, to git's global configuration - only when it is not a dry run, which says it instead.
type programs struct {
	ctx      context.Context
	dir      string
	out, err io.Writer
	dry      bool
}

func programsOf(c *cobra.Command, dry bool) programs {
	return programs{ctx: c.Context(), out: c.OutOrStdout(), err: c.ErrOrStderr(), dry: dry}
}

// in is p with its programs run in dir.
func (p programs) in(dir string) programs {
	p.dir = dir
	return p
}

// read is what name prints on stdout, trimmed; its stderr is the verb's.
func (p programs) read(name string, args ...string) (string, error) {
	cmd := p.command(name, args...)
	cmd.Stderr = p.err
	out, err := cmd.Output()
	return strings.TrimSpace(string(out)), failed(err, name, args)
}

// run runs name with the verb's stdout and stderr.
func (p programs) run(name string, args ...string) error {
	cmd := p.command(name, args...)
	cmd.Stdout, cmd.Stderr = p.out, p.err
	return failed(cmd.Run(), name, args)
}

// write runs name with stdin as its input, as run does, or on a dry run says it would.
func (p programs) write(stdin, name string, args ...string) error {
	if !p.dry {
		cmd := p.command(name, args...)
		cmd.Stdin = strings.NewReader(stdin)
		cmd.Stdout, cmd.Stderr = p.out, p.err
		return failed(cmd.Run(), name, args)
	}
	_, err := fmt.Fprintf(p.out, "dry run, not run: %s\n", line(name, args))
	if err == nil && stdin != "" {
		_, err = fmt.Fprintf(p.out, "with this on its stdin:\n%s\n", stdin)
	}
	return err
}

func (p programs) command(name string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(p.ctx, name, args...)
	cmd.Dir = p.dir
	return cmd
}

// failed is err with the program's exit status as the verb's, so a refusal reads as the program's.
func failed(err error, name string, args []string) error {
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		return exitError{code: exit.ExitCode(), err: fmt.Errorf("%s: %w", line(name, args[:min(len(args), 2)]), err)}
	}
	return err
}

// line is a command line as a person would type it.
func line(name string, args []string) string {
	words := []string{name}
	for _, a := range args {
		if a == "" || strings.ContainsAny(a, " \t\n\"'$`\\|&;<>()*?[]{}#~") {
			a = strconv.Quote(a)
		}
		words = append(words, a)
	}
	return strings.Join(words, " ")
}

// env is each of names from the environment, or an error naming the ones that are not set.
func env(names ...string) (map[string]string, error) {
	got := map[string]string{}
	var missing []string
	for _, n := range names {
		v, ok := os.LookupEnv(n)
		if !ok || v == "" {
			missing = append(missing, n)
		}
		got[n] = v
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("not set: %s", strings.Join(missing, ", "))
	}
	return got, nil
}

// say is a line for the run's log, on stdout, where the scripts these verbs replace said theirs.
func say(p programs, format string, a ...any) {
	_, _ = fmt.Fprintf(p.out, format+"\n", a...)
}
