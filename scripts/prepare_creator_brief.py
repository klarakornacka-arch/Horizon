from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


TOP_HEADING = "## 今日优先选题 Top 3"
TOP_HEADING_RE = re.compile(r"^## 今日优先选题 Top 3[ \t]*\r?$", re.MULTILINE)
EXCLUDED = {
    "今日 AI 核心趋势概览",
    "模型与行业动态",
    "AI 工具与工作流",
    "编程与开源项目",
    "商业、创业与变现",
    "今日优先选题 Top 3",
}


def clean_heading(value: str) -> str:
    """Return a rendered item heading as a plain title."""
    value = re.sub(r"\s+⭐️\s+\S+\s*$", "", value.strip())
    value = re.sub(r"^\[(.+?)\]\(.+?\)$", r"\1", value)
    return re.sub(r"\s+", " ", value).strip()


def item_titles(markdown: str) -> list[str]:
    """Return distinct item titles in their rendered Markdown order."""
    titles: list[str] = []
    for match in re.finditer(r"^#{3,4}\s+(.+?)\s*$", markdown, re.MULTILINE):
        title = clean_heading(match.group(1))
        if title and title not in EXCLUDED and title not in titles:
            titles.append(title)
    return titles


def prepare_markdown(markdown: str, report_date: str) -> str:
    """Append one creator-focused priority section to generated Markdown."""
    marker = f"<!-- ai-frontier-radar:{report_date} -->"
    if marker in markdown or TOP_HEADING_RE.search(markdown):
        return markdown

    titles = item_titles(markdown)[:3]
    if not titles:
        raise ValueError("No eligible briefing item headings were found")

    newline = "\r\n" if "\r\n" in markdown else "\n"
    if markdown.endswith(newline * 2):
        separator = ""
    elif markdown.endswith(newline):
        separator = newline
    else:
        separator = newline * 2

    lines = [marker, TOP_HEADING, ""]
    lines.extend(f"{index}. {title}" for index, title in enumerate(titles, start=1))
    return markdown + separator + newline.join(lines) + newline


def select_latest_chinese_post(posts_dir: Path, report_date: str) -> Path:
    """Select the requested day's Chinese generated post."""
    expected = posts_dir / f"{report_date}-summary-zh.md"
    if expected.is_file():
        return expected

    near_matches = sorted(posts_dir.glob(f"{report_date}-summary-zh-*.md"))
    if len(near_matches) > 1:
        raise FileExistsError(f"Multiple generated Chinese posts for {report_date}")
    raise FileNotFoundError(f"No generated Chinese post for {report_date}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--posts-dir", type=Path, default=Path("docs/_posts"))
    parser.add_argument("--date", required=True)
    args = parser.parse_args()

    try:
        post = select_latest_chinese_post(args.posts_dir, args.date)
        original_bytes = post.read_bytes()
        original = original_bytes.decode("utf-8")
        prepared = prepare_markdown(original, args.date)
    except (FileNotFoundError, FileExistsError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1

    if prepared != original:
        post.write_bytes(prepared.encode("utf-8"))
    print(post.as_posix())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
