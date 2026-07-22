#!/usr/bin/env bash
set -euo pipefail

# Fetches the releases/<VERSION>/release.json definition from RELEASE_REPOSITORY
# (an array of {packageName, targetVersion} objects) and writes it to RELEASE_MAP
# as a single {packageName: targetVersion} object.
#
# Required environment: VERSION, RELEASE_REPOSITORY, RELEASE_MAP, GITHUB_TOKEN

gh api "/repos/${RELEASE_REPOSITORY}/contents/releases/${VERSION}/release.json" --jq '.content' \
    | base64 --decode \
    | jq '[ .[] | { (.packageName): (.targetVersion) } ] | add' > "${RELEASE_MAP}"
