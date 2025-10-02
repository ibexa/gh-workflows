#!/bin/bash

set -euo pipefail

dependencies_json=${1:-dependencies.json}
composer_file=composer.json

# Process each package from dependencies.json
while IFS= read -r package; do
    name=$(echo "$package" | jq -r '.package')
    requirement=$(echo "$package" | jq -r '.requirement')
    should_be_added_as_vcs=$(echo "$package" | jq -r '.shouldBeAddedAsVCS')

    if jq -e ".require | has(\"$name\")" "$composer_file" >/dev/null
    then
        composer require --no-update "$name":"$requirement"
        echo "> Updated '$name' package requirement to '$requirement'"
    elif jq -e ".\"require-dev\" | has(\"$name\")" "$composer_file" >/dev/null
    then
        composer require --dev --no-update "$name":"$requirement"
        echo "> Updated '$name' dev package requirement to '$requirement'"
    else
        # Skip further processing for a dependency which is not a part of currently processed composer.json
        continue
    fi

    if [[ $should_be_added_as_vcs == "true" ]] ; then
        repository_url=$(echo "$package" | jq -r '.repositoryUrl')
        echo ">> Configuring VCS repository $repository_url for $name"
        composer config repositories."$(uuidgen)" vcs "$repository_url"
    fi
done < <(jq -c '.packages[]' "$dependencies_json")

echo "> Display updated composer.json for debugging"
cat "$composer_file"
