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

If a single PR runs this action against multiple manifest locations (e.g.
`cicd/dev` and `cicd/prod`), each location gets its own persistent comment,
keyed by the `location` input — one run does not overwrite another's comment.

