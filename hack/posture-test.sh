#!/usr/bin/env bash
# The fresh install's posture step (hack/fresh-install.sh posture) judges what AWS answers with the
# filters in hack/posture/. Each is run here on a recorded answer that keeps every promise - which
# must say nothing - and on the same answer with one value changed, which must say what broke: a
# filter that says nothing of anything passes the first half alone.
set -euo pipefail
cd "$(dirname "$0")/posture"

failed=0
ips='["198.51.100.10","198.51.100.11","10.0.1.10","10.0.1.11"]'

# check <case> <fixture> <change, a jq program> <what the filter must say, or empty> <filter> [jq args...]
check() {
  local name=$1 fixture=$2 change=$3 want=$4 filter=$5
  shift 5
  local got
  got=$(jq "${change}" "testdata/${fixture}" | jq -r -f "${filter}" "$@")
  if [ -z "${want}" ] && [ -n "${got}" ]; then
    echo "FAIL ${name}: a recorded answer that keeps every promise was judged broken:"
    echo "${got}"
    failed=1
  elif [ -n "${want}" ] && ! grep -qF -- "${want}" <<< "${got}"; then
    echo "FAIL ${name}: want a line with '${want}', got:"
    echo "${got:-(nothing)}"
    failed=1
  fi
}

i='.Reservations[0].Instances[1]'
check "instances keep their promises" instances.json . "" instances.jq
check "IMDSv1" instances.json "${i}.MetadataOptions.HttpTokens = \"optional\"" "i-0aaaaaaaaaaaaaaa2: the metadata service answers IMDSv1" instances.jq
check "two hops" instances.json "${i}.MetadataOptions.HttpPutResponseHopLimit = 2" "answers 2 hops away" instances.jq
check "IPv6" instances.json "${i}.MetadataOptions.HttpProtocolIpv6 = \"enabled\"" "answers on IPv6" instances.jq
check "tags" instances.json "${i}.MetadataOptions.InstanceMetadataTags = \"enabled\"" "says the instance's tags" instances.jq
check "legacy BIOS" instances.json "${i}.CurrentInstanceBootMode = \"legacy-bios\"" "boot mode legacy-bios" instances.jq

check "volumes encrypted" volumes.json . "" volumes.jq
check "a volume in the clear" volumes.json '.Volumes[1].Encrypted = false' "vol-0aaaaaaaaaaaaaaa2 on i-0aaaaaaaaaaaaaaa2: not encrypted" volumes.jq

check "nothing denied is allowed" denied.json . "" reach.jq --arg want denied
check "a denied action allowed" denied.json '.EvaluationResults[0].EvalDecision = "allowed"' "iam:CreateRole on *: allowed, want denied" reach.jq --arg want denied
check "everything allowed is allowed" allowed.json . "" reach.jq --arg want allowed
check "an allowed action denied" allowed.json '.EvaluationResults[0].EvalDecision = "implicitDeny"' "logs:PutLogEvents" reach.jq --arg want allowed

check "the trail is the machines'" trail.json . "" trail.jq --argjson ips "${ips}"
check "a refused call" trail.json '.Events[0].CloudTrailEvent |= (fromjson | .errorCode = "AccessDenied" | tojson)' "CreateLogStream was refused (AccessDenied)" trail.jq --argjson ips "${ips}"
check "a call from elsewhere" trail.json '.Events[1].CloudTrailEvent |= (fromjson | .sourceIPAddress = "203.0.113.9" | tojson)' "GetCallerIdentity from 203.0.113.9" trail.jq --argjson ips "${ips}"

if [ "${failed}" -ne 0 ]; then
  exit 1
fi
echo "OK: every posture filter says nothing of a kept promise and names each broken one."
