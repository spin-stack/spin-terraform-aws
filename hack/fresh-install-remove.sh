#!/usr/bin/env bash
# The fresh install's removal (.github/workflows/fresh-install.yml): at the end of a run, and at the
# start of the next on whatever that one left. One removal for both, so what a teardown could not
# remove is removed the same way by the run after it, and nobody cleans the account by hand.
#
#   1. The installation, while bootstrap's bucket holds its state: the README's removal.
#   2. What still carries the installation's tag: said, and a key of it scheduled for deletion.
#   3. Bootstrap, once the installation's state holds nothing - before, that state is what finds
#      what is left. By the names bootstrap/ gives in this region: its own state is a file on the
#      runner that applied it, gone with that runner.
#
# Nothing stops at the first failure: each is said, the rest goes on where that is safe, and the
# exit says whether any failed. Nothing is removed by a pattern, only by the exact names and ids
# bootstrap/ and the installation give, in this region.
set -uo pipefail

# The account publishes Spin OS from another region with a bootstrap of the same names: removed
# by name there, these are the keys every image is signed with.
if [ "${AWS_REGION:-}" != us-east-1 ] || [ "${TF_VAR_name:-}" != fresh ]; then
  echo "::error::this removes the fresh install, fresh in us-east-1, and nothing else (AWS_REGION=${AWS_REGION:-}, TF_VAR_name=${TF_VAR_name:-})"
  exit 2
fi
cd "$(dirname "$0")/.." || exit 2
region=${AWS_REGION}
name=${TF_VAR_name}
install=examples/complete
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}" "${install}/decommission_override.tf"' EXIT

failed=0
fail() {
  echo "::error::$*"
  failed=1
}

account=$(aws sts get-caller-identity --query Account --output text) || exit 1
# bootstrap/main.tf's local.bucket and local.alias, and publish.tf's secure_boot aliases.
bucket="spin-tofu-state-${account}-${region}"
state_alias=alias/spin-tofu-state
boot_aliases=(alias/spin-os-secureboot-db-control-plane alias/spin-os-secureboot-db-runner alias/spin-os-secureboot-db-proxy)

# 0 there, 1 not, 2 cannot tell - which is never read as not. Only this account's buckets are
# listed, so one of that name in another account is not this.
bucket_exists() {
  local out
  out=$(aws s3api list-buckets --query "Buckets[?Name=='${bucket}'].Name" --output text) || return 2
  [ "${out}" = "${bucket}" ]
}

# A key already pending deletion, or gone, is one an earlier removal scheduled.
schedule() {
  local out
  if ! out=$(aws kms describe-key --key-id "$1" --query KeyMetadata.KeyState --output text 2>&1); then
    [[ ${out} == *NotFound* ]] && return 0
    echo "${out}" >&2
    fail "key $1 could not be described"
    return 1
  fi
  [ "${out}" = PendingDeletion ] && return 0
  local state=${out}
  if ! out=$(aws kms schedule-key-deletion --key-id "$1" --pending-window-in-days 7 --query KeyId --output text 2>&1); then
    echo "${out}" >&2
    fail "key $1 (${state}) was not scheduled for deletion"
    return 1
  fi
  echo "key ${out} scheduled for deletion"
}

# Its key first, then the alias: a key that refused stays findable by the alias the next run reads.
retire() {
  local key
  if ! key=$(aws kms describe-key --key-id "$1" --query KeyMetadata.KeyId --output text 2>&1); then
    [[ ${key} == *NotFound* ]] && return 0
    echo "${key}" >&2
    fail "$1 could not be described"
    return 1
  fi
  schedule "${key}" || return 1
  aws kms delete-alias --alias-name "$1" || { fail "$1 was not deleted"; return 1; }
  echo "$1 deleted"
}

# The installation's managed resources still in its state, into `left`; false when the state
# could not be read, so nothing is concluded from it.
remaining() {
  local shown
  shown=$(tofu -chdir="${install}" show -json) || return 1
  left=$(jq -r '.values.root_module // {} | .. | objects | select(has("address") and .mode? == "managed") | .address' <<< "${shown}") || return 1
}

