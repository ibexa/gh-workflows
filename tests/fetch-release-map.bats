#!/usr/bin/env bats

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../actions/create-metapackage-tag/fetch-release-map.bash"

setup() {
    setup_stub_path

    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    export GH_RESPONSE="$BATS_TEST_TMPDIR/gh.response"
    touch "$GH_LOG"

    stub_command gh '
echo "gh $*" >> "$GH_LOG"
cat "$GH_RESPONSE"'

    export VERSION='4.6.30'
    export RELEASE_REPOSITORY='ibexa/release-maker'
    export RELEASE_MAP="$BATS_TEST_TMPDIR/release-map.json"
}

@test "turns the release.json array into a packageName->targetVersion map" {
    printf '[
        {"packageName": "ibexa/core", "targetVersion": "v4.6.30", "irrelevant": "x"},
        {"packageName": "ibexa/admin-ui", "targetVersion": "v4.6.31"}
    ]' | base64 > "$GH_RESPONSE"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(jq -c -S . "$RELEASE_MAP")" = '{"ibexa/admin-ui":"v4.6.31","ibexa/core":"v4.6.30"}' ]
}

@test "requests the release definition for the given version from the release repository" {
    printf '[]' | base64 > "$GH_RESPONSE"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q 'gh api /repos/ibexa/release-maker/contents/releases/4.6.30/release.json --jq .content' "$GH_LOG"
}

@test "fails with an attributable error when the release definition is missing" {
    stub_command gh '
echo "gh: Not Found (HTTP 404)" >&2
exit 1'

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [[ "$output" == *'::error::Release definition releases/4.6.30/release.json is not available in ibexa/release-maker'* ]]
    [[ "$output" != *'base64'* ]]
    [ ! -e "$RELEASE_MAP" ]
}
