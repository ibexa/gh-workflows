#!/usr/bin/env bash
set -euo pipefail

check() {
    local -a curl_auth=()
    if [[ -n "${AUTH_KEY:-}" ]]; then
        curl_auth=(-u "${AUTH_KEY}:${AUTH_TOKEN}")
    fi
    curl -sf "${curl_auth[@]}" "${REPOSITORY_URL%/}/p2/${PACKAGE}.json" \
        | jq -e --arg pkg "${PACKAGE}" --arg version "${VERSION}" \
            '.packages[$pkg][] | select(.version == $version)' > /dev/null
}

if [[ "${RETRY:-false}" != 'true' ]]; then
    RETRY_SCHEDULE=''
fi

for DELAY in ${RETRY_SCHEDULE}; do
    if check; then
        exit 0
    fi
    echo "${PACKAGE}:${VERSION} not yet available, re-checking in ${DELAY} seconds"
    sleep "${DELAY}"
done
if check; then
    exit 0
fi

echo "::error::${PACKAGE}:${VERSION} is not available in ${REPOSITORY_URL%/}" >&2
exit 1
