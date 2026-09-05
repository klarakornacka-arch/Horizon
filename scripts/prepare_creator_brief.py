from __future__ import annotations

import argparse
import html
import re
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from urllib.parse import urlparse


TOP_HEADING = "## 今日优先创作与实践 Top 3"
TOP_HEADING_RE = re.compile(
    r"^## 今日优先创作与实践 Top 3[ \t]*\r?$", re.MULTILINE
)
GROWTH_HEADING = "## 今日成长行动"
GROWTH_HEADING_RE = re.compile(r"^## 今日成长行动[ \t]*\r?$", re.MULTILINE)
GENERATOR_MARKER_RE = re.compile(
    r"^<!-- ai-frontier-radar:(\d{4}-\d{2}-\d{2}) -->[ \t]*\r?$", re.MULTILINE
)
REPORT_START_DATE = date(2026, 8, 24)
GROWTH_WEEKS = (
    ("可靠信息与事实核查", "一页 AI 信息源可信度清单"),
    ("版式层级与网格", "三张同主题版式对比稿"),
    ("字体与中文排印", "一套标题、正文与标注字体规范"),
    ("色彩、构图与视觉复盘", "一张视觉研究板和四周复盘"),
    ("用户访谈与真实需求", "访谈提纲和三份洞察记录"),
    ("受众、定位与竞争分析", "目标用户画像与竞品坐标图"),
    ("品牌策略与视觉方向", "品牌策略一页纸和两套情绪板"),
    ("原型、反馈与方向验证", "一轮可验证原型和反馈结论"),
    ("模拟客户发现与项目范围", "模拟需求纪要、范围和排期"),
    ("品牌概念与核心识别", "概念提案和核心视觉识别"),
    ("内容视觉系统与应用", "六张内容模板和一项品牌应用"),
    ("修改、规范与交付包装", "品牌使用指南和交付文件包"),
    ("案例叙事与作品集", "完整案例页初稿"),
    ("服务产品、范围与报价", "一页服务套餐和报价逻辑"),
    ("个人品牌内容与获客", "三篇专业内容和潜在客户清单"),
    ("提案、试点与创业复盘", "客户提案模板、试点方案和复盘"),
)
DAY_VERBS = ("观察", "拆解", "复刻", "改造", "讲解", "包装", "复盘")
REQUIRED_BLOCK_TITLES = (
    "入选依据",
    "审美点评",
    "设计思维",
    "商业视角",
    "创作角度",
    "今日行动",
)
ITEM_HEADING_RE = re.compile(r"^#{3,4}(?!#)\s+(.+?)\s*$", re.MULTILINE)
ITEM_BOUNDARY_RE = re.compile(r"^#{1,4}(?!#)\s+", re.MULTILINE)
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\(([^)\s]+)\)")
EVIDENCE_BLOCK_RE = re.compile(r"^\*\*「([^」\r\n]+)」\*\*(.*)$", re.MULTILINE)
SOURCE_DATE_RE = re.compile(r"(?:^|\n)发布日期\s*[：:]\s*(\d{4}-\d{2}-\d{2})(?:\s|$)")
RAW_HTML_TAG_RE = re.compile(r"</?[A-Za-z][\w-]*\b[^>]*>", re.IGNORECASE)
NONRENDERING_HTML_TAG_RE = re.compile(
    r"</?(?P<tag>template|script|style)\b[^>]*>", re.IGNORECASE
)
BLOCK_HTML_CONTAINER_RE = re.compile(
    r"<\s*/?\s*(?:div|script|template|style)\b", re.IGNORECASE
)
ZERO_WIDTH_RE = re.compile(r"[\u200b-\u200f\u2060\ufeff]")
HTML_ATTRIBUTE_RE = re.compile(
    r"\s+([A-Za-z_:][\w:.-]*)(?:\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s>]+))?"
)
DISPLAY_NONE_RE = re.compile(r"display\s*:\s*none", re.IGNORECASE)
VISIBILITY_HIDDEN_RE = re.compile(r"visibility\s*:\s*hidden\b", re.IGNORECASE)
MARKDOWN_LINK_TEXT_RE = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
EXCLUDED = {
    "今日 AI 核心趋势概览",
    "模型与行业动态",
    "AI 工具与工作流",
    "编程与开源项目",
    "商业、创业与变现",
    "今日优先创作与实践 Top 3",
}


@dataclass(frozen=True)
class ReportItem:
    """A visible report item with its direct publisher source."""

    title: str
    url: str


