#!/usr/bin/env bats

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../actions/validate-release-version/validate-release-version.bash"

setup() {
    setup_stub_path

    stub_command git 'case "$*" in "tag --list") printf "%s" "$TAGS" | tr " " "\n" ;; "tag --points-at HEAD") printf "%s" "$HEAD_TAGS" | tr " " "\n" ;; *) exit 1 ;; esac'

    export TAGS='v1.0.0 v1.1.0 v1.1.4 v1.1.5 v2.0.0 v2.0.5 v2.1.0-rc.1'
    export HEAD_TAGS=''
    export BRANCH='1.x'
    export RELEASE_BRANCHES='major.x'
}

@test "accepts the next patch of the latest stable tag of the major" {
    VERSION=1.1.6 run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$output" = 'Version 1.1.6 can be released from 1.x' ]
}

@test "accepts the next minor of the latest stable tag of the major" {
    VERSION=1.2.0 run "$SCRIPT"

    [ "$status" -eq 0 ]
}

@test "accepts a prerelease of the next version" {
    VERSION=1.2.0-alpha.1 run "$SCRIPT"

    [ "$status" -eq 0 ]
}

@test "rejects a version that skips the sequence" {
    VERSION=1.1.7 run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$output" = '::error::Version 1.1.7 does not follow the latest tag v1.1.5; expected 1.1.6 or 1.2.0, or a prerelease of it' ]
}

@test "rejects a prerelease of a version that is already released or older" {
    VERSION=1.1.5-rc.1 run "$SCRIPT"
    [ "$status" -eq 1 ]

    VERSION=1.0.0-alpha.1 run "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "ignores prerelease tags when looking for the latest stable tag" {
    BRANCH=2.x VERSION=2.0.6 run "$SCRIPT"

    [ "$status" -eq 0 ]
}

@test "rejects an existing tag" {
    VERSION=1.1.5 run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$output" = '::error::Tag v1.1.5 already exists' ]
}

@test "rejects versions that are not strict semver" {
    for version in '' v1.1.6 1.1 1.1.06 01.1.6 1.1.6- 1.1.6-rc..1 1.1.6-.rc 1.1.6+build "1.1.6'; id; echo '"; do
        VERSION="$version" run "$SCRIPT"

        [ "$status" -eq 1 ]
        [[ "$output" == '::error::Invalid version '* ]]
    done
}

@test "rejects a version of another major than the major.x branch" {
    VERSION=2.0.6 run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$output" = '::error::Branch 1.x releases 1.*.* only; got 2.0.6' ]
}

@test "rejects a branch that is not a release branch" {
    BRANCH=feature VERSION=1.1.6 run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$output" = "::error::Refusing to release from 'feature'; allowed release branches: major.x" ]
}

@test "validates the sequence from any branch when the release branch is not required" {
    BRANCH=19/merge REQUIRE_RELEASE_BRANCH=false VERSION=1.1.6 run "$SCRIPT"
    [ "$status" -eq 0 ]

    BRANCH=19/merge REQUIRE_RELEASE_BRANCH=false VERSION=1.1.7 run "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "still binds the version to a release branch when the release branch is not required" {
    REQUIRE_RELEASE_BRANCH=false VERSION=2.0.6 run "$SCRIPT"

    [ "$status" -eq 1 ]
}

@test "starts a new major line at its .0.0" {
    BRANCH=3.x VERSION=3.0.0 run "$SCRIPT"
    [ "$status" -eq 0 ]

    BRANCH=3.x VERSION=3.0.0-alpha1 run "$SCRIPT"
    [ "$status" -eq 0 ]

    BRANCH=3.x VERSION=3.5.7 run "$SCRIPT"
    [ "$status" -eq 1 ]
    [ "$output" = '::error::Version 3.5.7 does not follow a line without a stable tag; expected 3.0.0, or a prerelease of it' ]
}

