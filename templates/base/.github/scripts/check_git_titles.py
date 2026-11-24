"""Check the title of a pull request and its new non-merge commits.

Format: '<type>[(scope)][!]: <summary containing Korean>' — e.g. 'feat: 로그인 화면 추가'.
"""

import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path


TITLE = re.compile(
    r"(?:feat|fix|docs|refactor|perf|test|style|build|ci|chore|revert)"
    r"(?:\([a-z0-9]+(?:-[a-z0-9]+)*\))?!?: (?P<summary>\S.*)"
)
HANGUL = re.compile(r"[가-힣]")


def valid_title(title):
    match = TITLE.fullmatch(unicodedata.normalize("NFC", title.strip()))
    return match is not None and HANGUL.search(match["summary"]) is not None


def main(event_path):
    pr = json.loads(Path(event_path).read_text(encoding="utf-8"))["pull_request"]
    base = pr["base"]["sha"]
    head = pr["head"]["sha"]
    commits = subprocess.check_output(
        ["git", "log", "-z", "--no-merges", "--format=%h%x00%s", f"{base}..{head}", "--"],
        encoding="utf-8",
    ).split("\0")
    invalid = []
    if not valid_title(pr["title"]):
        invalid.append("PR 제목")
    invalid.extend(
        f"커밋 {sha}" for sha, title in zip(commits[0:-1:2], commits[1::2])
        if not valid_title(title)
    )
    if invalid:
        print(f"제목 형식을 확인해 주세요. {', '.join(invalid)}", file=sys.stderr)
        print("형식은 'feat: 로그인 화면 추가'입니다.", file=sys.stderr)
        print("docs/development/PR-ISSUE-GUIDE.md에 허용 유형이 있습니다.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