def clean_heading(value: str) -> str:
    """Return a rendered item heading as a plain title."""
    value = re.sub(r"\s+⭐️\s+\S+\s*$", "", value.strip())
    value = re.sub(r"^\[(.+?)\]\(.+?\)$", r"\1", value)
    return re.sub(r"\s+", " ", value).strip()


def _mask(value: str) -> str:
    """Replace visible characters with spaces while retaining line positions."""
    return "".join(character if character in "\r\n" else " " for character in value)


def _mask_nonrendering_html_containers(markdown: str) -> str:
    """Mask nested script, style, and template containers without shifting lines."""
    visible: list[str] = []
    open_containers: list[str] = []
    position = 0
    for match in NONRENDERING_HTML_TAG_RE.finditer(markdown):
        tag = match.group("tag").lower()
        is_closing = match.group(0).startswith("</")
        if open_containers:
            visible.append(_mask(markdown[position : match.end()]))
        else:
            visible.append(markdown[position : match.start()])
            visible.append(match.group(0) if is_closing else _mask(match.group(0)))

        if is_closing:
            if open_containers and open_containers[-1] == tag:
                open_containers.pop()
        else:
            open_containers.append(tag)
        position = match.end()

    tail = markdown[position:]
    visible.append(_mask(tail) if open_containers else tail)
    return "".join(visible)


def _mask_html_comments(line: str, in_comment: bool) -> tuple[str, bool]:
    """Mask comments on one line and return whether a multiline comment remains."""
    masked = list(line)
    position = 0
    while position < len(line):
        if in_comment:
            close = line.find("-->", position)
            end = len(line) if close == -1 else close + 3
            for index in range(position, end):
                if masked[index] not in "\r\n":
                    masked[index] = " "
            if close == -1:
                return "".join(masked), True
            in_comment = False
            position = end
            continue

        start = line.find("<!--", position)
        if start == -1:
            break
        close = line.find("-->", start + 4)
        end = len(line) if close == -1 else close + 3
        for index in range(start, end):
            if masked[index] not in "\r\n":
                masked[index] = " "
        if close == -1:
            return "".join(masked), True
        position = end
    return "".join(masked), in_comment


def _fence_opener(line: str) -> tuple[str, int] | None:
    """Return the character and length of a CommonMark fence opener, if present."""
    match = re.match(r"^[ ]{0,3}([`~])\1{2,}[^\r\n]*$", line)
    if not match:
        return None
    fence = match.group(0).lstrip(" ")
    marker = fence[0]
    length = len(fence) - len(fence.lstrip(marker))
    # CommonMark forbids backticks in the info string of a backtick fence.
    if marker == "`" and "`" in fence[length:]:
        return None
    return marker, length


def _is_fence_closer(line: str, marker: str, length: int) -> bool:
    """Return whether a line closes the currently open fenced code block."""
    return bool(
        re.match(
            rf"^[ ]{{0,3}}{re.escape(marker)}{{{length},}}[ \t]*\r?$", line
        )
    )


def visible_markdown(markdown: str) -> str:
    """Return Markdown with comments and fenced blocks masked in place.

    Fences follow the CommonMark indentation and closing-length rules so parser
    decisions share one visibility model with section generation.
    """
    visible: list[str] = []
    in_comment = False
    open_fence: tuple[str, int] | None = None
    for line in markdown.splitlines(keepends=True):
        if open_fence is not None:
            visible.append(_mask(line))
            if _is_fence_closer(line, *open_fence):
                open_fence = None
            continue

        if in_comment:
            masked_line, in_comment = _mask_html_comments(line, in_comment)
            visible.append(masked_line)
            continue

        opener = _fence_opener(line)
        if opener is not None:
            visible.append(_mask(line))
            open_fence = opener
        else:
            masked_line, in_comment = _mask_html_comments(line, in_comment)
            visible.append(masked_line)
    return "".join(visible)


def _visible_generator_markers(markdown: str) -> list[tuple[int, int]]:
    """Return ownership markers that are not concealed by comments or fences."""
    markers: list[tuple[int, int]] = []
    in_comment = False
    open_fence: tuple[str, int] | None = None
    offset = 0
    for line in markdown.splitlines(keepends=True):
        if open_fence is not None:
            if _is_fence_closer(line, *open_fence):
                open_fence = None
        elif in_comment:
            _, in_comment = _mask_html_comments(line, in_comment)
        else:
            opener = _fence_opener(line)
            if opener is not None:
                open_fence = opener
            else:
                marker = GENERATOR_MARKER_RE.match(line)
                if marker is not None:
                    markers.append((offset + marker.start(), offset + marker.end()))
                else:
                    _, in_comment = _mask_html_comments(line, in_comment)
        offset += len(line)
    return markers