@test "sequences a major.minor branch within its own minor" {
    export TAGS='v5.0.8 v5.0.9 v5.1.3 v6.0.0-alpha1'
    export RELEASE_BRANCHES='main,major.minor'

    BRANCH=5.0 VERSION=5.0.10 run "$SCRIPT"
    [ "$status" -eq 0 ]

    BRANCH=5.0 VERSION=5.1.0 run "$SCRIPT"
    [ "$status" -eq 1 ]
    [ "$output" = '::error::Branch 5.0 releases 5.0.* only; got 5.1.0' ]

    BRANCH=5.1 VERSION=5.1.4 run "$SCRIPT"
    [ "$status" -eq 0 ]

    BRANCH=6.0 VERSION=6.0.0 run "$SCRIPT"
    [ "$status" -eq 0 ]

    BRANCH=6.0 VERSION=6.0.1 run "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "lets main release the next patch, minor or major of the latest tag" {
    export BRANCH=main

    for version in 2.0.6 2.1.0 3.0.0; do
        RELEASE_BRANCHES='main,major.minor' VERSION="$version" run "$SCRIPT"

        [ "$status" -eq 0 ]
    done

    RELEASE_BRANCHES='main,major.minor' VERSION=1.1.6 run "$SCRIPT"
    [ "$status" -eq 1 ]
    [ "$output" = '::error::Version 1.1.6 does not follow the latest tag v2.0.5; expected 2.0.6 or 2.1.0 or 3.0.0, or a prerelease of it' ]
}

@test "accepts the first release of a repository without tags" {
    export TAGS=''
    export BRANCH=main
    export RELEASE_BRANCHES=main

    for version in 0.0.1 0.1.0 1.0.0 1.0.0-beta.1; do
        VERSION="$version" run "$SCRIPT"

        [ "$status" -eq 0 ]
    done

    VERSION=0.0.2 run "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "rejects version-like tags in another spelling" {
    TAGS="$TAGS 1.1.6 v1.2 v1.1.06" VERSION=1.1.6 run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$output" = '::error::Version-like tags not in the v<major>.<minor>.<patch> form: 1.1.6 v1.2 v1.1.06; the release sequence cannot be established' ]
}

@test "ignores tags that are not versions" {
    TAGS="$TAGS latest nightly v1" VERSION=1.1.6 run "$SCRIPT"

    [ "$status" -eq 0 ]
}

@test "rejects releasing a commit that already carries a version tag" {
    HEAD_TAGS='latest v1.1.5' VERSION=1.1.6 run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$output" = '::error::HEAD is already released as v1.1.5; nothing new to release. Allow an empty release to tag it anyway' ]
}

@test "releases an already tagged commit when an empty release is allowed" {
    HEAD_TAGS='v1.1.5' ALLOW_EMPTY_RELEASE=true VERSION=1.1.6 run "$SCRIPT"

    [ "$status" -eq 0 ]
}

@test "releases out of sequence with a warning when the sequence check is skipped" {
    SKIP_SEQUENCE_CHECK=true VERSION=1.0.1 run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$output" = '::warning::Sequence check skipped: Version 1.0.1 does not follow the latest tag v1.1.5; expected 1.1.6 or 1.2.0, or a prerelease of it
Version 1.0.1 can be released from 1.x' ]
}

@test "tolerates version-like tags in another spelling when the sequence check is skipped" {
    TAGS="$TAGS 1.1.6" SKIP_SEQUENCE_CHECK=true VERSION=1.1.6 run "$SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" == '::warning::Sequence check skipped: Version-like tags not in the v<major>.<minor>.<patch> form: 1.1.6;'* ]]
}

@test "keeps the other rules when the sequence check is skipped" {
    export SKIP_SEQUENCE_CHECK=true

    VERSION=1.1.06 run "$SCRIPT"
    [ "$status" -eq 1 ]

    VERSION=1.1.5 run "$SCRIPT"
    [ "$status" -eq 1 ]

    VERSION=2.0.9 run "$SCRIPT"
    [ "$status" -eq 1 ]

    BRANCH=feature VERSION=1.0.1 run "$SCRIPT"
    [ "$status" -eq 1 ]

    HEAD_TAGS='v1.1.5' VERSION=1.0.1 run "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "rejects an unknown release branch scheme" {
    RELEASE_BRANCHES='major.x,develop' BRANCH=develop VERSION=1.1.6 run "$SCRIPT"

    [ "$status" -eq 1 ]
    [ "$output" = "::error::Unknown release branch scheme 'develop'; expected major.x, major.minor or main" ]
}

@test "fails when the tags cannot be listed" {
    stub_command git 'exit 1'

    VERSION=1.1.6 run "$SCRIPT"

    [ "$status" -ne 0 ]
}
