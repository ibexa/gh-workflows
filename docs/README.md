# Ibexa GitHub Workflows

## Actions

Composite actions published by this repository, used as `ibexa/gh-workflows/actions/<name>@main`.

- [`check-composer-package`](#check-composer-package)
- [`composer-audit-ignore`](#composer-audit-ignore)
- [`composer-install`](#composer-install)
- [`create-metapackage-tag`](#create-metapackage-tag)
- [`frontend-install`](#frontend-install)
- [`setup-app-git-identity`](#setup-app-git-identity)
- [`setup-composer-root-version`](#setup-composer-root-version)
- [`yarn-test`](#yarn-test)

### `check-composer-package`

Checks that a package version is available in a Composer repository: Packagist by default,
or a Satis instance such as `updates.ibexa.co` when `repository-url` and the auth inputs are
given. With `retry` enabled it re-checks on the `retry-schedule` delays before failing, for
packages that are being published while the caller runs. Leave `retry` disabled when the
absence means a mistake that should fail fast.

```yaml
steps:
    -   uses: ibexa/gh-workflows/actions/check-composer-package@main
        with:
            package: ibexa/experience
            version: v4.6.30
            repository-url: https://updates.ibexa.co
            auth-key: ${{ secrets.SATIS_NETWORK_KEY }}
            auth-token: ${{ secrets.SATIS_NETWORK_TOKEN }}
            retry: 'true'
```

Inputs: `package` and `version` (as published, e.g. `v4.6.30`), optional `repository-url`
(defaults to `https://repo.packagist.org`), `auth-key` / `auth-token` (HTTP basic auth, e.g.
the Satis network key and token), `retry` (defaults to `false`) and `retry-schedule`
(space-separated delays in seconds, defaults to `30 60 120 300 300 300 300 300`).

Fails with a `::error::` annotation when the version is not found after the last re-check.

### `composer-audit-ignore`

Configures the Composer `audit.ignore` list for CI tests in an allow-list way, using the
`configure_composer_audit_ignores.sh` script from `ibexa/ci-scripts`. `composer-install`
already calls it, so use it directly only when dependencies are installed another way.

```yaml
steps:
    -   uses: ibexa/gh-workflows/actions/composer-audit-ignore@main
        with:
            php-version: '8.3'
```

Inputs: `php-version` and optional `ci-scripts-ref` (branch or ref of `ibexa/ci-scripts`,
defaults to `main`).

### `composer-install`

Sets up PHP, configures the credentials for private packages and installs the PHP
dependencies with Composer. When `dependencies.json` is present in the repository root, it
updates `composer.json` first, which lets a PR be tested against an unmerged branch of
another `ibexa/*` package. Known unsolvable advisories are ignored through
`composer-audit-ignore`.

```yaml
steps:
    -   uses: actions/checkout@v7

    -   uses: ibexa/gh-workflows/actions/setup-composer-root-version@main

    -   uses: ibexa/gh-workflows/actions/composer-install@main
        with:
            php-version: ${{ matrix.php }}
            gh-client-id: ${{ secrets.AUTOMATION_CLIENT_ID }}
            gh-client-secret: ${{ secrets.AUTOMATION_CLIENT_SECRET }}
            satis-network-key: ${{ secrets.SATIS_NETWORK_KEY }}
            satis-network-token: ${{ secrets.SATIS_NETWORK_TOKEN }}
```

Inputs: `gh-client-id` and `gh-client-secret` (the GitHub App client ID and private key, used
to generate a token for `github-oauth.github.com`), optional `satis-network-key` /
`satis-network-token` (added as `http-basic.updates.ibexa.co` when both are set),
`php-version` (falls back to the calling job's `matrix.php` when empty; jobs without a PHP
matrix should set it explicitly), `php-extensions` (defaults to `pdo_sqlite, gd`), `coverage`
(the setup-php driver, defaults to `none`), `composer-options` (passed to
`ramsey/composer-install`) and `ci-scripts-ref` (defaults to `main`).

`dependencies.json` format, one entry per package to override:

```json
{
    "recipesEndpoint": "",
    "packages": [
        {
            "package": "ibexa/admin-ui",
            "requirement": "dev-my-branch as 6.0.x-dev",
            "repositoryUrl": "https://github.com/ibexa/admin-ui.git",
            "shouldBeAddedAsVCS": false
        }
    ]
}
```

Packages absent from `require` and `require-dev` are skipped. `shouldBeAddedAsVCS: true`
registers `repositoryUrl` as a VCS repository, needed for forks and private repositories.
The file is a testing aid: commit it separately and remove it before merging.

### `create-metapackage-tag`

Sets the dependency versions of a metapackage for a release, from the
`releases/<version>/release.json` definition in the release repository, updates
`composer.lock`, and, when `real-op` is enabled, commits, tags `v<version>` and pushes the tag
using a GitHub App token. The caller checks out the repository first with
`persist-credentials: false`; the action authenticates git through `gh` for its own push.

```yaml
steps:
    -   uses: actions/checkout@v7
        with:
            persist-credentials: false

    -   uses: ibexa/gh-workflows/actions/create-metapackage-tag@main
        with:
            version: 4.6.30
            pin-packages: |
                ibexa/experience
                ibexa/commerce
            real-op: ${{ inputs.real-op }}
            gh-client-id: ${{ secrets.AUTOMATION_CLIENT_ID }}
            gh-client-secret: ${{ secrets.AUTOMATION_CLIENT_SECRET }}
            satis-network-key: ${{ secrets.SATIS_NETWORK_KEY }}
            satis-network-token: ${{ secrets.SATIS_NETWORK_TOKEN }}
```

Inputs: `version` (without the `v` prefix, e.g. `4.5.6-beta1`), `pin-packages`
(newline-separated package names pinned to the release version), `gh-client-id`,
`gh-client-secret`, `satis-network-key`, `satis-network-token`, optional `real-op` (defaults
to `false`, which stops after `composer update` and `composer validate`), `git-push-args`
(e.g. `--force-with-lease`), `php-version` (defaults to `8.3`) and `release-repository`
(defaults to `ibexa/release-maker`).

The steps, each in its own script under `actions/create-metapackage-tag/`: fetch the release
map, set the minimum stability from the version suffix, pin the listed packages to `version`,
patch every `require` entry present in the map (pinned packages included, so on overlap the
map wins), update the lock file, then commit, tag and push.

### `frontend-install`

Sets up Node.js and installs the npm packages that backend test suites need, from the
lockfile shipped with the action. Currently this is `@typescript-eslint/typescript-estree`,
used by the `ibexa/admin-ui` translation extractor to read `Translator.trans()` calls from
TypeScript sources. Add it next to `composer-install` in packages that ship `.ts` / `.tsx`
files.

```yaml
steps:
    -   uses: ibexa/gh-workflows/actions/composer-install@main
        with:
            # ...

    -   uses: ibexa/gh-workflows/actions/frontend-install@main
```

Inputs: optional `node-version` (defaults to `24`).

The packages are exposed as `node_modules/` in the repository root, which Node searches both
in `ibexa/admin-ui` itself and in packages having it in `vendor/`.

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

### `setup-composer-root-version`

Sets the `COMPOSER_ROOT_VERSION` environment variable for the rest of the job from the
`extra.branch-alias.dev-main` value of `composer.json`, so that Composer resolves the package
under test as that version instead of guessing it from the checked-out ref. Run it after the
checkout and before `composer-install`.

```yaml
steps:
    -   uses: actions/checkout@v7

    -   uses: ibexa/gh-workflows/actions/setup-composer-root-version@main
```

No inputs.

### `yarn-test`

Runs a Yarn script, `test` by default, while capturing its output. When the script fails, the
log is inspected for known error signatures and the relevant configuration is dumped into the
CI log, so that the failure is diagnosable without reproducing it locally. For a TypeScript
error it prints `tsconfig.json`, the `@ibexa/ts-config` base it extends and the effective
configuration from `tsc --showConfig`.

```yaml
steps:
    -   run: yarn install

    -   uses: ibexa/gh-workflows/actions/yarn-test@main
        with:
            script: test
```

Inputs: optional `script` (defaults to `test`).
