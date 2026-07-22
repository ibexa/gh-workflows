#!/usr/bin/env bats

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../actions/create-metapackage-tag/pin-packages.bash"

setup() {
    cd "$BATS_TEST_TMPDIR"
    printf '{
        "name": "ibexa/commerce",
        "require": {
            "ibexa/experience": "~4.6.0",
            "other/package": "^1.0"
        }
    }' > composer.json

    export VERSION='4.6.30'
}

@test "pins a single package to the release version" {
    PIN_PACKAGES='ibexa/experience' run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(jq -r '.require["ibexa/experience"]' composer.json)" = '4.6.30' ]
    [ "$(jq -r '.require["other/package"]' composer.json)" = '^1.0' ]
    [ "$(jq -r '.name' composer.json)" = 'ibexa/commerce' ]
}

@test "pins every package of a multi-line list" {
    PIN_PACKAGES=$'ibexa/experience\nother/package' run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(jq -r '.require["ibexa/experience"]' composer.json)" = '4.6.30' ]
    [ "$(jq -r '.require["other/package"]' composer.json)" = '4.6.30' ]
}

@test "ignores blank lines in the list" {
    PIN_PACKAGES=$'\nibexa/experience\n\n' run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(jq -r '.require["ibexa/experience"]' composer.json)" = '4.6.30' ]
    [ "$(jq '.require | length' composer.json)" -eq 2 ]
}

@test "leaves no temporary file behind" {
    PIN_PACKAGES='ibexa/experience' run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ ! -e composer.json.tmp ]
}
