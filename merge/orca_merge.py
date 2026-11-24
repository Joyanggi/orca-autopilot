#!/usr/bin/env python3
"""Publish two Orca review verdicts for a PR head and request GitHub auto-merge.

Installed by `oap merge-runner` as `<brew prefix>/bin/<key>-orca-merge` with the
project's settings baked into CONFIG. The coordinator calls only that absolute
path, so code on a work branch never runs with the coordinator's GitHub rights.
"""

import argparse
import json
import re
import subprocess
import sys
import unicodedata
from contextlib import contextmanager, nullcontext
from pathlib import PurePosixPath


CONFIG = None  # oap:config

GITHUB_ACTIONS_APP_ID = 15368
REVIEWERS = ("claude", "codex")
# Paths whose change turns a PR into "owner review required": harness, rules,
# acceptance criteria and data migrations.
PROTECTED = (
    ".claude", ".github", ".codex", "AGENTS.md", "CLAUDE.md", "REVIEW.md", "orca-autopilot.json",
    "docs/development/WORKFLOW.md", "docs/development/PR-ISSUE-GUIDE.md",
    "docs/quality", "docs/product/PRD.md", "docs/product/REQUIREMENTS.md",
    "docs/decisions", "supabase/migrations", "migrations", "db/migrations", "prisma/migrations",
)

REPO = REPO_OWNER = BASE = CI = MARK = BRANCH_PREFIX = LOCK_PREFIX = RECHECK_CONTEXT = ""
CONTEXTS = {}


def configure(config):
    """Set the module globals from the baked (or test) configuration."""
    global REPO, REPO_OWNER, BASE, CI, MARK, BRANCH_PREFIX, LOCK_PREFIX, RECHECK_CONTEXT, CONTEXTS
    REPO = config["repo"]
    REPO_OWNER = REPO.split("/", 1)[0].casefold()
    BASE = config.get("base", "main")
    CI = config["ci"]
    MARK = config["mark"]
    BRANCH_PREFIX = config.get("branch_prefix", "orca/")
    prefix = config["status_prefix"]
    CONTEXTS = {role: f"{prefix}/review-{role}" for role in REVIEWERS}
    RECHECK_CONTEXT = f"{prefix}/recheck-registered"
    LOCK_PREFIX = f"{prefix}-review-lock"


if CONFIG is not None:
    configure(CONFIG)


class Blocked(Exception):
    """A precondition for publishing or merging is missing."""


def run(*argv):
    return subprocess.run(argv, check=True, text=True, stdout=subprocess.PIPE).stdout


def github(*args):
    return json.loads(run("gh", "api", *args))


def orca(verb, flag, value):
    response = json.loads(run(
        "orca", "orchestration", verb, "--environment", "local", flag, value, "--json", "--full"
    ))
    if not response.get("ok"):
        raise Blocked(f"Orca rejected {verb}.")
    return response["result"]


def verify_review(run_id, sha, role, dispatch_id, worker, tasks):
    dispatch = worker.get("dispatch") or {}
    details = worker.get("worker") or {}
    launch = (details.get("startOptions") or {}).get("launch") or {}
    task = tasks.get(dispatch.get("taskId"), {})
    if (
        dispatch.get("id") != dispatch_id or dispatch.get("runId") != run_id
        or dispatch.get("status") != "completed" or details.get("state") != "succeeded"
        or (launch.get("effective") or {}).get("agent") != role
        or task.get("status") != "completed"
    ):
        raise Blocked(f"{role} lacks a completed review dispatch in this run.")
    report = json.loads(task.get("result") or "{}")
    if (
        report.get("provenance") != "worker_report" or report.get("outcome") != "succeeded"
        or not dispatch.get("assigneeHandle") or report.get("reportedBy") != dispatch["assigneeHandle"]
        or report.get("filesModified") != []
        or f"{MARK}-TARGET {sha}" not in (task.get("spec") or "").splitlines()
    ):
        raise Blocked(f"{role} did not return an attributable read-only report for this SHA.")
    lines = (report.get("body") or "").splitlines()
    decision = f"{MARK} {sha} PASS"
    markers = [line for line in lines if line.lstrip().startswith(f"{MARK} ")]
    if not lines or lines[-1] != decision or markers != [decision]:
        raise Blocked(f"{role} did not pass the requested commit.")
    return task["id"]


