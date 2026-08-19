#!/usr/bin/env bash
set -euo pipefail

# Fetches the releases/<VERSION>/release.json definition from RELEASE_REPOSITORY
# (an array of {packageName, targetVersion} objects) and writes it to RELEASE_MAP
# as a single {packageName: targetVersion} object.
#
# Required environment: VERSION, RELEASE_REPOSITORY, RELEASE_MAP, GITHUB_TOKEN

if ! CONTENT=$(gh api "/repos/${RELEASE_REPOSITORY}/contents/releases/${VERSION}/release.json" --jq '.content'); then
    echo "::error::Release definition releases/${VERSION}/release.json is not available in ${RELEASE_REPOSITORY}" >&2
    exit 1
fi

base64 --decode <<< "${CONTENT}" \
    | jq '[ .[] | { (.packageName): (.targetVersion) } ] | add' > "${RELEASE_MAP}"
