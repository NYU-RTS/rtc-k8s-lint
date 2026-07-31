## `rtc-k8s-lint`

When this action runs on a pull request, it can refresh a single bot comment with
the latest Flux schema validation failures. Grant the job `pull-requests: write`
if you want that PR comment behavior. On non-PR events, the action still emits
its normal outputs and step summary.

