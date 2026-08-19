#!/usr/bin/env bash
set -euo pipefail

# Derives composer minimum-stability and prefer-stable from the pre-release
# suffix of VERSION (e.g. 4.5.6-beta1 -> beta); stable versions get both unset.
#
# Required environment: VERSION

SUFFIX="${VERSION#*-}"
composer config minimum-stability --unset
composer config prefer-stable --unset
case ${SUFFIX} in
    alpha*|beta*|rc*) composer config prefer-stable true ;;&
    alpha*) composer config minimum-stability alpha ;;
    beta*) composer config minimum-stability beta ;;
    rc*) composer config minimum-stability rc ;;
    *) ;; # stable version or unrecognized suffix: leave stability unset
esac