def verify_review_pair(sha, task_ids, tasks, *, must_recheck=False):
    selected = set(task_ids.values())
    if len(selected) != len(REVIEWERS):
        raise Blocked("The two reviews must be separate tasks.")
    marker = f"{MARK}-RECHECK {sha}"
    rechecks = {
        task_id for task_id, task in tasks.items()
        if marker in map(str.strip, (task.get("spec") or "").splitlines())
    }
    if rechecks and not must_recheck:
        raise Blocked("Register the disagreement recheck in GitHub before using its verdicts.")
    # Registration supersedes the first pair even before either recheck finishes.
    if must_recheck and selected != rechecks:
        raise Blocked("Both PASS reports must come from the disagreement recheck for this SHA.")


@contextmanager
def review_lock(sha):
    ref = f"heads/{LOCK_PREFIX}/{sha}"
    # GitHub's create-only operation lets one coordinator acquire the ref.
    github("-X", "POST", f"repos/{REPO}/git/refs", "-f", f"ref=refs/{ref}", "-f", f"sha={sha}")
    try:
        yield
    finally:
        try:
            run("gh", "api", "-X", "DELETE", f"repos/{REPO}/git/refs/{ref}")
        except (OSError, subprocess.CalledProcessError):
            print(f"Could not release {ref}. Check the PR and active coordinators before retrying.",
                  file=sys.stderr)


def require_coordinator():
    if github("user").get("login", "").casefold() != REPO_OWNER:
        raise Blocked("Only the configured coordinator GitHub account may publish the checks.")


def review_statuses(sha):
    pages = github(f"repos/{REPO}/commits/{sha}/statuses?per_page=100", "--paginate", "--slurp")
    return [entry for page in pages for entry in page]


def registered_recheck(statuses):
    registrations = set()
    for entry in statuses:
        if entry["context"].casefold() != RECHECK_CONTEXT:
            continue
        match = re.fullmatch(r"Orca run (run_[a-z0-9]+)", entry.get("description") or "")
        url = entry.get("target_url") or ""
        if (
            not match or not re.fullmatch(rf"https://github\.com/{re.escape(REPO)}/pull/[1-9][0-9]*", url)
            or entry["state"] != "success"
            or (entry.get("creator") or {}).get("login", "").casefold() != REPO_OWNER
        ):
            raise Blocked("The disagreement recheck registration could not be verified.")
        registrations.add((url, match[1]))
    if len(registrations) > 1:
        raise Blocked("Conflicting disagreement recheck registrations for this commit.")
    return next(iter(registrations), None)


def protected_paths(pages, expected_count):
    changes = [change for page in pages for change in page]
    # GitHub returns at most 3,000 files, irrespective of pagination.
    if not isinstance(expected_count, int) or not 0 < expected_count < 3000 or len(changes) != expected_count:
        raise Blocked("The complete PR file list could not be verified.")
    guarded = {PurePosixPath(item.casefold()) for item in PROTECTED}
    paths = set()
    for change in changes:
        for field in ("filename", "previous_filename"):
            raw_path = change.get(field)
            if not raw_path:
                continue
            path = PurePosixPath(unicodedata.normalize("NFC", raw_path).casefold())
            if path in guarded or guarded.intersection(path.parents):
                paths.add(raw_path)
    return paths


def verify_pr(pr, sha):
    if (
        pr.get("state") != "OPEN" or pr.get("isCrossRepository") is not False
        or pr.get("baseRefName") != BASE or not pr.get("headRefName", "").startswith(BRANCH_PREFIX)
        or pr.get("headRefOid") != sha
    ):
        raise Blocked(f"The PR must be open, target {BASE}, and have the reviewed {BRANCH_PREFIX} head.")


def verify_branch_rules(rules):
    by_type = {rule["type"]: rule for rule in rules}
    status = (by_type.get("required_status_checks") or {}).get("parameters") or {}
    contexts = {check.get("context"): check for check in status.get("required_status_checks", [])}
    if (
        "pull_request" not in by_type or "non_fast_forward" not in by_type
        or "deletion" not in by_type or not status.get("strict_required_status_checks_policy")
        or not set(CONTEXTS.values()).issubset(contexts)
        or contexts.get(CI, {}).get("integration_id") != GITHUB_ACTIONS_APP_ID
    ):
        raise Blocked(f"{BASE} is missing the PR-only or required-check protection. Run 'oap github'.")


def merge_or_queue(pr_number, sha, get_pr):
    command = ("gh", "pr", "merge", str(pr_number), "--repo", REPO,
               "--squash", "--match-head-commit", sha)
    pr = get_pr()
    verify_pr(pr, sha)
    if pr.get("mergeStateStatus") == "CLEAN":
        return run(*command)
    try:
        return run(*command, "--auto")
    except subprocess.CalledProcessError:
        # The last required check can settle while GitHub is receiving the request.
        pr = get_pr()
        if pr.get("state") == "MERGED" and pr.get("headRefOid") == sha:
            return pr["url"]
        verify_pr(pr, sha)
        if pr.get("mergeStateStatus") != "CLEAN":
            raise
        return run(*command)


