#!/usr/bin/env python3
"""Audit GitHub Actions workflow safety for open-source pull requests."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


WORKFLOW_GLOBS = ("*.yml", "*.yaml")
DANGEROUS_PR_TERMS = re.compile(r"\b(deploy|deployment|publish|sign|attestation|provenance|upload-artifact|push image|docker push)\b", re.I)
WRITE_PERMISSION = re.compile(r"(?m)^\s*[a-z-]+:\s*write\s*$")
TOP_LEVEL_PERMISSIONS = re.compile(r"(?m)^permissions:")
# Attacker-controlled contexts that must reach run: scripts through env:, never by interpolation.
UNTRUSTED_CONTEXT = re.compile(r"\$\{\{\s*(github\.event\.(issue|pull_request|comment|review|review_comment|discussion|commits|head_commit|pages)\b|github\.head_ref)")
# Install commands Scorecard's Pinned-Dependencies counts as unpinned.
UNPINNED_INSTALL = re.compile(r"\bnpm\s+(i|install|update)\b|\bpip3?\s+install\b(?!.*(--require-hashes|--no-deps))")


@dataclass
class Finding:
    severity: str
    check: str
    path: str
    message: str


def workflow_files(root: Path) -> list[Path]:
    workflows = root / ".github" / "workflows"
    if not workflows.exists():
        return []
    files: list[Path] = []
    for pattern in WORKFLOW_GLOBS:
        files.extend(workflows.glob(pattern))
    return sorted(files)


def has_trigger(text: str, trigger: str) -> bool:
    return bool(re.search(rf"(?m)^\s*{re.escape(trigger)}\s*:", text) or re.search(rf"(?m)^\s*-\s*{re.escape(trigger)}\s*$", text))


def workflow_name(text: str, fallback: str) -> str:
    match = re.search(r"(?m)^\s*name:\s*(.+?)\s*$", text)
    return match.group(1).strip("'\"") if match else fallback


def unpinned_uses(text: str) -> list[str]:
    """Actions and reusable workflows not pinned to a full SHA, GitHub-owned ones included."""
    uses = re.findall(r"(?m)^\s*(?:-\s*)?uses:\s*['\"]?([^@\s'\"]+)@([^\s'\"]+)", text)
    risky: list[str] = []
    for action, ref in uses:
        if action.startswith("./") or action.startswith("docker://"):
            continue
        if not re.fullmatch(r"[a-f0-9]{40}", ref):
            risky.append(f"{action}@{ref}")
    return risky


def run_scripts(text: str) -> list[str]:
    """Bodies of run: steps, inline or block scalar."""
    scripts: list[str] = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        match = re.match(r"^(\s*)(?:-\s*)?run:\s*(.*)$", line)
        if not match:
            continue
        indent, rest = len(match.group(1)), match.group(2).strip()
        if rest and rest[0] not in "|>":
            scripts.append(rest)
            continue
        body: list[str] = []
        for following in lines[i + 1:]:
            if following.strip() and len(following) - len(following.lstrip()) <= indent:
                break
            body.append(following)
        scripts.append("\n".join(body))
    return scripts


def checkouts_persisting_credentials(text: str) -> int:
    """actions/checkout steps that leave the token in .git/config for later steps to read."""
    count = 0
    blocks = re.split(r"(?m)^\s*-\s+(?=\S)", text)
    for block in blocks:
        if re.search(r"uses:\s*actions/checkout@", block) and not re.search(r"persist-credentials:\s*false", block):
            count += 1
    return count


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="ignore")
    except OSError:
        return ""


def audit(root: Path) -> dict[str, object]:
    root = root.resolve()
    findings: list[Finding] = []
    workflows = workflow_files(root)
    if not workflows:
        findings.append(Finding("blocker", "workflows", ".", "missing .github/workflows CI configuration"))
        return report(root, findings)

    pr_workflow_count = 0
    compliance_like = False
    sast = False
    scorecard = False

    for path in workflows:
        rel = str(path.relative_to(root))
        text = path.read_text(encoding="utf-8", errors="ignore")
        lower = text.lower()
        name = workflow_name(text, rel).lower()
        has_pr = has_trigger(text, "pull_request")
        has_pr_target = has_trigger(text, "pull_request_target")
        if has_pr:
            pr_workflow_count += 1
        if any(term in name or term in lower for term in ("compliance", "readiness", "security", "license")):
            compliance_like = True

        if TOP_LEVEL_PERMISSIONS.search(text):
            findings.append(Finding("ok", "permissions_declared", rel, "top-level permissions present"))
        elif "permissions:" in text:
            findings.append(Finding("warn", "permissions_declared", rel, "only job-level permissions; add top-level `permissions: contents: read` (Scorecard Token-Permissions)"))
        else:
            findings.append(Finding("blocker", "permissions_declared", rel, "missing explicit least-privilege permissions"))

        if re.search(r"(?m)^\s*permissions:\s*write-all\s*$", text):
            findings.append(Finding("blocker", "permissions_write_all", rel, "uses permissions: write-all"))

        if has_pr_target:
            findings.append(Finding("blocker", "pull_request_target", rel, "pull_request_target requires maintainer-reviewed justification"))

        if has_pr and "secrets." in text:
            findings.append(Finding("blocker", "pr_secrets", rel, "pull_request workflow references secrets"))

        if has_pr and DANGEROUS_PR_TERMS.search(text):
            findings.append(Finding("blocker", "pr_release_or_deploy", rel, "pull_request workflow appears to publish, release, sign, upload, or deploy"))

        writes = [m.group(0).strip() for m in WRITE_PERMISSION.finditer(text)]
        if "codeql-action/" in text:
            writes = [w for w in writes if not w.startswith("security-events:")]
        if has_pr and writes:
            findings.append(Finding("warn", "pr_write_permissions", rel, "pull_request workflow requests write permission; verify this is necessary and fork-safe"))

        if "concurrency:" in text:
            findings.append(Finding("ok", "concurrency", rel, "concurrency control present"))
        else:
            findings.append(Finding("warn", "concurrency", rel, "missing concurrency cancellation"))

        for action in unpinned_uses(text):
            findings.append(Finding("warn", "unpinned_action", rel, f"action is not pinned to a full commit SHA: {action}"))

        scripts = run_scripts(text)
        if any(UNTRUSTED_CONTEXT.search(script) for script in scripts):
            findings.append(Finding("blocker", "script_injection", rel, "run: step interpolates untrusted event data; pass it through env: instead"))
        for script in scripts:
            for line in script.splitlines():
                if UNPINNED_INSTALL.search(line):
                    findings.append(Finding("warn", "unpinned_install", rel, f"install is not lockfile- or hash-pinned: {line.strip()}"))

        persisting = checkouts_persisting_credentials(text)
        if persisting:
            findings.append(Finding("warn", "persist_credentials", rel, f"{persisting} checkout step(s) without persist-credentials: false"))

        if "codeql-action/analyze" in text or "codeql-action/init" in text:
            sast = True
        if "ossf/scorecard-action" in text:
            scorecard = True

    if pr_workflow_count:
        findings.append(Finding("ok", "pull_request_checks", ".github/workflows", f"{pr_workflow_count} pull_request workflow(s) detected"))
    else:
        findings.append(Finding("blocker", "pull_request_checks", ".github/workflows", "no pull_request validation workflow detected"))

    if compliance_like:
        findings.append(Finding("ok", "compliance_workflow", ".github/workflows", "compliance/security/license workflow detected"))
    else:
        findings.append(Finding("warn", "compliance_workflow", ".github/workflows", "add compliance checks for README, license, workflows, secrets, and required files"))

    if sast:
        findings.append(Finding("ok", "sast", ".github/workflows", "CodeQL workflow detected"))
    else:
        findings.append(Finding("warn", "sast", ".github/workflows", "no CodeQL workflow; Scorecard SAST expects every merged commit to be scanned"))

    if scorecard:
        findings.append(Finding("ok", "scorecard", ".github/workflows", "OpenSSF Scorecard workflow detected"))
    else:
        findings.append(Finding("warn", "scorecard", ".github/workflows", "no OpenSSF Scorecard workflow publishing results"))

    codeowners = root / ".github" / "CODEOWNERS"
    if codeowners.exists() or (root / "CODEOWNERS").exists():
        findings.append(Finding("ok", "codeowners", "CODEOWNERS", "CODEOWNERS present"))
    else:
        findings.append(Finding("warn", "codeowners", ".", "missing CODEOWNERS for sensitive path ownership documentation"))

    maintainers = root / "MAINTAINERS.md"
    if maintainers.exists():
        text = read_text(maintainers)
        if "cigan1@gmail.com" in text:
            findings.append(Finding("ok", "maintainers_roster", "MAINTAINERS.md", "maintainer roster includes cigan1@gmail.com"))
        else:
            findings.append(Finding("blocker", "maintainers_roster", "MAINTAINERS.md", "maintainer roster must include cigan1@gmail.com"))
    else:
        findings.append(Finding("blocker", "maintainers_roster", ".", "missing MAINTAINERS.md with cigan1@gmail.com"))

    return report(root, findings)


def report(root: Path, findings: Iterable[Finding]) -> dict[str, object]:
    finding_list = list(findings)
    counts: dict[str, int] = {}
    for finding in finding_list:
        counts[finding.severity] = counts.get(finding.severity, 0) + 1
    decision = "no-go" if counts.get("blocker") else "conditional" if counts.get("warn") else "go"
    return {
        "root": str(root),
        "decision": decision,
        "counts": counts,
        "findings": [asdict(finding) for finding in finding_list],
    }


def print_human(data: dict[str, object]) -> None:
    print(f"Workflow readiness: {data['decision']}")
    print(f"Repository: {data['root']}")
    print(f"Counts: {data['counts']}")
    print()
    for finding in data["findings"]:  # type: ignore[index]
        print(f"[{finding['severity']}] {finding['check']} {finding['path']} - {finding['message']}")


def should_fail(data: dict[str, object], fail_on: str) -> bool:
    counts = data["counts"]  # type: ignore[assignment]
    if fail_on == "none":
        return False
    if fail_on == "warn":
        return bool(counts.get("blocker") or counts.get("warn"))  # type: ignore[union-attr]
    return bool(counts.get("blocker"))  # type: ignore[union-attr]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", nargs="?", default=".", help="repository path")
    parser.add_argument("--json", action="store_true", help="emit JSON")
    parser.add_argument("--fail-on", choices=("none", "blocker", "warn"), default="none", help="exit nonzero at this severity")
    args = parser.parse_args()

    data = audit(Path(args.repo))
    if args.json:
        print(json.dumps(data, indent=2, sort_keys=True))
    else:
        print_human(data)
    return 1 if should_fail(data, args.fail_on) else 0


if __name__ == "__main__":
    sys.exit(main())
