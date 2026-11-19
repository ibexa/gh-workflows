#!/usr/bin/env bash
set -euo pipefail

# Checks that VERSION may be released from BRANCH given the tags of the
# repository in the current directory. Prints the reason and exits 1 otherwise.
#
# Required environment: VERSION, BRANCH, RELEASE_BRANCHES
# Optional environment: REQUIRE_RELEASE_BRANCH (default true),
#                       ALLOW_EMPTY_RELEASE (default false),
#                       SKIP_SEQUENCE_CHECK (default false)
#
# RELEASE_BRANCHES is a comma-separated list of branch schemes:
#   major.x      2.x releases 2.*.*, sequenced within that major
#   major.minor  5.0 releases 5.0.*, sequenced within that minor
#   main         main releases anything, sequenced over all the tags

NUMBER='(0|[1-9][0-9]*)'
IDENTIFIER='[0-9A-Za-z][0-9A-Za-z-]*'
SEMVER="^${NUMBER}\.${NUMBER}\.${NUMBER}(-${IDENTIFIER}(\.${IDENTIFIER})*)?\$"
VERSION_LIKE='^v?[0-9]+\.[0-9]+'

fail() {
    local message=$1

    echo "::error::${message}" >&2
    exit 1
}

# Reports a break of the release sequence: fatal unless the sequence check is skipped.
fail_sequence() {
    local message=$1

    if [[ "${SKIP_SEQUENCE_CHECK:-false}" != 'true' ]]; then
        fail "$message"
    fi

    echo "::warning::Sequence check skipped: ${message}" >&2
}

if [[ ! "${VERSION:-}" =~ $SEMVER ]]; then
    fail "Invalid version '${VERSION:-}'; expected semver without the leading v, like 1.1.5 or 1.2.0-alpha.1"
fi

major=${BASH_REMATCH[1]}
minor=${BASH_REMATCH[2]}
patch=${BASH_REMATCH[3]}

scope=''
branch_matched=false
first_scheme=''

IFS=',' read -ra schemes <<< "${RELEASE_BRANCHES// /}"

for scheme in "${schemes[@]}"; do
    case "$scheme" in
        major.x) pattern="^${NUMBER}\.x\$" ;;
        major.minor) pattern="^${NUMBER}\.${NUMBER}\$" ;;
        main) pattern='^main$' ;;
        *) fail "Unknown release branch scheme '${scheme}'; expected major.x, major.minor or main" ;;
    esac

    first_scheme=${first_scheme:-$scheme}

    if [[ "$BRANCH" =~ $pattern ]]; then
        scope=$scheme
        branch_matched=true
        branch_major=${BASH_REMATCH[1]:-}
        branch_minor=${BASH_REMATCH[2]:-}
        break
    fi
done

if [[ -z "$first_scheme" ]]; then
    fail 'RELEASE_BRANCHES is empty; expected a list of major.x, major.minor or main'
fi

if [[ "$branch_matched" == true ]]; then
    if [[ "$scope" == 'major.x' && "$branch_major" != "$major" ]]; then
        fail "Branch ${BRANCH} releases ${branch_major}.*.* only; got ${VERSION}"
    fi

    if [[ "$scope" == 'major.minor' && ( "$branch_major" != "$major" || "$branch_minor" != "$minor" ) ]]; then
        fail "Branch ${BRANCH} releases ${branch_major}.${branch_minor}.* only; got ${VERSION}"
    fi
elif [[ "${REQUIRE_RELEASE_BRANCH:-true}" == 'true' ]]; then
    fail "Refusing to release from '${BRANCH}'; allowed release branches: ${RELEASE_BRANCHES}"
else
    scope=$first_scheme
fi

tags=$(git tag --list)
head_tags=$(git tag --points-at HEAD)
latest=''
malformed=()

while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue

    if [[ "$tag" == "v${VERSION}" ]]; then
        fail "Tag v${VERSION} already exists"
    fi

    if [[ ! "${tag#v}" =~ $SEMVER || "$tag" != v* ]]; then
        # Version-like tags in another spelling (1.1.6, v1.1, v1.1.06) block the release
        # on purpose: skipping them would let the sequence start from an older tag.
        # Counting them as the version they stand for was considered and left out until a
        # repository needs it. That change belongs here: parse the numbers of such a tag
        # and let it fall through to the code below instead of collecting it, behind an
        # opt-in input (e.g. legacy-tags: fail|normalize) so that the default stays strict.
        if [[ "$tag" =~ $VERSION_LIKE ]]; then
            malformed+=("$tag")
        fi

        continue
    fi

    tag_major=${BASH_REMATCH[1]}
    tag_minor=${BASH_REMATCH[2]}
    tag_patch=${BASH_REMATCH[3]}

    [[ -z "${BASH_REMATCH[4]}" ]] || continue
    [[ "$scope" == 'main' || "$tag_major" == "$major" ]] || continue
    [[ "$scope" != 'major.minor' || "$tag_minor" == "$minor" ]] || continue

    if [[ -n "$latest" ]]; then
        read -r latest_major latest_minor latest_patch <<< "${latest//./ }"

        (( tag_major > latest_major
            || (tag_major == latest_major && tag_minor > latest_minor)
            || (tag_major == latest_major && tag_minor == latest_minor && tag_patch > latest_patch) )) || continue
    fi

    latest="${tag_major}.${tag_minor}.${tag_patch}"
done <<< "$tags"

if (( ${#malformed[@]} > 0 )); then
    fail_sequence "Version-like tags not in the v<major>.<minor>.<patch> form: ${malformed[*]}; the release sequence cannot be established"
fi

allowed=()

if [[ -n "$latest" ]]; then
    read -r latest_major latest_minor latest_patch <<< "${latest//./ }"

    allowed+=("${latest_major}.${latest_minor}.$(( latest_patch + 1 ))")

    if [[ "$scope" != 'major.minor' ]]; then
        allowed+=("${latest_major}.$(( latest_minor + 1 )).0")
    fi

    if [[ "$scope" == 'main' ]]; then
        allowed+=("$(( latest_major + 1 )).0.0")
    fi

    origin="the latest tag v${latest}"
else
    case "$scope" in
        major.x) allowed+=("${major}.0.0") ;;
        major.minor) allowed+=("${major}.${minor}.0") ;;
        main) allowed+=('1.0.0') ;;
    esac

    if [[ "$major" == '0' ]]; then
        [[ "$scope" == 'major.minor' && "$minor" != '0' ]] || allowed+=('0.0.1')
        [[ "$scope" == 'major.minor' ]] || allowed+=('0.1.0')
    fi

    origin='a line without a stable tag'
fi

base="${major}.${minor}.${patch}"
is_allowed=false

for candidate in "${allowed[@]}"; do
    if [[ "$candidate" == "$base" ]]; then
        is_allowed=true
    fi
done

if [[ "$is_allowed" != true ]]; then
    expected=$(printf '%s or ' "${allowed[@]}")
    fail_sequence "Version ${VERSION} does not follow ${origin}; expected ${expected% or }, or a prerelease of it"
fi

if [[ "${ALLOW_EMPTY_RELEASE:-false}" != 'true' ]]; then
    while IFS= read -r tag; do
        if [[ "$tag" == v* && "${tag#v}" =~ $SEMVER ]]; then
            fail "HEAD is already released as ${tag}; nothing new to release. Allow an empty release to tag it anyway"
        fi
    done <<< "$head_tags"
fi

echo "Version ${VERSION} can be released from ${BRANCH}"
