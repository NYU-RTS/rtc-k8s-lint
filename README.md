## `rtc-k8s-lint`

When this action runs on a pull request, it refreshes a single bot comment with
the latest Flux schema validation failures. The calling workflow **must** grant
the job `pull-requests: write`, e.g.:

```yaml
permissions:
  pull-requests: write
```

Without it, the GitHub API calls to read/write the PR comment fail with a 403.
On non-PR events, the action still emits its normal outputs and step summary.

The `location` input is required and must be relative to the repository root.
By default, the action renders the location as a Kustomize root. To validate a
bare manifest file without Kustomize, set `kustomize: false`. The action
resolves the location inside the container as `/github/workspace/<location>`,
so workflow authors should pass values like `crds.yaml`, `example`, `cicd/dev`,
or `services/api/overlays/prod` rather than container-internal absolute paths.

```yaml
with:
  location: manifest.yaml
  kustomize: false
```

Kustomize rendering is enabled by default:

```yaml
with:
  location: cicd/dev
  kustomize: true
```

If a single PR runs this action against multiple manifest locations (e.g.
`cicd/dev` and `cicd/prod`), each location gets its own persistent comment,
keyed by the `location` input — one run does not overwrite another's comment.

### Custom resources without a public schema

Validation is strict by default: a document whose schema cannot be found in
the public Flux catalog fails the check. If you use exotic CRDs the catalog
doesn't cover, set `skip-missing-schemas: true` to pass
`--skip-missing-schemas` to `flux schema validate`, which skips those
documents instead of failing:

```yaml
with:
  skip-missing-schemas: true
```

### Private remote Kustomize bases

If your `kustomization.yaml` pulls in resources from a remote git repository
(e.g. `https://github.com/org/repo//path?ref=main`), Kustomize resolves that
by shelling out to `git` inside the action's container. For private repos,
the container needs credentials to clone them. The `github-token` input is
used to configure the GitHub CLI credential helper for those clones and
defaults to the workflow's `GITHUB_TOKEN`. If the remote base lives in a
different repo or org than the one running the workflow, pass a fine-grained
PAT or GitHub App token with access to that repo:

```yaml
with:
  github-token: ${{ secrets.CROSS_REPO_TOKEN }}
```

No username is needed with this flow. The older implementation embedded
credentials into rewritten HTTPS URLs, which required a username field for
basic auth. The current implementation lets git ask the GitHub CLI credential
helper for credentials instead, so the token is supplied directly and the
workflow does not need a separate `github-username` input.

### Hardened setup for untrusted pull requests

By default the action runs Kustomize on the PR's code and then posts the
comment from the same job, so that job holds a token with
`pull-requests: write`, and the default `github-token` is also handed to the
lint container. That is fine for trusted contributors. For PRs from forks, or
any workflow that runs PR code under `pull_request_target`, split linting
from commenting so untrusted code never shares a job with a write token:

1. A `pull_request` workflow lints with read-only permissions. It sets
   `comment: false` and `github-token: ''`, so no token enters the container,
   then uploads the report as an artifact.
2. A `workflow_run` workflow posts comments with the `comment` sub-action. It
   never checks out or runs PR code, and treats the artifact as untrusted. It
   only comments on a PR whose current head commit is the one that was linted.

`workflow_run` is used rather than `pull_request_target` because a
`pull_request_target` run starts at the same time as the `pull_request` run and
cannot see its artifacts.

```yaml
# .github/workflows/k8s-lint.yml
name: k8s-lint
on: pull_request
permissions:
  contents: read
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - id: lint
        uses: NYU-RTS/rtc-k8s-lint@v0.24.0
        with:
          location: cicd/dev
          comment: false
          # Only needed for private remote bases: a read-only contents token.
          github-token: ''
      - if: always() && steps.lint.outputs.report-path
        uses: actions/upload-artifact@v7
        with:
          name: rtc-k8s-lint-reports
          path: ${{ runner.temp }}/rtc-k8s-lint/
```

```yaml
# .github/workflows/k8s-lint-comment.yml
name: k8s-lint-comment
on:
  workflow_run:
    workflows: [k8s-lint]
    types: [completed]
permissions:
  actions: read        # download the artifact from the lint run
  pull-requests: write # post the comment
jobs:
  comment:
    if: github.event.workflow_run.event == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: rtc-k8s-lint-reports
          path: ${{ runner.temp }}/reports
          run-id: ${{ github.event.workflow_run.id }}
          github-token: ${{ github.token }}
      - uses: NYU-RTS/rtc-k8s-lint/comment@v0.24.0
        with:
          reports-dir: ${{ runner.temp }}/reports
```

If remote bases are private, replace `github-token: ''` with a separate token
that only has `contents: read` on those repositories. The lint job still fails
when validation fails, so the PR check status is unchanged; only the comment
moves to the trusted workflow.
