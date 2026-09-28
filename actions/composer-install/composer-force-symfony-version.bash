#!/bin/bash

set -euo pipefail

# Forces every lockstep symfony/* component to the given minor (e.g. "8.1"), direct and transitive.
# The component list is taken from the "replace" map of the matching symfony/symfony release on Packagist,
# and each component gets a root "conflict" entry "<X.Y", so the solver cannot keep any of them on a lower
# version. Contracts and polyfills version independently and are left alone.

symfony_version=${1:?Usage: $0 <major.minor>}
composer_file=composer.json

if [[ ! $symfony_version =~ ^[0-9]+\.[0-9]+$ ]]
then
    echo "Expected <major.minor>, got '$symfony_version'" >&2
    exit 1
fi

components=$(
    curl -fsSL https://repo.packagist.org/p2/symfony/symfony.json \
    | jq -r --arg v "$symfony_version" '
        [.packages["symfony/symfony"][] | select((.version | ltrimstr("v") | startswith($v + ".")) and (.version | contains("-") | not))]
        | first
        | .replace // {}
        | keys[]
        | select((contains("-contracts") or startswith("symfony/polyfill")) | not)
    '
)

if [[ -z $components ]]
then
    echo "No symfony/symfony $symfony_version.* release found on Packagist" >&2
    exit 1
fi

tmp_file=$(mktemp)
jq --arg c "<$symfony_version" --args '.conflict = ((.conflict // {}) + ($ARGS.positional | map({(.): $c}) | add))' $components < "$composer_file" > "$tmp_file"
mv "$tmp_file" "$composer_file"

echo "> Added conflict <$symfony_version for $(echo "$components" | wc -l | tr -d ' ') symfony/* components"
