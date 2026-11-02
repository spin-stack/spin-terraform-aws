#!/usr/bin/env bash
# What a destroy has to do in order, held against the dependency graph with no account. A destroy
# takes what depends on a thing before the thing, so the control plane has to go first, one still
# running makes the runners' groups again; then those groups and their machines, which are in no
# state; then the security group a runner sits in, which AWS will not delete with one in it.
#
# Validate does not see this: a graph that waits on itself through a machine AWS holds looks like
# any other, and the fresh install found it after fifteen minutes of DependencyViolation, leaving
# the installation running.
#
# Usage: destroy-order.sh TOFU DIR, DIR initialized.
set -euo pipefail

tofu=${1:?the tofu binary}
dir=${2:?the configuration}

asg='module.controlplane.aws_autoscaling_group.controlplane'
groups='module.runners.terraform_data.runner_groups'
security_group='module.runners.aws_security_group.runner'
template='module.runners.aws_launch_template.runner'

graph=$(mktemp)
trap 'rm -f "${graph}"' EXIT
"${tofu}" -chdir="${dir}" graph -type=plan -no-color >"${graph}"

# reaches FROM TO: whether FROM depends on TO, directly or through anything.
reaches() {
	awk -v from="$1" -v to="$2" '
		function name(s) { gsub(/^[ \t]*"\[root\] | \(expand\)"$|"$/, "", s); return s }
		$2 == "->" || / -> / {
			split($0, side, " -> ")
			a = name(side[1]); b = name(side[2])
			n[a]++; next_of[a, n[a]] = b
		}
		END {
			queue[1] = from; seen[from] = 1
			for (head = 1; head <= tail + 1 && queue[head] != ""; head++) {
				at = queue[head]
				if (at == to) { found = 1; break }
				for (i = 1; i <= n[at]; i++) {
					b = next_of[at, i]
					if (!seen[b]) { seen[b] = 1; queue[++last + 1] = b; tail = last }
				}
			}
			exit found ? 0 : 1
		}' "${graph}"
}

failed=0
must() {
	if ! reaches "$1" "$2"; then
		echo "$1 has to depend on $2: $3" >&2
		failed=1
	fi
}
must_not() {
	if reaches "$1" "$2"; then
		echo "$1 must not depend on $2: $3" >&2
		failed=1
	fi
}

must "${asg}" "${groups}" "the control plane goes first, or it makes the groups again"
must "${groups}" "${security_group}" "the groups and their machines go first, or it waits on a machine in it"
must "${groups}" "${template}" "the groups go first, or one fails to launch from it for as long as it lasts"
must_not "${security_group}" "${groups}" "it would go first, waiting on the machines the groups' removal has yet to take"
must_not "${template}" "${groups}" "it would go before the groups it makes machines for"

if [ "${failed}" -ne 0 ]; then
	exit 1
fi
echo "OK: the control plane, then the runners' groups, then what their machines sit in."
