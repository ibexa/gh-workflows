#!/usr/bin/env bats

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../actions/check-composer-package/check-composer-package.bash"

setup() {
    setup_stub_path

    export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
    export CURL_COUNT_FILE="$BATS_TEST_TMPDIR/curl.count"
    export CURL_RESPONSES_DIR="$BATS_TEST_TMPDIR/responses"
    export SLEEP_LOG="$BATS_TEST_TMPDIR/sleep.log"
    mkdir -p "$CURL_RESPONSES_DIR"
    touch "$CURL_LOG" "$SLEEP_LOG"

    # Responds with $CURL_RESPONSES_DIR/response.<call number> when present,
    # otherwise fails like curl -f does on an HTTP error.
    stub_command curl '
echo "curl $*" >> "$CURL_LOG"
COUNT=$(( $(cat "$CURL_COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$COUNT" > "$CURL_COUNT_FILE"
if [[ -f "$CURL_RESPONSES_DIR/response.$COUNT" ]]; then
    cat "$CURL_RESPONSES_DIR/response.$COUNT"
else
    exit 22
fi'

    stub_command sleep 'echo "$1" >> "$SLEEP_LOG"'

    export PACKAGE='ibexa/experience'
    export VERSION='v4.6.30'
    export REPOSITORY_URL='https://updates.ibexa.co'
    export RETRY='false'
    export RETRY_SCHEDULE='5 7'
    unset AUTH_KEY AUTH_TOKEN
}

metadata_with_version() {
    printf '{"packages": {"%s": [{"version": "v4.6.29"}, {"version": "%s"}]}}' "$PACKAGE" "$1"
}

curl_calls() {
    grep -c '^curl ' "$CURL_LOG"
}

@test "succeeds when the version is available" {
    metadata_with_version "$VERSION" > "$CURL_RESPONSES_DIR/response.1"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(curl_calls)" -eq 1 ]
    [ ! -s "$SLEEP_LOG" ]
}

@test "fails fast without retry when the version is missing" {
    metadata_with_version 'v4.6.29' > "$CURL_RESPONSES_DIR/response.1"

    run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$(curl_calls)" -eq 1 ]
    [ ! -s "$SLEEP_LOG" ]
    [[ "$output" == *"::error::ibexa/experience:v4.6.30 is not available in https://updates.ibexa.co"* ]]
}

@test "fails fast without retry even when a retry schedule is set" {
    run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$(curl_calls)" -eq 1 ]
    [ ! -s "$SLEEP_LOG" ]
}

@test "with retry, re-checks on the schedule and fails after the final check" {
    export RETRY='true'

    run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$(curl_calls)" -eq 3 ]
    [ "$(cat "$SLEEP_LOG")" = $'5\n7' ]
    [[ "$output" == *'not yet available, re-checking in 5 seconds'* ]]
    [[ "$output" == *'not yet available, re-checking in 7 seconds'* ]]
    [[ "$output" == *'::error::'* ]]
}

@test "with retry, succeeds as soon as the version appears" {
    export RETRY='true'
    metadata_with_version 'v4.6.29' > "$CURL_RESPONSES_DIR/response.1"
    metadata_with_version "$VERSION" > "$CURL_RESPONSES_DIR/response.2"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(curl_calls)" -eq 2 ]
    [ "$(cat "$SLEEP_LOG")" = '5' ]
}

@test "passes HTTP basic auth to curl when configured" {
    export AUTH_KEY='satis-key'
    export AUTH_TOKEN='satis-token'
    metadata_with_version "$VERSION" > "$CURL_RESPONSES_DIR/response.1"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q -- '-u satis-key:satis-token' "$CURL_LOG"
}

@test "requests anonymously when no auth is configured" {
    metadata_with_version "$VERSION" > "$CURL_RESPONSES_DIR/response.1"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    ! grep -q -- '-u ' "$CURL_LOG"
}

@test "queries the composer v2 metadata endpoint, trimming a trailing repository URL slash" {
    export REPOSITORY_URL='https://updates.ibexa.co/'
    metadata_with_version "$VERSION" > "$CURL_RESPONSES_DIR/response.1"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q 'https://updates.ibexa.co/p2/ibexa/experience.json' "$CURL_LOG"
}

@test "treats an HTTP-level curl failure as the version being unavailable" {
    export RETRY='true'
    export RETRY_SCHEDULE='5'
    # No response files at all: every curl call exits 22.

    run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$(curl_calls)" -eq 2 ]
    [[ "$output" == *'::error::'* ]]
}