def has_hidden_html_tag(markdown: str) -> bool:
    """Return whether rendered Markdown contains an HTML tag that hides content."""
    normalized_markdown = ZERO_WIDTH_RE.sub("", html.unescape(markdown))
    if BLOCK_HTML_CONTAINER_RE.search(normalized_markdown):
        return True
    for tag in RAW_HTML_TAG_RE.findall(normalized_markdown):
        for name, value in HTML_ATTRIBUTE_RE.findall(tag):
            normalized_name = name.lower()
            normalized_value = value.strip("'\"").lower()
            if normalized_name == "hidden":
                return True
            if normalized_name == "inert":
                return True
            if normalized_name == "aria-hidden" and normalized_value == "true":
                return True
            if normalized_name == "style" and (
                DISPLAY_NONE_RE.search(normalized_value)
                or VISIBILITY_HIDDEN_RE.search(normalized_value)
            ):
                return True
    return False


def _validate_source_date(visible: str) -> None:
    """Require one valid visible source date inside the current item."""
    match = SOURCE_DATE_RE.search(visible)
    if match is None:
        raise ValueError("Each report requires a visible source date")
    try:
        date.fromisoformat(match.group(1))
    except ValueError as error:
        raise ValueError("Each report requires a valid source date") from error


def _validate_evidence_blocks(item_body: str) -> None:
    """Require six named evidence blocks with visible content."""
    blocks = list(EVIDENCE_BLOCK_RE.finditer(item_body))
    block_titles = [match.group(1) for match in blocks]
    for index, block in enumerate(blocks):
        content_end = blocks[index + 1].start() if index + 1 < len(blocks) else len(item_body)
        content = block.group(2) + item_body[block.end() : content_end]
        if not _visible_text(content):
            raise ValueError(
                f"Each report item requires non-empty {block.group(1)} evidence"
            )

    for title in REQUIRED_BLOCK_TITLES:
        if title not in block_titles:
            raise ValueError(f"Each report item requires the {title} block")
    if len(block_titles) != len(REQUIRED_BLOCK_TITLES) or set(block_titles) != set(
        REQUIRED_BLOCK_TITLES
    ):
        raise ValueError("Each report item requires exactly six rendered evidence blocks")


def _visible_text(value: str) -> str:
    """Return text that a Markdown renderer can visibly display.

    Entity-only placeholders, zero-width characters, and raw/inert HTML do not
    satisfy evidence content. Text inside ordinary inline HTML remains visible.
    """
    decoded = html.unescape(value)
    decoded = _mask_nonrendering_html_containers(decoded)
    decoded = RAW_HTML_TAG_RE.sub("", decoded)
    decoded = MARKDOWN_LINK_TEXT_RE.sub(r"\1", decoded)
    return ZERO_WIDTH_RE.sub("", decoded).strip()


def parse_report_items(markdown: str) -> list[ReportItem]:
    """Parse and validate the report's visible, sourced items once."""
    visible = visible_markdown(markdown)
    if has_hidden_html_tag(visible):
        raise ValueError("Evidence blocks must not be hidden in raw HTML")
    headings = list(ITEM_HEADING_RE.finditer(visible))
    if len(headings) > 15:
        raise ValueError("A report may contain no more than 15 linked items")
    items: list[ReportItem] = []
    for index, heading in enumerate(headings):
        heading_links = MARKDOWN_LINK_RE.findall(heading.group(1))
        original_url = urlparse(heading_links[0]) if len(heading_links) == 1 else None
        if (
            original_url is None
            or original_url.scheme != "https"
            or not original_url.hostname
            or original_url.hostname.rstrip(".").lower().endswith("news.google.com")
        ):
            raise ValueError("Each report item requires an HTTPS original URL")

        boundary = ITEM_BOUNDARY_RE.search(visible, heading.end())
        item_end = boundary.start() if boundary else len(visible)
        item_body = visible[heading.end() : item_end]
        _validate_source_date(_visible_text(item_body))
        _validate_evidence_blocks(item_body)
        title = clean_heading(heading.group(1))
        if title and title not in EXCLUDED:
            items.append(ReportItem(title=title, url=heading_links[0]))

    return items


