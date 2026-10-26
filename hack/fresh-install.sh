#!/usr/bin/env bash
# The fresh install's steps (.github/workflows/fresh-install.yml), one a call: `task fresh-install
# -- <step>`. In bash, and in a file shellcheck reads, as they were in the workflow: the Taskfile's
# own shell has no umask, and a script there is one no linter reads. What a step hands the next -
# a variable, a directory on PATH, an output - goes where GitHub reads it, or to stdout outside a
# run. The removal is fresh-install-remove.sh's, which the run calls at both ends.
#
# Each step runs as GitHub ran it: errexit, and pipefail and nounset where the step asked them.
# TF_VAR_spin_version and TF_VAR_domain are the run's, from the steps release and domain.
# shellcheck disable=SC2154
set -e
cd "$(dirname "$0")/.."

# The newest release this commit can install in the region: an image of every role and its
# measurements. None is a failure: main installs nothing. spin-stack/ami's release publishes in
# the regions its release.yml names, which must include this one.
release() {
  set -euo pipefail
  local release
  release=$(jq -r --arg r "${AWS_REGION}" --slurpfile m measurements.json '[to_entries[] | .key as $v | .value as $img
    | select(all("control-plane", "runner", "proxy"; $img[.][$r] and ($m[0][$v][.] // {} | length > 0))) | $v] | sort | last // empty' images.json)
  if [ -z "${release}" ]; then
    echo "::error::images.json and measurements.json have no release with every role's image and measurements in ${AWS_REGION}: a release must be published in ${AWS_REGION} by spin-stack/ami (release.yml)"
    exit 1
  fi
  echo "TF_VAR_spin_version=${release}" >> "${GITHUB_ENV:-/dev/stdout}"
}

# The CLI of the release installed, from its public package, checked as docs/releases.md in spin
# checks a file: signed by release.yml at main, and its provenance naming this release.
cli() {
  set -euo pipefail
  local identity=https://github.com/spin-stack/spin/.github/workflows/release.yml@refs/heads/main
  local issuer=https://token.actions.githubusercontent.com
  local dir="${RUNNER_TEMP}/cli" built usage
  oras pull --no-tty -o "${dir}" "ghcr.io/spin-stack/spin-release:${TF_VAR_spin_version}-spin-linux-amd64"
  cosign verify-blob --bundle "${dir}/spin-linux-amd64.sigstore.json" --certificate-identity "${identity}" \
    --certificate-oidc-issuer "${issuer}" "${dir}/spin-linux-amd64"
  cosign verify-blob-attestation --type slsaprovenance1 --bundle "${dir}/spin-linux-amd64.provenance.sigstore.json" \
    --digest "$(sha256sum "${dir}/spin-linux-amd64" | cut -d' ' -f1)" --digestAlg sha256 \
    --certificate-identity "${identity}" --certificate-oidc-issuer "${issuer}"
  built=$(jq -r .dsseEnvelope.payload "${dir}/spin-linux-amd64.provenance.sigstore.json" | base64 -d |
    jq -r .predicate.buildDefinition.externalParameters.version)
  if [ "${built}" != "${TF_VAR_spin_version}" ]; then
    echo "::error::spin-linux-amd64 of ${TF_VAR_spin_version} says it was built as ${built}"
    exit 1
  fi
  mkdir -p "${RUNNER_TEMP}/bin"
  install -m 755 "${dir}/spin-linux-amd64" "${RUNNER_TEMP}/bin/spin"
  echo "${RUNNER_TEMP}/bin" >> "${GITHUB_PATH:-/dev/stdout}"
  # Only while the newest release images.json names predates `spin smoke` (v20261015.01 did,
  # when this was written): an older CLI's `smoke --help` is its root's help, exit 0. Once one
  # that has it is merged, a CLI without it is a failure and this goes.
  usage=$("${RUNNER_TEMP}/bin/spin" smoke --help)
  if grep -q '^  spin smoke ' <<< "${usage}"; then
    echo "smoke=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  else
    echo "::warning::spin ${TF_VAR_spin_version} has no 'spin smoke': the installation is signed in to and not used"
  fi
}

# What each run of the last five weeks cost, by its spin:run tag, into the job's summary. Cost
# Explorer answers a day late, and only by a tag the account activated (fresh-install.yml says
# how); what carries no tag - data transfer, some API calls - is in no run's line.
cost() {
  set -euo pipefail
  local runs
  aws ce get-cost-and-usage --time-period "Start=$(date -u -d '-35 days' +%F),End=$(date -u +%F)" \
    --granularity MONTHLY --metrics UnblendedCost \
    --filter '{"Tags": {"Key": "spin:purpose", "Values": ["fresh-install"]}}' \
    --group-by Type=TAG,Key=spin:run > "${RUNNER_TEMP}/cost.json"
  # A month is a period of its own, so a run is summed across the two a window may cross.
  runs=$(jq -r --arg repo "${GITHUB_REPOSITORY:-spin-stack/spin-terraform-aws}" '
    [.ResultsByTime[].Groups[] | {run: (.Keys[0] | sub("^spin:run\\$"; "")), usd: (.Metrics.UnblendedCost.Amount | tonumber)}]
    | group_by(.run) | map({run: .[0].run, usd: (map(.usd) | add)}) | sort_by(.run) | .[]
    | "| \(if .run == "" then "no spin:run" else "[\(.run)](https://github.com/\($repo)/actions/runs/\(.run))" end) | \(.usd * 100 | round / 100) |"' \
    "${RUNNER_TEMP}/cost.json")
  {
    echo "### What the fresh installs cost"
    echo
    if [ -z "${runs}" ]; then
      echo "Nothing in the bill by spin:purpose=fresh-install: the tags are not active yet, or no tagged run is a day old."
    else
      echo "| Run | USD |"
      echo "|---|---|"
      echo "${runs}"
    fi
  } >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
}

domain() {
  set -euo pipefail
  local zone
  zone=$(aws route53 get-hosted-zone --id "${ZONE_ID}" --query HostedZone.Name --output text)
  echo "TF_VAR_domain=r${GITHUB_RUN_NUMBER}.qa.${zone%.}" >> "${GITHUB_ENV:-/dev/stdout}"
}

bootstrap() {
  cd bootstrap
  tofu init -lockfile=readonly
  tofu apply -auto-approve
}

installation() {
  cd examples/complete
  # Bootstrap's output is the whole init command, its backend's arguments included: split as words.
  # shellcheck disable=SC2046
  $(tofu -chdir=../../bootstrap output -raw init) -lockfile=readonly
  tofu apply -auto-approve
}

delegate() {
  set -euo pipefail
  cd examples/complete
  jq -n --arg d "${TF_VAR_domain}" --argjson ns "$(tofu output -json name_servers)" \
    '{Changes: [{Action: "UPSERT", ResourceRecordSet: {Name: $d, Type: "NS", TTL: 60, ResourceRecords: [$ns[] | {Value: .}]}}]}' \
    > "${RUNNER_TEMP}/delegation.json"
  aws route53 change-resource-record-sets --hosted-zone-id "${ZONE_ID}" --change-batch "file://${RUNNER_TEMP}/delegation.json"
}

undelegate() {
  jq '.Changes[0].Action = "DELETE"' "${RUNNER_TEMP}/delegation.json" > "${RUNNER_TEMP}/undelegation.json"
  aws route53 change-resource-record-sets --hosted-zone-id "${ZONE_ID}" --change-batch "file://${RUNNER_TEMP}/undelegation.json"
}

wait-machines() {
  set -euo pipefail
  cd examples/complete
  local group
  for group in $(tofu output -json update_status | jq -r 'keys[]'); do
    until aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${group}" \
      --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService']" --output text | grep -q .; do
      sleep 30
    done
    echo "${group} is in service"
  done
}

# The first sign-in, as the installation's administrator: its session token in
# ${RUNNER_TEMP}/session-token, for the smoke: a session is the person, every procedure an API
# key's scopes would name included.
sign-in() {
  set -euo pipefail
  cd examples/complete
  umask 077
  local sign_in password endpoint token force fresh
  sign_in=$(tofu output -json first_sign_in)
  password=$(eval "$(jq -r .password <<< "${sign_in}")")
  echo "::add-mask::${password}"
  jq -n --arg e "$(jq -r .user <<< "${sign_in}")" --arg p "${password}" '{email: $e, password: $p}' > "${RUNNER_TEMP}/login.json"
  endpoint=$(jq -r .url <<< "${sign_in}")
  until curl -fsS -o "${RUNNER_TEMP}/session.json" -H 'Content-Type: application/json' --data-binary "@${RUNNER_TEMP}/login.json" \
    "${endpoint}/spin.v1.SetupService/PasswordLogin"; do
    sleep 30
  done
  token=$(jq -r '.sessionToken // empty' "${RUNNER_TEMP}/session.json")
  [ -n "${token}" ]
  echo "::add-mask::${token}"
  printf '%s' "${token}" > "${RUNNER_TEMP}/session-token"
  echo "SPIN_ENDPOINT=${endpoint}" >> "${GITHUB_ENV:-/dev/stdout}"
  force=$(jq -r '.forcePasswordChange // false' "${RUNNER_TEMP}/session.json")
  echo "signed in; force_password_change: ${force}"
  # A session opened with the one-time password may only change it (whileChangingThePassword in
  # spin), so it is changed, to one nobody needs again: the session stays, the others go. An
  # upper, a lower and a digit, as the control plane's strength check asks.
  if [ "${force}" = true ]; then
    fresh="Aa1$(openssl rand -hex 24)"
    echo "::add-mask::${fresh}"
    jq -n --arg c "${password}" --arg n "${fresh}" '{currentPassword: $c, newPassword: $n}' > "${RUNNER_TEMP}/change.json"
    printf 'Authorization: Bearer %s\n' "${token}" > "${RUNNER_TEMP}/bearer"
    curl -fsS -o /dev/null -H 'Content-Type: application/json' -H "@${RUNNER_TEMP}/bearer" \
      --data-binary "@${RUNNER_TEMP}/change.json" "${endpoint}/spin.v1.SetupService/ChangePassword"
    rm "${RUNNER_TEMP}/change.json" "${RUNNER_TEMP}/bearer"
  fi
  rm "${RUNNER_TEMP}/login.json" "${RUNNER_TEMP}/session.json"
}

# `spin smoke` as the administrator signed in, with a key of their own.
smoke() {
  set -euo pipefail
  export HOME="${RUNNER_TEMP}/spin-home"
  SPIN_TOKEN=$(cat "${RUNNER_TEMP}/session-token")
  export SPIN_TOKEN
  mkdir -m 700 "${HOME}" "${HOME}/.ssh"
  ssh-keygen -q -t ed25519 -N '' -C fresh-install -f "${HOME}/.ssh/id_ed25519"
  spin ssh-key add fresh-install "${HOME}/.ssh/id_ed25519.pub"
  spin sign --yes
  local status=0 failed why
  spin -o json smoke --timeout 20m > "${RUNNER_TEMP}/smoke.json" || status=$?
  jq . "${RUNNER_TEMP}/smoke.json" || cat "${RUNNER_TEMP}/smoke.json"
  if [ "${status}" -ne 0 ]; then
    failed=$(jq -r '[.steps[]? | select(.error) | .step] | join(", ")' "${RUNNER_TEMP}/smoke.json" 2> /dev/null || true)
    case "${status}" in
      69) why="the installation did not answer" ;;
      70) why="a scenario failed: ${failed}" ;;
      77) why="the session was refused" ;;
      *) why="it could not run as configured" ;;
    esac
    echo "::error::spin smoke exited ${status}: ${why}"
    exit "${status}"
  fi
}

# What each machine's boot said and each group's update did, by the commands the installation's
# outputs give: one that fails does not hide the rest.
why() {
  cd examples/complete
  tofu output -json boot_log | jq -r '.[] | rtrimstr(" --follow")' | while read -r cmd; do eval "${cmd}" || true; done
  tofu output -json update_status | jq -r '.[]' | while read -r cmd; do eval "${cmd}" || true; done
}

case "${1:-}" in
  release | cli | cost | domain | bootstrap | installation | delegate | undelegate | wait-machines | sign-in | smoke | why) "$1" ;;
  *)
    echo "usage: $0 release|cli|cost|domain|bootstrap|installation|delegate|undelegate|wait-machines|sign-in|smoke|why" >&2
    exit 2
    ;;
esac
