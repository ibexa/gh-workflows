#!/usr/bin/env bash
set -euo pipefail

# Derives composer minimum-stability and prefer-stable from the pre-release
# suffix of VERSION (e.g. 4.5.6-beta1 -> beta); stable versions get both unset.
#
# Required environment: VERSION

SUFFIX=$(echo "${VERSION}" | cut -d '-' -f 2)
SET_STABILITY="composer config minimum-stability"
$SET_STABILITY --unset
composer config prefer-stable --unset
case $SUFFIX in
    alpha*|beta*|rc*) composer config prefer-stable true ;;&
    alpha*) $SET_STABILITY alpha ;;
    beta*) $SET_STABILITY beta ;;
    rc*) $SET_STABILITY rc ;;
esac
