#!/usr/bin/env bash
set -euo pipefail

# Commits the composer.json/composer.lock changes, tags v<VERSION> and pushes
# the tag. git is authenticated through gh with GITHUB_TOKEN, scoped to this
# process — no credentials are written into the remote URL.
#
# Required environment: VERSION, GITHUB_TOKEN
# Optional environment: GIT_PUSH_ARGS

gh auth setup-git
git config --local user.name "github-actions[bot]"
git config --local user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add composer.*
git commit -m "[composer] Set dependencies for ${VERSION} release + .lock"
git tag "v${VERSION}"
# shellcheck disable=SC2086 # GIT_PUSH_ARGS is deliberately word-split
git push origin "v${VERSION}" ${GIT_PUSH_ARGS:-}
