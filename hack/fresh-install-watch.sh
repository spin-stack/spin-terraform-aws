#!/usr/bin/env bash
# The fresh install's watch (.github/workflows/fresh-install-watch.yml): between runs, nothing of it
# should be in the account. A run that failed to remove itself otherwise costs by the hour until the
# next one, a week later, with only a failed run in a list to say so. So anything found is removed
# as a run removes it, and what cannot be removed is an open issue, assigned to whoever answers for
# the account, which this closes once the account is clean.
#
# It shares the runs' concurrency group, so it never looks at an installation a run is making.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

label=fresh-install-left-behind
report=$(mktemp)
trap 'rm -f "${report}"' EXIT

open_issue() {
  gh issue list --label "${label}" --state open --limit 1 --json number --jq '.[0].number // empty'
}

if bash hack/fresh-install-remove.sh --list; then
  echo "nothing of the fresh install is in the account"
  issue=$(open_issue) && [ -n "${issue}" ] && gh issue close "${issue}" --comment "The account is clean: ${RUN_URL}"
  exit 0
fi

echo "::warning::the fresh install left things in the account: removing them"
bash hack/fresh-install-remove.sh
if bash hack/fresh-install-remove.sh --list > "${report}" 2>&1; then
  echo "removed"
  issue=$(open_issue) && [ -n "${issue}" ] && gh issue close "${issue}" --comment "Removed by the watch: ${RUN_URL}"
  exit 0
fi
cat "${report}"

fence=$(printf '\140\140\140')
body=$(printf 'The watch could not remove what the fresh install left in the account, and it goes on costing until it is gone. It tries again on its next run.\n\nRun: %s\n\n%s\n%s\n%s\n' \
  "${RUN_URL}" "${fence}" "$(sed -E 's/^::[a-z]+:://' "${report}" | cut -c1-200 | head -60)" "${fence}")
gh label create "${label}" --color B60205 --description "The fresh install left something in AWS" --force
if issue=$(open_issue) && [ -n "${issue}" ]; then
  gh issue comment "${issue}" --body "${body}"
else
  gh issue create --title "The fresh install left things in AWS" --label "${label}" --assignee "${ALERT_ASSIGNEE}" --body "${body}"
fi
exit 1
