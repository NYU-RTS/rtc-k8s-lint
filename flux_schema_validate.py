import argparse
import json
import os
import sys
import urllib.error
import urllib.request

API_ROOT = "https://api.github.com"


def comment_marker(manifest):
    # Keyed by manifest path so a repo validating multiple locations (e.g.
    # cicd/dev and cicd/prod) gets one persistent comment per location
    # instead of each run deleting/overwriting the others'.
    return f"<!-- rtc-k8s-lint:{manifest} -->"


def github_request(method, path, token, payload=None):
    request_body = None
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if payload is not None:
        request_body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        f"{API_ROOT}/{path}",
        data=request_body,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request) as response:
            return response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        if error.code == 403:
            print(
                "::error::GitHub API returned 403 Forbidden. This workflow "
                "needs `permissions: pull-requests: write` to post the "
                "validation comment; see README.md.",
                file=sys.stderr,
            )
            sys.exit(1)
        raise


def load_comments(repo, pr_number, token):
    response = github_request("GET", f"repos/{repo}/issues/{pr_number}/comments", token)
    return json.loads(response)


def delete_existing_comment(repo, pr_number, token, manifest):
    marker = comment_marker(manifest)
    for comment in load_comments(repo, pr_number, token):
        body = comment.get("body") or ""
        if comment["user"]["login"] == "github-actions[bot]" and marker in body:
            github_request(
                "DELETE",
                f"repos/{repo}/issues/comments/{comment['id']}",
                token,
            )


def format_subject(resource):
    namespace = resource.get("namespace") or "<cluster>"
    return "{apiVersion} {kind} {namespace}/{name}".format(
        apiVersion=resource["apiVersion"],
        kind=resource["kind"],
        namespace=namespace,
        name=resource["name"],
    )


def build_comment_body(report, manifest):
    invalid_results = [
        entry
        for entry in report.get("report", {}).get("results", [])
        if entry.get("status") != "valid"
    ]
    if not invalid_results:
        return None

    lines = [
        comment_marker(manifest),
        f"## Flux schema validation failed for `{manifest}`",
        "",
    ]
    for entry in invalid_results:
        lines.append(f"- `{format_subject(entry['resource'])}`")
        for violation in entry.get("violations", []):
            detail = violation["message"]
            if violation.get("path"):
                detail = f"`{violation['path']}`: {detail}"
            lines.append(f"  - {detail}")
    return "\n".join(lines)


def update_step_summary(body):
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    with open(summary_path, "a", encoding="utf-8") as summary_file:
        if body is None:
            summary_file.write("## Flux schema validation passed\n")
        else:
            summary_file.write(f"{body}\n")


def publish_comment(repo, pr_number, token, body):
    if body is None:
        return
    github_request(
        "POST",
        f"repos/{repo}/issues/{pr_number}/comments",
        token,
        {"body": body},
    )


parser = argparse.ArgumentParser(
    prog="flux_schema_validate.py",
    description="Publish Flux schema validation results to a pull request comment.",
)
parser.add_argument("--manifest", required=True)
parser.add_argument("--pr-number", required=True)
parser.add_argument("--repo", required=True)

if __name__ == "__main__":
    args = parser.parse_args()
    token = os.environ["GH_TOKEN"]
    report = json.loads(os.environ["VALIDATION_JSON"])
    body = build_comment_body(report, args.manifest)
    delete_existing_comment(args.repo, args.pr_number, token, args.manifest)
    publish_comment(args.repo, args.pr_number, token, body)
    update_step_summary(body)
