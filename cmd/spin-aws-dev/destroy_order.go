package main

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
)

func destroyOrderCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "destroy-order TOFU DIR",
		Short: "Fail unless a destroy of DIR, initialized, takes the control plane, then the runners' groups, then what their machines sit in",
		Long: `A destroy takes what depends on a thing before the thing, so the control plane has to go first,
as one still running makes the runners' groups again; then those groups and their machines, which are
in no state; then the security group a runner sits in, which AWS will not delete with one in it.

Validate does not see this: a graph that waits on itself through a machine AWS holds looks like any
other, and the fresh install found it after fifteen minutes of DependencyViolation, leaving the
installation running. This holds TOFU's plan graph of DIR to it, with no account.`,
		Args: cobra.ExactArgs(2),
		RunE: func(c *cobra.Command, args []string) error {
			p := programsOf(c, false)
			dot, err := p.read(args[0], "-chdir="+args[1], "graph", "-type=plan", "-no-color")
			if err != nil {
				return err
			}
			if broken := destroyOrder(dependencies(dot)); len(broken) > 0 {
				_, _ = fmt.Fprintln(p.err, strings.Join(broken, "\n"))
				return exitError{code: 1}
			}
			say(p, "OK: the control plane, then the runners' groups, then what their machines sit in.")
			return nil
		},
	}
}

// dependencies is each resource of a tofu graph and what it depends on directly.
func dependencies(dot string) map[string][]string {
	name := func(s string) string {
		s = strings.Trim(strings.TrimSpace(s), `"`)
		return strings.TrimSuffix(strings.TrimPrefix(s, "[root] "), " (expand)")
	}
	deps := map[string][]string{}
	for _, l := range strings.Split(dot, "\n") {
		if a, b, ok := strings.Cut(l, " -> "); ok {
			deps[name(a)] = append(deps[name(a)], name(b))
		}
	}
	return deps
}

// destroyOrder is what in deps breaks the order a destroy has to happen in, a line each.
func destroyOrder(deps map[string][]string) []string {
	const (
		asg           = "module.controlplane.aws_autoscaling_group.controlplane"
		groups        = "module.runners.terraform_data.runner_groups"
		securityGroup = "module.runners.aws_security_group.runner"
		template      = "module.runners.aws_launch_template.runner"
	)
	var broken []string
	for _, r := range []struct {
		from, to string
		must     bool
		why      string
	}{
		{asg, groups, true, "the control plane goes first, or it makes the groups again"},
		{groups, securityGroup, true, "the groups and their machines go first, or it waits on a machine in it"},
		{groups, template, true, "the groups go first, or one fails to launch from it for as long as it lasts"},
		{securityGroup, groups, false, "it would go first, waiting on the machines the groups' removal has yet to take"},
		{template, groups, false, "it would go before the groups it makes machines for"},
	} {
		if reaches(deps, r.from, r.to) != r.must {
			broken = append(broken, fmt.Sprintf("%s %s %s: %s", r.from, map[bool]string{true: "has to depend on", false: "must not depend on"}[r.must], r.to, r.why))
		}
	}
	return broken
}

// reaches is whether from depends on to, directly or through anything.
func reaches(deps map[string][]string, from, to string) bool {
	seen := map[string]bool{from: true}
	for queue := []string{from}; len(queue) > 0; queue = queue[1:] {
		if queue[0] == to {
			return true
		}
		for _, d := range deps[queue[0]] {
			if !seen[d] {
				seen[d] = true
				queue = append(queue, d)
			}
		}
	}
	return false
}
