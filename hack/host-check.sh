#!/usr/bin/env bash
# Run on a runner, as root, through a host shell (hack/fresh-install.sh host-check), while a
# workspace runs on it: what keeps a machine's QEMU, and the host's egress namespace, from the
# host's role, looked at on a real EC2 instance with a real metadata service answering it. spin's
# lanes check the same in QEMU under QEMU, where no metadata service is real.
#
# One line per check, `CHECK <name> ok` or `CHECK <name> FAIL <why>`, `INFO` lines for what is
# only shown, and `HOST-CHECK-END` last: a session cut short says so by its absence. Nothing here
# changes the host, which the shell retires once it ends anyway.
set -u

imds=169.254.169.254
machine_uids=$((0x70000000))
# Kept until the end and said at once: the terminal echoes what was typed as it arrives, and a
# line said while that echo runs can be cut in two by it.
results=$(mktemp)
say() { echo "$*" >> "${results}"; }
ok() { say "CHECK $1 ok"; }
fail() { say "CHECK $1 FAIL $2"; }

# The host's own root reaches the metadata service: every "cannot" below is about who asks, not a
# service that is down.
if [ -n "$(curl -s -m 3 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' "http://${imds}/latest/api/token")" ]; then
  ok host-root-reaches-imds
else
  fail host-root-reaches-imds "the host's root got no IMDSv2 token: the checks below prove nothing"
fi

qemus=()
for exe in /proc/[0-9]*/exe; do
  case "$(readlink "${exe}" 2> /dev/null)" in
    */qemu-system-*) pid=${exe#/proc/} && qemus+=("${pid%/exe}") ;;
  esac
done
if [ "${#qemus[@]}" -eq 0 ]; then
  fail machines-running "no qemu-system process on this runner: there is nothing to look at"
fi

for pid in "${qemus[@]}"; do
  uid=$(awk '/^Uid:/ {print $2}' "/proc/${pid}/status")
  if [ "${uid}" -ge "${machine_uids}" ]; then ok "qemu-${pid}-uid"; else fail "qemu-${pid}-uid" "runs as ${uid}, not a machine's own uid"; fi

  capeff=$(awk '/^CapEff:/ {print $2}' "/proc/${pid}/status")
  if [ "${capeff}" = 0000000000000000 ]; then ok "qemu-${pid}-capabilities"; else fail "qemu-${pid}-capabilities" "holds capabilities ${capeff}"; fi

  if [ "$(readlink "/proc/${pid}/root")" != / ]; then ok "qemu-${pid}-root"; else fail "qemu-${pid}-root" "sees the host's whole filesystem"; fi

  if [ "$(tr -d '\0' < "/proc/${pid}/environ" | wc -c)" -eq 0 ]; then ok "qemu-${pid}-environment"; else fail "qemu-${pid}-environment" "has an environment"; fi

  links=$(nsenter -t "${pid}" -n ip -o link show | awk -F': ' '{print $2}' | tr '\n' ' ')
  if [ "${links}" = "lo " ]; then ok "qemu-${pid}-network"; else fail "qemu-${pid}-network" "its namespace has links: ${links}"; fi

  if nsenter -t "${pid}" -n timeout 3 bash -c "exec 3<>/dev/tcp/${imds}/80" 2> /dev/null; then
    fail "qemu-${pid}-imds" "connects to the metadata service from its namespace"
  else
    ok "qemu-${pid}-imds"
  fi
  say "INFO qemu-${pid} $(grep -E '^(NoNewPrivs|Seccomp):' "/proc/${pid}/status" | tr '\n\t' '  ')"
done

# The egress proxy's namespace: what a proxy a tenant took could send from.
if [ ! -e /run/netns/spin-egress ]; then
  fail egress-imds "this runner has no egress namespace: a refused connection would prove nothing"
elif ip netns exec spin-egress timeout 3 bash -c "exec 3<>/dev/tcp/${imds}/80" 2> /dev/null; then
  fail egress-imds "the egress namespace connects to the metadata service"
else
  ok egress-imds
fi

if [ -d /run/credstore ]; then
  mode=$(stat -c '%a %U' /run/credstore)
  if [ "${mode}" = "700 root" ]; then ok credstore; else fail credstore "/run/credstore is ${mode}, not 700 root"; fi
fi

for unit in spin-runner.service spin-boot.service; do
  say "INFO ${unit} $(systemd-analyze security --no-pager "${unit}" 2> /dev/null | tail -n 1)"
done
sleep 2
echo
cat "${results}"
rm -f "${results}"
echo HOST-CHECK-END
