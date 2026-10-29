"""Post Flux schema validation comments from reports produced by an untrusted run.

Runs in a trusted job separate from the lint job (see comment/action.yml). The reports come
from an artifact that the pull request's own workflow uploaded, so a malicious
PR can make them say anything. Every field is validated, and the target PR is
only trusted after confirming its head commit is the one the lint run built.
"""

import argparse
import json
import os
import sys

from flux_schema_validate import (
    build_comment_body,
    delete_existing_comment,
    github_request,
    publish_comment,
)

MAX_REPORTS = 50
MAX_REPORT_BYTES = 5 * 1024 * 1024
MAX_LOCATION_LENGTH = 256
# GitHub rejects comment bodies over 65536 characters.
MAX_COMMENT_LENGTH = 60000


class InvalidReport(Exception):
    pass


def validate_report(report):
    if not isinstance(report, dict):
        raise InvalidReport("report is not a JSON object")

    location = report.get("location")
    if (
        not isinstance(location, str)
        or not location
        or len(location) > MAX_LOCATION_LENGTH
        # The location is embedded in an HTML comment marker and a markdown
        # heading, so reject anything that could break out of either.
        or any(not ch.isprintable() for ch in location)
        or any(token in location for token in ("-->", "`", "<", ">"))
    ):
        raise InvalidReport("invalid location")

    pr_number = report.get("pr_number")
    # bool is a subclass of int, so exclude it explicitly.
    if not isinstance(pr_number, int) or isinstance(pr_number, bool) or pr_number <= 0:
        raise InvalidReport("invalid pr_number")

    validation = report.get("validation")
    if not isinstance(validation, dict):
        raise InvalidReport("invalid validation")

    return location, pr_number, validation


def load_reports(reports_dir):
    names = sorted(
        name
        for name in os.listdir(reports_dir)
        if name.endswith(".json")
        and os.path.isfile(os.path.join(reports_dir, name))
        and not os.path.islink(os.path.join(reports_dir, name))
    )
    if len(names) > MAX_REPORTS:
        raise InvalidReport(f"too many reports ({len(names)} > {MAX_REPORTS})")
    for name in names:
        path = os.path.join(reports_dir, name)
        if os.path.getsize(path) > MAX_REPORT_BYTES:
            raise InvalidReport(f"{name} is too large")
        with open(path, encoding="utf-8") as report_file:
            yield name, json.load(report_file)


def pr_matches_head(repo, pr_number, head_sha, token):
    pull = json.loads(github_request("GET", f"repos/{repo}/pulls/{pr_number}", token))
    return pull.get("state") == "open" and pull.get("head", {}).get("sha") == head_sha


def safe_comment_body(validation, location):
    try:
        body = build_comment_body(validation, location)
    except (KeyError, TypeError, AttributeError) as error:
        raise InvalidReport(f"malformed validation report: {error!r}") from error
    if body is not None and len(body) > MAX_COMMENT_LENGTH:
        body = body[:MAX_COMMENT_LENGTH] + "\n\n_Output truncated; see the lint job log._"
    return body


parser = argparse.ArgumentParser(
    prog="post_pr_comments.py",
    description="Publish Flux schema validation reports from an untrusted artifact as PR comments.",
)
parser.add_argument("--reports-dir", required=True)
parser.add_argument("--repo", required=True)
parser.add_argument("--head-sha", required=True)

if __name__ == "__main__":
    args = parser.parse_args()
    token = os.environ["GH_TOKEN"]
    if not os.path.isdir(args.reports_dir):
        print(f"::notice::no reports found in {args.reports_dir}")
        sys.exit(0)

    failed = False
    for name, report in load_reports(args.reports_dir):
        try:
            location, pr_number, validation = validate_report(report)
            body = safe_comment_body(validation, location)
        except InvalidReport as error:
            print(f"::warning::skipping {name}: {error}")
            failed = True
            continue

        if not pr_matches_head(args.repo, pr_number, args.head_sha, token):
            print(
                f"::warning::skipping {name}: PR #{pr_number} is not open at "
                f"{args.head_sha}"
            )
            continue

        delete_existing_comment(args.repo, pr_number, token, location)
        publish_comment(args.repo, pr_number, token, body)

    sys.exit(1 if failed else 0)
