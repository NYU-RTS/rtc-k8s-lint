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
The action resolves it inside the container as `/github/workspace/<location>`, so
workflow authors should pass values like `example`, `cicd/dev`, or
`services/api/overlays/prod` rather than container-internal absolute paths.

```yaml
with:
  location: cicd/dev
```

If a single PR runs this action against multiple manifest locations (e.g.
`cicd/dev` and `cicd/prod`), each location gets its own persistent comment,
keyed by the `location` input — one run does not overwrite another's comment.

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
