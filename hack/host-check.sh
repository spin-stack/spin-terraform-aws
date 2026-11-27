#!/usr/bin/env bash
# Run on a runner, as root, through a host shell (hack/fresh-install.sh host-check), while a
# workspace runs on it: what keeps a machine's QEMU, and the host's egress namespace, from the
# host's role, looked at on a real EC2 instance with a real metadata service answering it. spin's
# lanes check the same in QEMU under QEMU, where no metadata service is real. It stays shell: the
# runner has nothing else this repository builds, and the script reaches it over a terminal.
#
# One line per check, `CHECK <name> ok` or `CHECK <name> FAIL <why>`, `INFO` lines for what is
# only shown, and `HOST-CHECK-END` last: a session cut short says so by its absence. Nothing here
# changes the host, which the shell retires once it ends anyway.
set -u

imds=169.254.169.254
# Kept until the end and said at once: the terminal echoes what was typed as it arrives, and a
# line said while that echo runs can be cut in two by it.
results=$(mktemp)
say() { echo "$*" >> "${results}"; }
# check NAME WHY COMMAND...: NAME is ok when COMMAND succeeds, and fails with WHY when it does not.
check() { if "${@:3}"; then say "CHECK $1 ok"; else say "CHECK $1 FAIL $2"; fi; }
# unreachable PREFIX...: the metadata service refuses a connection made through PREFIX (nsenter, ip netns exec).
unreachable() { ! "$@" timeout 3 bash -c "exec 3<>/dev/tcp/${imds}/80" 2> /dev/null; }

# The host's own root reaches the metadata service: every "cannot" below is about who asks, not a
# service that is down.
check host-root-reaches-imds "the host's root got no IMDSv2 token: the checks below prove nothing" \
  test -n "$(curl -s -m 3 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' "http://${imds}/latest/api/token")"

qemus=()
for exe in /proc/[0-9]*/exe; do
  case "$(readlink "${exe}" 2> /dev/null)" in */qemu-system-*) pid=${exe#/proc/} && qemus+=("${pid%/exe}") ;; esac
done
[ "${#qemus[@]}" -gt 0 ] || say "CHECK machines-running FAIL no qemu-system process on this runner: there is nothing to look at"

for pid in "${qemus[@]}"; do
  read -r uid capeff < <(awk '/^Uid:/ {u = $2} /^CapEff:/ {c = $2} END {print u, c}' "/proc/${pid}/status")
  links=$(nsenter -t "${pid}" -n ip -o link show | awk -F': ' '{print $2}' | tr '\n' ' ')
  check "qemu-${pid}-uid" "runs as ${uid}, not a machine's own uid" test "${uid}" -ge $((0x70000000))
  check "qemu-${pid}-capabilities" "holds capabilities ${capeff}" test "${capeff}" = 0000000000000000
  check "qemu-${pid}-root" "sees the host's whole filesystem" test "$(readlink "/proc/${pid}/root")" != /
  check "qemu-${pid}-environment" "has an environment" test "$(tr -d '\0' < "/proc/${pid}/environ" | wc -c)" -eq 0
  check "qemu-${pid}-network" "its namespace has links: ${links}" test "${links}" = "lo "
  check "qemu-${pid}-imds" "connects to the metadata service from its namespace" unreachable nsenter -t "${pid}" -n
  say "INFO qemu-${pid} $(grep -E '^(NoNewPrivs|Seccomp):' "/proc/${pid}/status" | tr '\n\t' '  ')"
done

# The egress proxy's namespace: what a proxy a tenant took could send from.
if [ ! -e /run/netns/spin-egress ]; then
  say "CHECK egress-imds FAIL this runner has no egress namespace: a refused connection would prove nothing"
else
  check egress-imds "the egress namespace connects to the metadata service" unreachable ip netns exec spin-egress
fi

if [ -d /run/credstore ]; then
  mode=$(stat -c '%a %U' /run/credstore)
  check credstore "/run/credstore is ${mode}, not 700 root" test "${mode}" = "700 root"
fi

for unit in spin-runner.service spin-boot.service; do
  say "INFO ${unit} $(systemd-analyze security --no-pager "${unit}" 2> /dev/null | tail -n 1)"
done
sleep 2
echo
cat "${results}"
rm -f "${results}"
echo HOST-CHECK-END
