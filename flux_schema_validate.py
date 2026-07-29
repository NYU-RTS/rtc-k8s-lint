import json
import os
import subprocess
import sys

manifest = os.environ["MANIFEST"]
pr_number = os.environ["PR_NUMBER"]

result = subprocess.run(
    ["flux", "schema", "validate", "-s", "ecosystem", manifest, "-o", "json"],
    capture_output=True,
    text=True,
)
print(result.stderr, file=sys.stderr)

report = json.loads(result.stdout)
for entry in report["report"]["results"]:
    if entry["status"] == "valid":
        continue
    resource = entry["resource"]
    subject = "{apiVersion} {kind} {namespace}/{name}".format(**resource)
    lines = [f"**flux schema validate** — {manifest}: {subject}"]
    for violation in entry.get("violations", []):
        detail = violation["message"]
        if violation.get("path"):
            detail = f"{violation['path']}: {detail}"
        lines.append(f"- {detail}")
    subprocess.run(
        ["gh", "pr", "comment", pr_number, "--body", "\n".join(lines)],
        check=True,
    )

sys.exit(result.returncode)
