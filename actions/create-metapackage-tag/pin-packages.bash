#!/usr/bin/env bash
set -euo pipefail

# Pins each package listed in PIN_PACKAGES (newline-separated composer package
# names) to VERSION in the require section of composer.json.
#
# Required environment: VERSION, PIN_PACKAGES

while IFS= read -r PACKAGE; do
    if [[ -z "${PACKAGE}" ]]; then
        continue
    fi
    jq --arg pkg "${PACKAGE}" --arg version "${VERSION}" \
        '.require[$pkg] = $version' composer.json > composer.json.tmp
    mv composer.json.tmp composer.json
done <<< "${PIN_PACKAGES}"
