#!/usr/bin/env bash
# Configures git so that commits are authored by the bot user of the GitHub App
# whose slug is in APP_SLUG. GH_TOKEN must hold a token able to call the API.
set -euo pipefail

user_id=$(gh api "/users/${APP_SLUG}[bot]" --jq .id)
user_name="${APP_SLUG}[bot]"
user_email="${user_id}+${APP_SLUG}[bot]@users.noreply.github.com"

git config --global user.name "$user_name"
git config --global user.email "$user_email"

{
    echo "user-id=$user_id"
    echo "user-name=$user_name"
    echo "user-email=$user_email"
} >> "$GITHUB_OUTPUT"
