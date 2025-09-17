#!/bin/bash

set -euo pipefail

dependencies_json=${1:-dependencies.json}
composer_file=composer.json

# Process each package from dependencies.json
while IFS= read -r package; do
    name=$(echo "$package" | jq -r '.package')
    requirement=$(echo "$package" | jq -r '.requirement')

    if jq -e ".require | has(\"$name\")" "$composer_file" >/dev/null
    then
        composer require --no-update "$name":"$requirement"
        echo "Updated '$name' package requirement to '$requirement'"
    elif jq -e ".\"require-dev\" | has(\"$name\")" "$composer_file" >/dev/null
    then
        composer require --dev --no-update "$name":"$requirement"
        echo "Updated '$name' dev package requirement to '$requirement'"
    fi
done < <(jq -c '.packages[]' "$dependencies_json")
