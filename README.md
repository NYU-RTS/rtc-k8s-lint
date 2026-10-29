## `rtc-k8s-lint`

A GitHub Action that validates Kubernetes manifests against the
[Flux schema catalog](https://schemas.fluxoperator.dev/) using
`flux schema validate`, optionally rendering them with Kustomize first. On pull
requests it also keeps a single bot comment up to date with the latest
validation failures. On other events it still emits its outputs and a step
summary.

```yaml
- uses: NYU-RTS/rtc-k8s-lint@2b1990e39fce12ce48bbee13ad5d6ad82a312c2a # v0.25.0
  with:
    location: cicd/dev
```

### Inputs

| Input                  | Required | Default                 | Description                                                                                         | Since |
| ---------------------- | -------- | ----------------------- | --------------------------------------------------------------------------------------------------- | ------ |
| `location`             | **yes**  |                         | Path to the manifests or Kustomize root, relative to the repository root.                           | v0.3.0 |
| `kustomize`            | no       | `true`                  | Render the location with Kustomize before validating. Set to `false` for a bare manifest file.      | v0.22.0 |
| `skip-missing-schemas` | no       | `false`                 | Skip documents with no schema in the catalog instead of failing. Leave off for strict checking.     | v0.25.0 |
| `github-token`         | no       | `${{ github.token }}`   | Token for cloning private remote Kustomize bases. Use `''` to keep any token out of the container.  | v0.19.0 |
| `comment`              | no       | `true`                  | Refresh the PR comment from this job (needs `pull-requests: write`). `false` only writes a report.  | v0.24.0 |

### Outputs

| Output            | Description                                                                              |
| ----------------- | ---------------------------------------------------------------------------------------- |
| `manifest`        | The manifest passed to Flux schema validation.                                           |
| `validation-json` | The Flux schema validation result in JSON format.                                        |
| `report-path`     | Path to the report for the `comment` sub-action. Set on pull request events (since v0.24.0). |

### `location` (required)

The location must be relative to the repository root. The action resolves it
inside the container as `/github/workspace/<location>`, so pass values like
`crds.yaml`, `example`, `cicd/dev`, or `services/api/overlays/prod` rather than
container-internal absolute paths.

If a single PR runs this action against multiple locations (e.g. `cicd/dev` and
`cicd/prod`), each location gets its own persistent comment, keyed by the
`location` input — one run does not overwrite another's comment.

### `kustomize`

By default the action renders the location as a Kustomize root. To validate a
bare manifest file without Kustomize, disable it:

```yaml
with:
  location: manifest.yaml
  kustomize: false
```

### `skip-missing-schemas`

Validation is strict by default: a document whose schema cannot be found in the
[Flux schema catalog](https://schemas.fluxoperator.dev/) fails the check. Browse
the catalog to see which projects, kinds and versions are supported. If you use
exotic CRDs the catalog doesn't cover, set `skip-missing-schemas: true` to pass
`--skip-missing-schemas` to `flux schema validate`, which skips those documents
instead of failing:

```yaml
with:
  skip-missing-schemas: true
```

Missing projects can also be requested from the catalog maintainers, see the
[schema-catalog repository](https://github.com/controlplaneio-fluxcd/schema-catalog).

### `github-token` (private remote Kustomize bases)

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

### `comment`

When this action runs on a pull request, it refreshes a single bot comment with
the latest Flux schema validation failures. The calling workflow **must** grant
the job `pull-requests: write`, e.g.:

```yaml
permissions:
  pull-requests: write
```

Without it, the GitHub API calls to read/write the PR comment fail with a 403.
To lint without a write token, set `comment: false` and see
[Hardened setup](#hardened-setup-separate-lint-and-comment-jobs).

### Hardened setup: separate lint and comment jobs

By default the action runs Kustomize on the PR's code and then posts the
comment from the same job, so that job holds a token with
`pull-requests: write`, and the default `github-token` is also handed to the
lint container. To keep PR code away from a write token, split linting from
commenting into two jobs in the same workflow:

1. The `lint` job has read-only permissions. It sets `comment: false` and
   `github-token: ''`, so no token enters the container, then uploads the
   report as an artifact.
2. The `comment` job holds `pull-requests: write` and posts comments with the
   `comment` sub-action. It never checks out or runs PR code, and treats the
   artifact as untrusted. It only comments on a PR whose current head commit is
   the one that was linted.

```yaml
# .github/workflows/k8s-lint.yml
name: k8s-lint
on: pull_request
permissions: {}
jobs:
  lint:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    outputs:
      report-path: ${{ steps.lint.outputs.report-path }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - id: lint
        uses: NYU-RTS/rtc-k8s-lint@2b1990e39fce12ce48bbee13ad5d6ad82a312c2a # v0.25.0
        with:
          location: cicd/dev
          comment: false
          # Only needed for private remote bases: a read-only contents token.
          github-token: ''
      - if: always() && steps.lint.outputs.report-path
        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        with:
          name: rtc-k8s-lint-reports
          path: ${{ runner.temp }}/rtc-k8s-lint/
  comment:
    # Run even when validation fails, which is when the comment matters most.
    if: ${{ !cancelled() && needs.lint.outputs.report-path != '' }}
    needs: lint
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write # post the comment
    steps:
      - uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
        with:
          name: rtc-k8s-lint-reports
          path: ${{ runner.temp }}/reports
      - uses: NYU-RTS/rtc-k8s-lint/comment@2b1990e39fce12ce48bbee13ad5d6ad82a312c2a # v0.25.0
        with:
          reports-dir: ${{ runner.temp }}/reports
          head-sha: ${{ github.event.pull_request.head.sha }}
```

If remote bases are private, replace `github-token: ''` with a separate token
that only has `contents: read` on those repositories. The `lint` job still
fails when validation fails, so the PR check status is unchanged; only the
comment moves to the `comment` job.

On `pull_request` runs from forks, GitHub gives the workflow a read-only
`GITHUB_TOKEN` regardless of the `permissions` block, so the `comment` job
cannot post there. Fork PRs still get the failing check and the step summary.
