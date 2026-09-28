#!/bin/bash

set -euo pipefail

# Fails when an installed symfony/* component forced by composer-force-symfony-version.bash
# (a root "conflict" entry "<X.Y") is not on that minor.

symfony_version=${1:?Usage: $0 <major.minor>}
composer_file=composer.json

forced=$(jq -r --arg c "<$symfony_version" '.conflict // {} | to_entries[] | select((.key | startswith("symfony/")) and .value == $c) | .key' "$composer_file")
installed=$(composer show --format=json | jq -r '.installed[] | "\(.name) \(.version)"')

checked=0
mismatched=()
while read -r name version
do
    if grep -qxF "$name" <<< "$forced"
    then
        checked=$((checked + 1))
        echo "$name $version"
        [[ ${version#v} == "$symfony_version".* ]] || mismatched+=("$name $version")
    fi
done <<< "$installed"

if [[ $checked -eq 0 ]]
then
    echo "No forced symfony/* component is installed - was composer-force-symfony-version.bash run?" >&2
    exit 1
fi

if [[ ${#mismatched[@]} -gt 0 ]]
then
    echo "Components not on Symfony $symfony_version:" >&2
    printf '%s\n' "${mismatched[@]}" >&2
    exit 1
fi

echo "> All $checked installed symfony/* components are on $symfony_version"