# Every version's legal hold lifted, in each Object Lock bucket the state has: the README's
# removal, step 2. A bucket already gone has nothing to lift.
unhold() {
  local buckets b out key id
  if ! buckets=$(tofu -chdir="${install}" show -json | jq -r '.. | objects | select(.mode? == "managed" and .type? == "aws_s3_bucket" and .values.object_lock_enabled? == true) | .values.bucket'); then
    fail "the installation's locked buckets could not be read"
    return
  fi
  for b in ${buckets}; do
    if ! out=$(aws s3api list-object-versions --bucket "${b}" --expected-bucket-owner "${account}" --output json 2> "${tmp}/err"); then
      grep -q NoSuchBucket "${tmp}/err" || fail "${b}'s versions could not be listed: $(< "${tmp}/err")"
      continue
    fi
    while IFS=$'\t' read -r key id; do
      aws s3api put-object-legal-hold --bucket "${b}" --expected-bucket-owner "${account}" --key "${key}" \
        --version-id "${id}" --legal-hold Status=OFF || fail "${b}/${key} (${id}) is still held"
    done < <(jq -r '(.Versions // [])[] | [.Key, .VersionId] | @tsv' <<< "${out}")
  done
}

# The README's removal, as an operator runs it: decommission applied to the buckets the state has,
# what refuses a destroy taken out of the state, the destroy, and the keys. -lock=false: the
# workflow's concurrency group is the lock, and a run killed mid-apply left its own behind.
installation() {
  # bootstrap's `init` output, which needs bootstrap's state; the next run has only the names.
  if ! tofu -chdir="${install}" init -reconfigure -lockfile=readonly -input=false \
    -backend-config="bucket=${bucket}" -backend-config="region=${region}"; then
    fail "${install} did not initialise against ${bucket}"
    return
  fi
  # The domain the state's installation was made on: an earlier run's is not this one's, and a
  # plan with another would move what is named for it.
  local dashboard
  if dashboard=$(tofu -chdir="${install}" output -raw dashboard 2> /dev/null); then
    export TF_VAR_domain=${dashboard#https://app.}
  fi
  printf 'module "spin" {\n  decommission = true\n}\n' > "${install}/decommission_override.tf"
  local addresses
  if ! addresses=$(tofu -chdir="${install}" state list); then
    fail "the installation's state could not be listed"
    return
  fi
  local targets kept keys
  targets=$(grep -E '\.aws_s3_bucket(_policy)?\.[a-z]+(\[0\])?$' <<< "${addresses}" | sed 's/^/-target=/')
  if [ -n "${targets}" ]; then
    # shellcheck disable=SC2086 # one -target= per word
    tofu -chdir="${install}" apply -auto-approve -lock=false ${targets} || fail "decommission was not applied"
  fi
  unhold
  # `// empty`: an install that stopped halfway has a key with no id yet (run 39161868759).
  keys=$(tofu -chdir="${install}" show -json | jq -r '.. | objects | select(.mode? == "managed" and .type? == "aws_kms_key") | .values.key_id // empty') ||
    fail "the installation's keys could not be read"
  kept=$(grep -E '\.aws_kms_key\.|\.tls_(private_key|self_signed_cert)\.ca$' <<< "${addresses}")
  if [ -n "${kept}" ]; then
    # shellcheck disable=SC2086 # one address per word
    tofu -chdir="${install}" state rm -lock=false ${kept} || fail "the keys and the CA were not taken out of the state"
  fi
  # Keys only after a destroy: one that failed leaves them usable to what it left. They are out of
  # the state by then; the tag sweep below schedules them once the state is empty.
  if tofu -chdir="${install}" destroy -auto-approve -lock=false; then
    for id in ${keys}; do schedule "${id}"; done
  else
    fail "the destroy failed; its keys are kept: ${keys//$'\n'/ }"
  fi
  rm -f "${install}/decommission_override.tf"
}

# Whether what the tagging API names is still there, which it is behind by minutes: 0 there, 1
# gone, 2 cannot tell.
real() {
  local arn=$1 id=${1##*/} group out
  local -a ask
  case "${arn}" in
    *:ec2:*:instance/*) ask=(ec2 describe-instances --instance-ids "${id}" --query "Reservations[].Instances[?State.Name!='terminated'][].InstanceId") ;;
    *:ec2:*:vpc/*) ask=(ec2 describe-vpcs --vpc-ids "${id}" --query 'Vpcs[].VpcId') ;;
    *:ec2:*:subnet/*) ask=(ec2 describe-subnets --subnet-ids "${id}" --query 'Subnets[].SubnetId') ;;
    *:ec2:*:security-group/*) ask=(ec2 describe-security-groups --group-ids "${id}" --query 'SecurityGroups[].GroupId') ;;
    *:ec2:*:security-group-rule/*) ask=(ec2 describe-security-group-rules --security-group-rule-ids "${id}" --query 'SecurityGroupRules[].SecurityGroupRuleId') ;;
    *:ec2:*:route-table/*) ask=(ec2 describe-route-tables --route-table-ids "${id}" --query 'RouteTables[].RouteTableId') ;;
    *:ec2:*:internet-gateway/*) ask=(ec2 describe-internet-gateways --internet-gateway-ids "${id}" --query 'InternetGateways[].InternetGatewayId') ;;
    *:ec2:*:elastic-ip/*) ask=(ec2 describe-addresses --allocation-ids "${id}" --query 'Addresses[].AllocationId') ;;
    *:ec2:*:vpc-endpoint/*) ask=(ec2 describe-vpc-endpoints --vpc-endpoint-ids "${id}" --query "VpcEndpoints[?State!='deleted'].VpcEndpointId") ;;
    *:ec2:*:vpc-flow-log/*) ask=(ec2 describe-flow-logs --flow-log-ids "${id}" --query 'FlowLogs[].FlowLogId') ;;
    *:ec2:*:launch-template/*) ask=(ec2 describe-launch-templates --launch-template-ids "${id}" --query 'LaunchTemplates[].LaunchTemplateId') ;;
    *:ec2:*:volume/*) ask=(ec2 describe-volumes --volume-ids "${id}" --query 'Volumes[].VolumeId') ;;
    *:ec2:*:network-interface/*) ask=(ec2 describe-network-interfaces --network-interface-ids "${id}" --query 'NetworkInterfaces[].NetworkInterfaceId') ;;
    arn:*:s3:::*) ask=(s3api list-buckets --query "Buckets[?Name=='${arn##*:}'].Name") ;;
    *:ssm:*:parameter/*) ask=(ssm get-parameters --names "/${arn#*:parameter/}" --query 'Parameters[].Name') ;;
    *:logs:*:log-group:*)
      group=${arn#*:log-group:}
      group=${group%:\*}
      ask=(logs describe-log-groups --log-group-name-prefix "${group}" --query "logGroups[?logGroupName=='${group}'].logGroupName")
      ;;
    arn:*:route53:::hostedzone/*) ask=(route53 get-hosted-zone --id "${id}" --query HostedZone.Id) ;;
    *:acm:*:certificate/*) ask=(acm describe-certificate --certificate-arn "${arn}" --query Certificate.CertificateArn) ;;
    *:cloudfront::*:distribution/*) ask=(cloudfront get-distribution --id "${id}" --query Distribution.Id) ;;
    *:iam::*:role/*) ask=(iam get-role --role-name "${id}" --query Role.RoleName) ;;
    *:iam::*:instance-profile/*) ask=(iam get-instance-profile --instance-profile-name "${id}" --query InstanceProfile.InstanceProfileName) ;;
    *:iam::*:policy/*) ask=(iam get-policy --policy-arn "${arn}" --query Policy.Arn) ;;
    *:route53resolver:*:resolver-query-log-config/*) ask=(route53resolver get-resolver-query-log-config --resolver-query-log-config-id "${id}" --query ResolverQueryLogConfig.Id) ;;
    *:budgets::*:budget/*) ask=(budgets describe-budget --account-id "${account}" --budget-name "${id}" --query Budget.BudgetName) ;;
    *) return 2 ;;
  esac
  if ! out=$(aws "${ask[@]}" --output text 2>&1); then
    case "${out}" in *NotFound* | *NoSuch*) return 1 ;; esac
    echo "${out}" >&2
    return 2
  fi
  [ -n "${out}" ] && [ "${out}" != None ]
}

# What the destroy did not know of - made after the state was last written - or could not remove.
# Said rather than removed, since a tag is anybody's to write; but a key of it is scheduled once the
# installation's state is empty, being the one thing a destroy never takes.
tagged() {
  local arns arn state
  if ! arns=$(aws resourcegroupstaggingapi get-resources --tag-filters "Key=spin:installation,Values=${name}" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text); then
    fail "what carries spin:installation=${name} could not be listed"
    return
  fi
  for arn in ${arns}; do
    case "${arn}" in
      None) ;;
      arn:aws:kms:"${region}":"${account}":key/*)
        if ! state=$(aws kms describe-key --key-id "${arn}" --query KeyMetadata.KeyState --output text 2>&1); then
          [[ ${state} == *NotFound* ]] || echo "::warning::left behind, maybe: ${arn}: ${state}"
        elif [ "${state}" = Enabled ] && [ "$1" = empty ]; then
          schedule "${arn}"
        elif [ "${state}" != PendingDeletion ]; then
          echo "::warning::left behind: ${arn} (${state})"
        fi
        ;;
      *)
        real "${arn}"
        case $? in
          0) echo "::warning::left behind: ${arn}" ;;
          2) echo "::warning::left behind, maybe: ${arn}" ;;
        esac
        ;;
    esac
  done
}

# Every version, a thousand at a time (delete-objects' limit), then the bucket.
remove_bucket() {
  local round out
  for round in $(seq 100); do
    if ! aws s3api list-object-versions --bucket "${bucket}" --expected-bucket-owner "${account}" --output json > "${tmp}/versions.json" ||
      ! jq '{Objects: [(.Versions // [])[], (.DeleteMarkers // [])[] | {Key, VersionId}][:1000], Quiet: true}' \
        "${tmp}/versions.json" > "${tmp}/delete.json"; then
      fail "${bucket}'s objects could not be listed"
      return 1
    fi
    jq -e '.Objects | length > 0' "${tmp}/delete.json" > /dev/null || break
    # Quiet: what it prints is only what it could not delete.
    if ! out=$(aws s3api delete-objects --bucket "${bucket}" --expected-bucket-owner "${account}" \
      --delete "file://${tmp}/delete.json" --output json) || jq -e '(.Errors // []) | length > 0' <<< "${out}" > /dev/null 2>&1; then
      echo "${out}" >&2
      fail "${bucket}'s objects were not deleted (round ${round})"
      return 1
    fi
  done
  aws s3api delete-bucket --bucket "${bucket}" --expected-bucket-owner "${account}" || { fail "${bucket} was not deleted"; return 1; }
  echo "${bucket} deleted"
}

# The bucket first, and the state's key only once it is gone: a bucket left with a state in it is
# one the next run opens with that key.
bootstrap() {
  bucket_exists
  case $? in
    0) remove_bucket ;;
    2) fail "whether ${bucket} is there could not be told" ;;
  esac
  for alias in "${boot_aliases[@]}"; do retire "${alias}"; done
  if bucket_exists; then
    fail "${state_alias} is kept: ${bucket} is still there"
  elif [ $? -eq 2 ]; then
    fail "${state_alias} is kept: whether ${bucket} is still there could not be told"
  else
    retire "${state_alias}"
  fi
}

left=""
read_state=true
bucket_exists
case $? in
  1) ;;
  2) read_state=false ;;
  *)
    if ! states=$(aws s3api list-objects-v2 --bucket "${bucket}" --expected-bucket-owner "${account}" --prefix "${name}.tfstate" \
      --query "Contents[?Key=='${name}.tfstate'].Key" --output text); then
      read_state=false
    elif [ "${states}" = "${name}.tfstate" ]; then
      installation
      remaining || read_state=false
    fi
    ;;
esac

if [ "${read_state}" = true ] && [ -z "${left}" ]; then
  tagged empty
  bootstrap
else
  tagged kept
  if [ "${read_state}" = true ]; then
    fail "bootstrap is kept: the installation's state still has ${left//$'\n'/ }, and it is what finds them"
  else
    fail "bootstrap is kept: the installation's state could not be read, so what it still has is not known"
  fi
fi
exit "${failed}"
