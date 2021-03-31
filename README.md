# Helm Publisher

A GitHub Action for running dependabot in Github Enterpise

## What it can do 

This action will check your dependencies based on the given package_manager.
Then it will create (or update) Pull Requests.

## What it cannot do:

### automatic rebase

It will not automatically check for mergability of its Pull Requests and automatically rebase the PR.

The action needs to be triggered, so the PRs are rebased.

### act on @dependabot messages

It cannot act on Messages like `@dependabot rebase` or `@dependabot merge`

## Usage

### Inputs

* `token` The GitHub Enterprise PAT for creating dependabot PRs
* `github_token`  Personal access token for github.com to overcome request limits
* `package_manager` package manager for dependabot, available values: terraform,python,dep,go_modules,hex,composer,npm_and_yarn


## Examples

Package and push all charts in `./charts` dir to `gh-pages` branch:

```yaml
name: dependabot
on:
  workflow_dispatch:
  schedule:
    - cron:  '0 23 * * *' 

jobs:
  dependabot:
    runs-on: [ self-hosted] 
    steps:
      - name: Create or Update Dependabot Pull Requests
        uses: paschdan/dependabot-enterprise-action@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          github_token: ${{ secrets.GITHUB_COM_TOKEN }}
          package_manager: npm_and_yarn
```

The same example but with cached docker image:

```yaml
name: dependabot
on:
  workflow_dispatch:
  schedule:
    - cron:  '0 23 * * *'

jobs:
  dependabot:
    runs-on: [ self-hosted]
    steps:
      - name: Create or Update Dependabot Pull Requests
        uses: docker://ghcr.io/paschdan/dependabot-enterprise-action:v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          github_token: ${{ secrets.GITHUB_COM_TOKEN }}
          package_manager: npm_and_yarn

```
