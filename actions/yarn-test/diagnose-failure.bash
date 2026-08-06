#!/bin/bash

# Deliberately without "-e", so that one failing check does not hide the rest.
set -uo pipefail

log_file=${1:?Usage: diagnose-failure.bash <log-file>}

# Any TypeScript error, for example TS2307: Cannot find module '...'.
if grep -qE 'error TS[0-9]+' "$log_file"
then
    # The generated tsconfig.json is assumed to extend the one shipped in @ibexa/ts-config.
    for config in tsconfig.json node_modules/@ibexa/ts-config/tsconfig.json
    do
        echo "::group::$config"
        cat "$config" || echo '> Missing - check whether "yarn install" and its "postinstall" script succeeded.'
        # The generated file may lack a trailing newline, and "::endgroup::" is only
        # recognised at the start of a line.
        echo
        echo "::endgroup::"
    done

    # What tsc actually uses: the above merged together, with paths resolved.
    echo "::group::Effective configuration (tsc --showConfig)"
    yarn --silent tsc --showConfig || echo '> Could not resolve the effective configuration.'
    echo "::endgroup::"
fi