def process_pr(args):
    def get_pr():
        return json.loads(run(
            "gh", "pr", "view", str(args.pr), "--repo", REPO, "--json",
            "baseRefName,headRefName,headRefOid,isCrossRepository,isDraft,state,url,changedFiles,mergeStateStatus",
        ))

    pr = get_pr()
    verify_pr(pr, args.sha)
    verify_branch_rules(github(f"repos/{REPO}/rules/branches/{BASE}"))
    if not args.verify_only:
        require_coordinator()
        if not args.require_recheck:
            pages = github(f"repos/{REPO}/pulls/{args.pr}/files?per_page=100", "--paginate", "--slurp")
            paths = protected_paths(pages, pr.get("changedFiles"))
            if paths:
                raise Blocked("Automation policy changes require owner review: " + ", ".join(sorted(paths)))
    with nullcontext() if args.verify_only else review_lock(args.sha):
        assess_pr(args, get_pr)


def assess_pr(args, get_pr):
    pr = get_pr()
    verify_pr(pr, args.sha)
    statuses = review_statuses(args.sha)
    registration = registered_recheck(statuses)
    if registration and registration != (pr["url"], args.run):
        raise Blocked("This commit must use the PR and Orca run registered for disagreement recheck.")
    if args.require_recheck:
        if pr.get("isDraft") is not True:
            raise Blocked("Register a disagreement recheck while the PR is in draft.")
        if not registration:
            if any(item["context"].casefold() in CONTEXTS.values() and item["state"] == "success"
                   for item in statuses):
                raise Blocked("Review approvals already exist for this commit. Review a new commit.")
            orca("run-show", "--id", args.run)
            github(
                "-X", "POST", f"repos/{REPO}/statuses/{args.sha}",
                "-f", "state=success", "-f", f"context={RECHECK_CONTEXT}",
                "-f", f"description=Orca run {args.run}", "-f", f"target_url={pr['url']}",
            )
        print(json.dumps({"sha": args.sha, "recheckRun": args.run, "pr": pr["url"]}))
        return
    tasks = {task["id"]: task for task in orca("task-list", "--run", args.run)["tasks"]}
    task_ids = {
        role: verify_review(args.run, args.sha, role, getattr(args, role),
                            orca("worker-show", "--dispatch", getattr(args, role)), tasks)
        for role in REVIEWERS
    }
    verify_review_pair(args.sha, task_ids, tasks, must_recheck=bool(registration))
    if args.verify_only:
        print(json.dumps({"sha": args.sha, "reviews": task_ids, "pr": pr["url"]}))
        return
    pr = get_pr()
    verify_pr(pr, args.sha)
    if registered_recheck(review_statuses(args.sha)) != registration:
        raise Blocked("The disagreement recheck registration changed. Verify the latest reports.")
    for role, task_id in task_ids.items():
        github(
            "-X", "POST", f"repos/{REPO}/statuses/{args.sha}",
            "-f", "state=success", "-f", f"context={CONTEXTS[role]}",
            "-f", f"description=Orca review passed ({task_id})",
            "-f", f"target_url={pr['url']}",
        )
    if pr["isDraft"]:
        run("gh", "pr", "ready", str(args.pr), "--repo", REPO)
    print(merge_or_queue(args.pr, args.sha, get_pr).strip() or pr["url"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--run", required=True)
    parser.add_argument("--claude")
    parser.add_argument("--codex")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--verify-only", action="store_true")
    mode.add_argument("--require-recheck", action="store_true")
    args = parser.parse_args()
    if not REPO:
        parser.exit(2, "This copy has no project configuration. Install it with 'oap merge-runner'.\n")
    if (
        args.pr < 1 or not re.fullmatch(r"[a-f0-9]{40}", args.sha)
        or not re.fullmatch(r"run_[a-z0-9]+", args.run)
    ):
        parser.error("Expected a PR number, full Git SHA and Orca run.")
    refs = (args.claude, args.codex)
    if args.require_recheck:
        if any(ref is not None for ref in refs):
            parser.error("Register a recheck without dispatch IDs.")
    elif not all(ref and re.fullmatch(r"ctx_[a-z0-9]+", ref) for ref in refs) or refs[0] == refs[1]:
        parser.error("Expected two distinct review dispatch IDs.")

    try:
        process_pr(args)
    except (Blocked, OSError, subprocess.CalledProcessError, ValueError, KeyError) as exc:
        parser.exit(1, f"Auto-merge blocked: {exc}\n")


if __name__ == "__main__":
    main()
