#!/usr/bin/env bash
# This module's next release (.github/workflows/release.yml, which says why): GITHUB_SHA tagged as
# the next v<YYYYMMDD>.<NN> today, in UTC, with its GitHub release, as GH_TOKEN in
# GITHUB_REPOSITORY. A file shellcheck reads, as the workflow's step was.
set -euo pipefail
cd "$(dirname "$0")/.."

sha=${GITHUB_SHA}
repo=${GITHUB_REPOSITORY}

# Only a commit Gate passed on: a release is what an installation that follows them is proposed
# next, and nothing after this step looks at the commit again. The latest Gate run, so a run
# again that passed is the one that counts.
gate=$(gh api "repos/${repo}/commits/${sha}/check-runs?check_name=Gate" --jq '.check_runs[0].conclusion // empty')
if [ "${gate}" != success ]; then
  echo "Gate has not passed on ${sha} (${gate:-no run}): nothing is released"
  exit 1
fi

# Named as spin names its own (hack/releaseversion there): one past today's highest, two digits
# at least, and only a tag spelled exactly so is counted - a candidate's suffix (-rc1) does not use
# up its number. Every tag there is, from the remote, not what the checkout happened to fetch.
day=$(date -u +%Y%m%d)
last=$(git ls-remote --tags --refs origin "refs/tags/v${day}.*" | sed -E 's|.*refs/tags/||' |
  { grep -E "^v${day}\.(0[1-9]|[1-9][0-9]+)$" || true; } | sed -E "s/^v${day}\.//" | sort -n | tail -1)
version=$(printf 'v%s.%02d' "${day}" "$((10#${last:-0} + 1))")

# The one before, by the same order, for what changed since: shipset's (edit.Newer) - the day,
# then the number, a longer number the later.
previous=$(git ls-remote --tags --refs origin 'refs/tags/v*' | sed -E 's|.*refs/tags/||' |
  { grep -E '^v[0-9]{8}\.[0-9]+$' || true; } | awk -F. '{ printf "%s %08d %s\n", $1, $2, $0 }' | sort | tail -1 | cut -d' ' -f3)

spin=$(jq -r 'keys | sort | last' images.json)
notes=$(mktemp)
trap 'rm -f "${notes}"' EXIT
{
  echo '## Using this release'
  echo
  echo '```hcl'
  echo 'module "spin" {'
  echo "  source       = \"github.com/spin-stack/spin-terraform-aws?ref=${version}\""
  echo "  spin_version = \"${spin}\""
  echo '}'
  echo '```'
  echo
  echo "Its \`images.json\` has spin releases up to ${spin}; an installation's \`spin_version\` is one with an image in its region. How an installation takes it is the README's \"Updating\"."
  if [ -n "${previous}" ]; then
    echo
    echo "What changed since ${previous}: ${GITHUB_SERVER_URL}/${repo}/compare/${previous}...${version}"
  fi
} > "${notes}"

# The tag is made by the release, at the commit, in one call: no tag without its release.
gh release create "${version}" -R "${repo}" --target "${sha}" --title "${version}" --notes-file "${notes}"
echo "Released ${version} at ${sha}"
