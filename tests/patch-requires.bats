#!/usr/bin/env bats

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../actions/create-metapackage-tag/patch-requires.bash"

setup() {
    cd "$BATS_TEST_TMPDIR"
    printf '{
        "name": "ibexa/commerce",
        "require": {
            "ibexa/core": "~4.6.0",
            "ibexa/admin-ui": "~4.6.0",
            "other/package": "^1.0"
        },
        "extra": {
            "unrelated": true
        }
    }' > composer.json

    export RELEASE_MAP="$BATS_TEST_TMPDIR/release-map.json"
    printf '{
        "ibexa/core": "v4.6.30",
        "ibexa/admin-ui": "v4.6.31",
        "not/required-here": "v9.9.9"
    }' > "$RELEASE_MAP"
}

@test "replaces require versions for packages present in the release map" {
    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(jq -r '.require["ibexa/core"]' composer.json)" = 'v4.6.30' ]
    [ "$(jq -r '.require["ibexa/admin-ui"]' composer.json)" = 'v4.6.31' ]
}

@test "keeps require entries that are not in the release map" {
    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(jq -r '.require["other/package"]' composer.json)" = '^1.0' ]
}

@test "does not add release map packages that are not required" {
    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(jq '.require | has("not/required-here")' composer.json)" = 'false' ]
}

@test "leaves other sections untouched" {
    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(jq '.extra.unrelated' composer.json)" = 'true' ]
    [ "$(jq -r '.name' composer.json)" = 'ibexa/commerce' ]
}

@test "reformats composer.json to 4-space indentation" {
    run "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q '^    "require"' composer.json
    grep -q '^        "ibexa/core"' composer.json
}

@test "leaves no temporary file behind" {
    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ ! -e composer.json.tmp ]
}
