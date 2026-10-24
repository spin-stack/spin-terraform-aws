#!/usr/bin/env bash
# This commit proposed to one deployment (.github/workflows/propose.yml, which says why and how):
# REPOSITORY (spin-stack/<deployment>) in REGION, as the app GH_TOKEN and APP_SLUG are, at the ref
# GitHub's GITHUB_* variables name. A file shellcheck reads, as the workflow's step was.
set -euo pipefail
cd "$(dirname "$0")/.."

# The ref the deployment names: a release's tag, which is what its users follow, or the commit on
# main.
if [ "${GITHUB_REF_TYPE}" = tag ]; then ref="${GITHUB_REF_NAME}"; else ref="${GITHUB_SHA::7}"; fi
# The newest release with every role's image in the region: releases are v<YYYYMMDD>.<NN>, which
# sort as text.
release=$(jq -r --arg r "${REGION}" '[to_entries[] | select(.value["control-plane"][$r] and .value.runner[$r] and .value.proxy[$r]) | .key] | sort | last // empty' images.json)
if [ -z "${release}" ]; then
  echo "images.json has no release with an image in ${REGION}"
  exit 1
fi

gh auth setup-git
id=$(gh api "/users/${APP_SLUG}[bot]" --jq .id)
git config --global user.name "${APP_SLUG}[bot]"
git config --global user.email "${id}+${APP_SLUG}[bot]@users.noreply.github.com"

gh repo clone "${REPOSITORY}" deployment -- --quiet --depth 1
cd deployment
sed -i -E "s|(github.com/spin-stack/spin-terraform-aws\?ref=)[^\"]+|\1${ref}|" main.tf
sed -i -E "s|^(spin_version *= *)\"[^\"]*\"|\1\"${release}\"|" terraform.tfvars
if git diff --quiet; then
  echo "${REPOSITORY} is at ${ref} and ${release} already"
  exit 0
fi

# One branch per deployment, rewritten by each run: the pull request on it is the newest.
branch=spin-terraform-aws/next
title="module ${ref}, spin ${release}"
git checkout -q -b "${branch}"
git commit -q -a -m "${title}" \
  -m "spin-stack/spin-terraform-aws at ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}, whose images.json has ${release} in ${REGION}. Read the plan before merging."
git push -q --force origin "${branch}"
# Everything named, nothing inferred from the shallow clone. A pull request open already was just
# rewritten: its title and body say what it holds now.
body="Moves the installation to spin-stack/spin-terraform-aws at ${ref} (${GITHUB_SHA}) and spin ${release}, the newest release with an image in ${REGION}. Read the plan before merging; merging changes nothing until the apply is run."
open=$(gh pr list -R "${REPOSITORY}" --head "${branch}" --state open --json number --jq '.[0].number // empty')
if [ -z "${open}" ]; then
  gh pr create -R "${REPOSITORY}" --head "${branch}" --base main --title "${title}" --body "${body}"
else
  gh pr edit "${open}" -R "${REPOSITORY}" --title "${title}" --body "${body}"
fi
