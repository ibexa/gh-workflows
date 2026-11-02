# Ibexa GitHub Workflows

## Actions

### `app-git-identity`

Generates an installation token for the Ibexa Workflow Automation GitHub App and configures
git so that the commits made later in the job are authored by the App's bot user. Use it in
jobs that commit, tag or push to branches protected by the repository rulesets. The default
`GITHUB_TOKEN` cannot push there.

```yaml
steps:
    -   uses: ibexa/gh-workflows/actions/app-git-identity@main
        id: bot
        with:
            client-id: ${{ secrets.AUTOMATION_CLIENT_ID }}
            private-key: ${{ secrets.AUTOMATION_CLIENT_SECRET }}

    -   uses: actions/checkout@v7
        with:
            token: ${{ steps.bot.outputs.token }}

    -   run: |
            git commit -m "..."
            git push
```

Outputs: `token`, `app-slug`, `user-id`, `user-name`, `user-email`. The identity is set with
`git config --global`, so it applies to every repository checked out in the job.

## COPYRIGHT
Copyright (C) 1999-2025 Ibexa AS (formerly eZ Systems AS). All rights reserved.

## LICENSE
This source code is available separately under the following licenses:

A - Ibexa Business Use License Agreement (Ibexa BUL),
version 2.4 or later versions (as license terms may be updated from time to time)
Ibexa BUL is granted by having a valid Ibexa DXP (formerly eZ Platform Enterprise) subscription,
as described at: https://www.ibexa.co/product
For the full Ibexa BUL license text, please see:
https://www.ibexa.co/software-information/licenses-and-agreements (latest version applies)

AND

B - GNU General Public License, version 2
Grants an copyleft open source license with ABSOLUTELY NO WARRANTY. For the full GPL license text, please see:
https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
