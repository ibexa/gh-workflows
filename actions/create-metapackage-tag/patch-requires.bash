#!/usr/bin/env bash
set -euo pipefail

# Replaces the value of every require entry of composer.json that has a key in
# the RELEASE_MAP JSON object ({packageName: targetVersion}) with the mapped
# version, then reformats composer.json to 4-space indentation.
#
# Required environment: RELEASE_MAP

jq --slurpfile release "${RELEASE_MAP}" '
    .require |= (
        to_entries |
        map({
            key: .key,
            value: (if ($release[0][.key]) then $release[0][.key] else .value end)
        }) | from_entries
    )
' composer.json > composer.json.tmp
mv composer.json.tmp composer.json

unexpand -t2 composer.json | expand -t4 > composer.json.tmp
mv composer.json.tmp composer.json