def validate_report_contract(markdown: str) -> int:
    """Validate sourced rendered items and return their count."""
    return len(parse_report_items(markdown))


def growth_guidance(report_date: str) -> dict[str, int | str]:
    """Return the repeatable daily exercise for the configured report date."""
    elapsed_days = (date.fromisoformat(report_date) - REPORT_START_DATE).days
    if elapsed_days < 0:
        raise ValueError("Report date is before the growth curriculum start")
    cycle, day_in_cycle = divmod(elapsed_days, len(GROWTH_WEEKS) * len(DAY_VERBS))
    week_index, day_index = divmod(day_in_cycle, len(DAY_VERBS))
    focus, deliverable = GROWTH_WEEKS[week_index]
    source = (
        "https://www.nngroup.com/articles/"
        if week_index < 4
        else "https://designthinking.ideo.com/introduction"
        if week_index < 12
        else "https://www.ycombinator.com/library"
    )
    source_name = "Nielsen Norman Group" if week_index < 4 else "IDEO Design Thinking" if week_index < 12 else "Y Combinator Library"
    verb = DAY_VERBS[day_index]
    return {
        "cycle": cycle + 1,
        "week": week_index + 1,
        "day": day_index + 1,
        "focus": focus,
        "action": f"{verb}与“{focus}”相关的一个案例，并把结论补入本周成果（20–40 分钟）。",
        "deliverable": deliverable,
        "source": source,
        "source_name": source_name,
    }


def _remove_generated_final_sections(markdown: str) -> str:
    """Remove one complete generator-owned final-section tail, if present."""
    visible = visible_markdown(markdown)
    growth_headings = list(GROWTH_HEADING_RE.finditer(visible))
    top_headings = list(TOP_HEADING_RE.finditer(visible))
    markers = _visible_generator_markers(markdown)

    if not growth_headings and not top_headings and not markers:
        return markdown
    if len(growth_headings) != 1 or len(top_headings) != 1 or len(markers) != 1:
        raise ValueError("Report must contain exactly one generated growth and Top 3 section")

    marker_start, marker_end = markers[0]
    growth_heading = growth_headings[0]
    top_heading = top_headings[0]
    if marker_start >= growth_heading.start() or growth_heading.start() >= top_heading.start():
        raise ValueError("Generated final sections have malformed ownership")
    if visible[marker_end : growth_heading.start()].strip():
        raise ValueError("Generated final sections have malformed ownership")

    growth_body = visible[growth_heading.end() : top_heading.start()]
    top_body = visible[top_heading.end() :]
    if (
        re.search(r"^#{1,6}(?!#)\s+", growth_body, re.MULTILINE)
        or re.search(r"^#{1,6}(?!#)\s+", top_body, re.MULTILINE)
        or not growth_body.strip()
        or not top_body.strip()
    ):
        raise ValueError("Generated final sections have malformed ownership")
    return markdown[:marker_start]


def prepare_markdown(markdown: str, report_date: str) -> str:
    """Regenerate the creator-focused final sections from validated report items."""
    if has_hidden_html_tag(visible_markdown(markdown)):
        raise ValueError("Evidence blocks must not be hidden in raw HTML")
    source_markdown = _remove_generated_final_sections(markdown)
    items = parse_report_items(source_markdown)
    guidance = growth_guidance(report_date)
    marker = f"<!-- ai-frontier-radar:{report_date} -->"
    titles = [item.title for item in items][:3]
    if not titles:
        raise ValueError("No eligible briefing item headings were found")

    newline = "\r\n" if "\r\n" in source_markdown else "\n"
    growth_lines = [
        GROWTH_HEADING,
        "",
        f"- 当前阶段：第 {guidance['cycle']} 轮 · 第 {guidance['week']} 周 · 第 {guidance['day']} 天",
        f"- 本周主题：{guidance['focus']}",
        f"- 今日练习（20–40 分钟）：{guidance['action']}",
        f"- 本周作品集成果：{guidance['deliverable']}",
        f"- 学习依据：[{guidance['source_name']}]({guidance['source']})",
        "",
    ]
    top_lines = [TOP_HEADING, ""]
    top_lines.extend(f"{index}. {title}" for index, title in enumerate(titles, start=1))

    def append_sections(content: str, lines: list[str]) -> str:
        if content.endswith(newline * 2):
            separator = ""
        elif content.endswith(newline):
            separator = newline
        else:
            separator = newline * 2
        return content + separator + newline.join(lines) + newline

    return append_sections(source_markdown, [marker] + growth_lines + top_lines)


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
