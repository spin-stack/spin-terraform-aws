package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// A plan graph as tofu writes it, in the order a destroy has to happen in, part of it through a
// resource in between.
const destroyGraph = `digraph {
	"[root] module.controlplane.aws_autoscaling_group.controlplane (expand)" -> "[root] module.controlplane.aws_launch_template.controlplane (expand)"
	"[root] module.controlplane.aws_launch_template.controlplane (expand)" -> "[root] module.runners.terraform_data.runner_groups (expand)"
	"[root] module.runners.terraform_data.runner_groups (expand)" -> "[root] module.runners.aws_launch_template.runner (expand)"
	"[root] module.runners.aws_launch_template.runner (expand)" -> "[root] module.runners.aws_security_group.runner (expand)"
}`

func TestDestroyOrder(t *testing.T) {
	for _, c := range []struct {
		name, graph, want string
		status            int
	}{
		{"in order", destroyGraph, "", 0},
		{"the control plane goes after the groups", strings.Replace(destroyGraph,
			`-> "[root] module.runners.terraform_data.runner_groups (expand)"`, `-> "[root] module.runners.aws_security_group.runner (expand)"`, 1),
			"module.controlplane.aws_autoscaling_group.controlplane has to depend on module.runners.terraform_data.runner_groups", 1},
		{"the security group goes before the groups", destroyGraph + "\n" +
			`"[root] module.runners.aws_security_group.runner (expand)" -> "[root] module.runners.terraform_data.runner_groups (expand)"`,
			"module.runners.aws_security_group.runner must not depend on module.runners.terraform_data.runner_groups", 1},
	} {
		t.Run(c.name, func(t *testing.T) {
			graph := filepath.Join(t.TempDir(), "graph")
			put(t, graph, c.graph, 0o644)
			calls := fakes(t, map[string]string{"tofu": "cat " + graph})
			stdout, stderr, status := verb(t, "destroy-order", "tofu", "dir")
			if status != c.status || !strings.Contains(stderr, c.want) || (c.status == 0) != strings.HasPrefix(stdout, "OK:") {
				t.Errorf("exit %d\nstdout: %s\nstderr: %s", status, stdout, stderr)
			}
			if got := read(t, calls); got != "tofu -chdir=dir graph -type=plan -no-color\n" {
				t.Errorf("ran %q", got)
			}
		})
	}
}

func TestDestroyOrderExitsAsTofuDoes(t *testing.T) {
	fakes(t, map[string]string{"tofu": "exit 3"})
	if _, stderr, status := verb(t, "destroy-order", "tofu", "dir"); status != 3 {
		t.Errorf("exit %d: %s", status, stderr)
	}
}
