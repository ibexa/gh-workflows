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
- [`validate-release-version`](#validate-release-version)
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

### `validate-release-version`

Checks that a version may be released from a branch, given the tags of the repository checked
out in the working directory (the checkout needs the tags, so `fetch-depth: 0`). It is the
version check of the [`tag.yml`](#tagyml) workflow and can be used on its own.

```yaml
steps:
    -   uses: actions/checkout@v7
        with:
            fetch-depth: 0

    -   uses: ibexa/gh-workflows/actions/validate-release-version@main
        with:
            version: ${{ inputs.version }}
            release-branches: major.x
```

A version passes when all of these hold:

- it is semver without the leading `v` and without leading zeros, e.g. `1.1.5` or `1.2.0-alpha.1`;
- the tag `v<version>` does not exist;
- the branch matches one of the `release-branches` schemes and the version belongs to its line:
  `major.x` (`2.x` releases `2.*.*`), `major.minor` (`5.0` releases `5.0.*`) or `main` (any version);
- it follows the latest stable tag of that line: the next patch, the next minor (not on a
  `major.minor` branch) or the next major (on `main` only). A line without a stable tag starts
  at `X.0.0` (`X.Y.0` on a `major.minor` branch). A prerelease has to be a prerelease of such a
  version; prereleases are not ordered among themselves;
- no tag of the repository looks like a version in another spelling (`1.1.6`, `v1.1`, `v1.1.06`):
  such a tag fails the check, because the sequence cannot be established. Tags that are not
  versions (`latest`) are ignored;
- the commit does not carry a version tag yet, unless `allow-empty-release` is `true`.

With `skip-sequence-check` set to `true` the two sequence rules (following the latest stable tag
and the tags in another spelling) are reported as warnings instead of failing, for a deliberate
exception such as a fix of an older minor. The other rules always apply.

Inputs: `version`, `release-branches`, optional `branch` (defaults to `github.ref_name`),
`require-release-branch` (defaults to `true`; with `false` the check can be rehearsed from any
branch and the line is taken from the version), `allow-empty-release` and `skip-sequence-check`
(both default to `false`).

## Workflows

### `tag.yml`

Releases a version of a repository whose release is a `v<version>` git tag: validates the version
with [`validate-release-version`](#validate-release-version), runs the repository's own bump
command, commits the result as `Released <version>`, creates the annotated tag and pushes the
branch and the tag together as the Ibexa Workflow Automation app. `workflow_dispatch` belongs to
the calling repository, which also runs its own checks before the release:

```yaml
name: Tag

on:
    workflow_dispatch:
        inputs:
            version:
                description: Release version without the leading v, e.g. 1.1.5
                type: string
                required: true
            dry-run:
                description: Run everything without pushing the commit and the tag
                type: boolean
                default: true
            allow-empty-release:
                description: Release a commit that already carries a version tag
                type: boolean
                default: false
            skip-sequence-check:
                description: Release a version that does not follow the latest tag
                type: boolean
                default: false

jobs:
    checks:
        runs-on: ubuntu-26.04
        steps:
            -   uses: actions/checkout@v7
            -   run: yarn install && yarn test

    tag:
        needs: checks
        uses: ibexa/gh-workflows/.github/workflows/tag.yml@main
        with:
            version: ${{ inputs.version }}
            dry-run: ${{ inputs.dry-run }}
            allow-empty-release: ${{ inputs.allow-empty-release }}
            skip-sequence-check: ${{ inputs.skip-sequence-check }}
            release-branches: major.x
            bump-command: npm pkg set "version=$VERSION"
            version-file: package.json
        secrets:
            AUTOMATION_CLIENT_ID: ${{ secrets.AUTOMATION_CLIENT_ID }}
            AUTOMATION_CLIENT_SECRET: ${{ secrets.AUTOMATION_CLIENT_SECRET }}
```

Inputs: `version`, `release-branches`, optional `dry-run` (defaults to `true`), `bump-command`
(the version is available to it as `$VERSION`; the tracked files it changes are committed; empty
means a tag without a commit), `version-file` (a file that has to contain the version after the
bump), `allow-empty-release` and `skip-sequence-check` (both default to `false`).

With `dry-run` the workflow can be run from any branch: the commit and the tag are created on the
runner and `git push --dry-run` shows the refs. A dry run proves the authentication, but the
repository rulesets are only evaluated by a real push. The app has to be a bypass actor of the
rulesets restricting the release branches and the tag creation.
