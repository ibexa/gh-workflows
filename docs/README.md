# Ibexa GitHub Workflows

## Actions

Composite actions published by this repository, used as `ibexa/gh-workflows/actions/<name>@main`.

- `check-composer-package`
- `composer-audit-ignore`
- `composer-install`
- `create-metapackage-tag`
- `frontend-install`
- [`setup-app-git-identity`](#setup-app-git-identity)
- `setup-composer-root-version`
- `yarn-test`

### `setup-app-git-identity`

Generates an installation token for the Ibexa Workflow Automation GitHub App and configures
git so that the commits made later in the job are authored by the App's bot user. Use it in
jobs that commit, tag or push to branches protected by the repository rulesets. The default
`GITHUB_TOKEN` cannot push there.

```yaml
steps:
    -   uses: ibexa/gh-workflows/actions/setup-app-git-identity@main
        id: bot
        with:
            gh-client-id: ${{ secrets.AUTOMATION_CLIENT_ID }}
            gh-client-secret: ${{ secrets.AUTOMATION_CLIENT_SECRET }}

    -   uses: actions/checkout@v7
        with:
            token: ${{ steps.bot.outputs.token }}

    -   run: |
            git commit -m "..."
            git push
```

Inputs: `gh-client-id`, `gh-client-secret`, optional `owner` (defaults to `github.repository_owner`).

Outputs: `token`, `app-slug`, `user-id`, `user-name`, `user-email`. The identity is set with
`git config --global`, so it applies to every repository checked out in the job.
