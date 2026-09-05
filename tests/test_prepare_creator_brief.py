from pathlib import Path
from datetime import datetime, timezone
import asyncio
import re

import pytest

from scripts.prepare_creator_brief import (
    growth_guidance,
    main,
    prepare_markdown,
    select_latest_chinese_post,
    validate_report_contract,
    visible_markdown,
)
from src.ai.summarizer import DailySummarizer
from src.models import (
    ClassificationResult,
    ContentAnalysis,
    ContentArtifact,
    ContentBlock,
    ContentItem,
    ProcessingResult,
    SourceType,
)


SAMPLE = """---
title: Horizon Daily
date: 2026-08-22
---
# 今日 AI 核心趋势概览
今天的重点是模型、工具和开源生态。
## 模型与行业动态
### [模型发布](https://example.com/model)
正文
发布日期：2026-08-22
**「入选依据」** 有可靠的一手信息。
**「审美点评」** 层级清晰。
**「设计思维」** 回应用户需求。
**「商业视角」** 有明确价值。
**「创作角度」** 可做案例解读。
**「今日行动」** 用 20–40 分钟整理证据。
## AI 工具与工作流
### [新工具上线](https://example.com/tool)
正文
发布日期：2026-08-22
**「入选依据」** 有可靠的一手信息。
**「审美点评」** 层级清晰。
**「设计思维」** 回应用户需求。
**「商业视角」** 有明确价值。
**「创作角度」** 可做案例解读。
**「今日行动」** 用 20–40 分钟整理证据。
## 编程与开源项目
### [开源框架更新](https://example.com/framework)
正文
发布日期：2026-08-22
**「入选依据」** 有可靠的一手信息。
**「审美点评」** 层级清晰。
**「设计思维」** 回应用户需求。
**「商业视角」** 有明确价值。
**「创作角度」** 可做案例解读。
**「今日行动」** 用 20–40 分钟整理证据。
## 商业、创业与变现
### [融资案例](https://example.com/business)
正文
发布日期：2026-08-22
**「入选依据」** 有可靠的一手信息。
**「审美点评」** 层级清晰。
**「设计思维」** 回应用户需求。
**「商业视角」** 有明确价值。
**「创作角度」** 可做案例解读。
**「今日行动」** 用 20–40 分钟整理证据。
"""


def test_validate_report_contract_counts_valid_linked_items():
    assert validate_report_contract(SAMPLE) == 4


def test_contract_ignores_indented_fence_with_longer_closer() -> None:
    fenced = "   ```md\n### [fake](https://fake.example)\n````\n"

    assert validate_report_contract(SAMPLE + fenced) == 4


def test_contract_rejects_empty_evidence_and_missing_source_date() -> None:
    with pytest.raises(ValueError, match="商业视角"):
        validate_report_contract(
            SAMPLE.replace("**「商业视角」** 有明确价值。", "**「商业视角」**")
        )
    with pytest.raises(ValueError, match="source date"):
        validate_report_contract(SAMPLE.replace("发布日期：2026-08-22", ""))


def test_contract_requires_source_date_inside_every_item() -> None:
    missing = SAMPLE.replace("发布日期：2026-08-22\n", "", 1)
    with pytest.raises(ValueError, match="source date"):
        validate_report_contract(missing)


def test_contract_strips_html_entities_zero_width_and_inert_html_for_evidence() -> None:
    payload = SAMPLE.replace(
        "**「审美点评」** 层级清晰。",
        "**「审美点评」** &nbsp;\u200b<br></br>",
        1,
    )
    with pytest.raises(ValueError, match="审美点评"):
        validate_report_contract(payload)
    for inert in (
        "<template>\u200b</template>", "<script>ignored</script>", "<style>ignored</style>",
        "<template>ignored", "<script>ignored", "<style>ignored",
    ):
        payload = SAMPLE.replace("**「审美点评」** 层级清晰。", f"**「审美点评」** {inert}", 1)
        with pytest.raises(ValueError, match="raw HTML|审美点评"):
            validate_report_contract(payload)


@pytest.mark.parametrize("container", ("template", "script", "style"))
def test_contract_rejects_evidence_heading_inside_nonrendering_html_container(
    container: str,
) -> None:
    markdown = SAMPLE.replace(
        "**「审美点评」** 层级清晰。\n",
        f"<{container}>**「审美点评」** 层级清晰。</{container}>\n",
        1,
    )

    with pytest.raises(ValueError, match="raw HTML|审美点评"):
        validate_report_contract(markdown)


def test_contract_rejects_multiline_evidence_inside_bare_inert_container() -> None:
    markdown = SAMPLE.replace(
        "**「审美点评」** 层级清晰。\n",
        "<div inert>\n**「审美点评」** 层级清晰。\n</div>\n",
        1,
    )

    with pytest.raises(ValueError, match="raw HTML"):
        validate_report_contract(markdown)


def test_contract_allows_inert_word_inside_non_hiding_attribute_value() -> None:
    assert validate_report_contract(SAMPLE + '\n<span class="inert"></span>\n') == 4


def test_contract_rejects_block_container_with_quoted_angle_attribute() -> None:
    markdown = SAMPLE.replace(
        "**「审美点评」** 层级清晰。\n",
        '<div title=">" hidden>\n**「审美点评」** 层级清晰。\n</div>\n',
        1,
    )

    with pytest.raises(ValueError, match="raw HTML"):
        validate_report_contract(markdown)


def test_contract_rejects_block_container_with_css_comment_obfuscation() -> None:
    markdown = SAMPLE.replace(
        "**「审美点评」** 层级清晰。\n",
        '<div style="display:/* hidden */none">\n**「审美点评」** 层级清晰。\n</div>\n',
        1,
    )

    with pytest.raises(ValueError, match="raw HTML"):
        validate_report_contract(markdown)


def test_contract_allows_anchor_and_ignores_block_container_literals_in_comments_and_fences() -> None:
    markdown = (
        SAMPLE
        + '\n<a id="renderer-anchor"></a>\n'
        + '<!-- <div title=">" hidden>not rendered</div> -->\n'
        + '```html\n<div title=">" hidden>not rendered</div>\n```\n'
    )

    assert validate_report_contract(markdown) == 4


def test_contract_masks_nested_template_content_before_evidence_heading_validation() -> None:
    markdown = SAMPLE.replace(
        "**「审美点评」** 层级清晰。\n",
        "<template>\n<template>\nplaceholder\n</template>\n"
        "**「审美点评」** 层级清晰。\n</template>\n",
        1,
    )

    with pytest.raises(ValueError, match="raw HTML|审美点评"):
        validate_report_contract(markdown)


def test_contract_rejects_entity_encoded_hidden_style_and_empty_markdown_link() -> None:
    hidden_style = SAMPLE.replace(
        "**「审美点评」** 层级清晰。\n",
        '<div style="display&#58; none">**「审美点评」** 层级清晰。</div>\n',
        1,
    )
    empty_link = SAMPLE.replace(
        "**「审美点评」** 层级清晰。",
        "**「审美点评」** []()",
        1,
    )

    with pytest.raises(ValueError, match="raw HTML"):
        validate_report_contract(hidden_style)
    with pytest.raises(ValueError, match="审美点评"):
        validate_report_contract(empty_link)


def test_contract_does_not_enter_comment_state_for_fence_info_containing_comment_opener() -> None:
    markdown = (
        SAMPLE
        + "\n```markdown <!-- valid fence info\n"
        + "ignored fenced content\n```\n"
        + "### [missing metadata](https://example.com/missing)\n正文\n"
    )

    with pytest.raises(ValueError, match="source date"):
        validate_report_contract(markdown)


def test_contract_rejects_google_news_hostname_with_trailing_dot() -> None:
    markdown = SAMPLE.replace(
        "https://example.com/model",
        "https://news.google.com./articles/example",
        1,
    )

    with pytest.raises(ValueError, match="HTTPS original URL"):
        validate_report_contract(markdown)


def test_contract_honors_commonmark_backtick_info_restriction() -> None:
    markdown = SAMPLE + "\n```lang`with-backtick\n### [fake](https://fake.example)\n```\n"
    assert "### [fake](https://fake.example)" in visible_markdown(markdown)


def test_summarizer_render_prepare_integration_requires_each_item_date() -> None:
    items = []
    source_dates = ("2026-08-20", "2026-08-21")
    for index, source_date in enumerate(source_dates, start=1):
        blocks = [
            ContentBlock(id=title, title=title, content=f"内容 {index}")
            for title in ("入选依据", "审美点评", "设计思维", "商业视角", "创作角度", "今日行动")
        ]
        items.append(
            ContentItem(
                id=f"rss:{index}", source_type=SourceType.RSS,
                title=f"项目 {index}", url=f"https://example.com/{index}",
                content="正文", author="来源", published_at=datetime.fromisoformat(source_date + "T08:00:00+00:00"),
                processing=ProcessingResult(
                    classification=ClassificationResult(profile="ai-blogger", method="source_override"),
                    analysis=ContentAnalysis(score=8, reason="test", summary="摘要"),
                    artifacts={"zh": ContentArtifact(language="zh", title=f"项目 {index}", blocks=blocks)},
                ),
            )
        )
    summary = asyncio.run(DailySummarizer().generate_summary(items, "2026-08-22", 2, "zh"))
    from src.orchestrator import render_jekyll_post

    rendered = render_jekyll_post(summary, report_date="2026-08-22", language="zh", generated_at=datetime(2026, 8, 22, tzinfo=timezone.utc))
    for index, source_date in enumerate(source_dates, start=1):
        item_section = rendered.split(f"### [项目 {index}]", maxsplit=1)[1].split("### ", maxsplit=1)[0]
        assert f"发布日期：{source_date}" in item_section
    assert prepare_markdown(rendered, "2026-08-24").count("发布日期：") == 2
    with pytest.raises(ValueError, match="source date"):
        prepare_markdown(rendered.replace("发布日期：2026-08-20", "", 1), "2026-08-24")


def test_prepare_markdown_regenerates_stale_final_sections() -> None:
    stale = prepare_markdown(SAMPLE, "2026-08-24").replace("第 1 天", "第 7 天")

    refreshed = prepare_markdown(stale, "2026-08-25")

    assert "第 2 天" in refreshed and "第 7 天" not in refreshed


def test_validate_report_contract_rejects_more_than_fifteen_items():
    item = SAMPLE.split("## AI 工具与工作流", maxsplit=1)[0].split(
        "## 模型与行业动态\n", maxsplit=1
    )[1]
    markdown = "# 报告\n" + "\n".join(
        item.replace("模型发布", f"项目 {number}").replace(
            "https://example.com/model", f"https://example.com/{number}"
        )
        for number in range(16)
    )

    with pytest.raises(ValueError, match="15"):
        validate_report_contract(markdown)


def test_validate_report_contract_rejects_plain_item_heading():
    with pytest.raises(ValueError, match="original URL"):
        validate_report_contract(SAMPLE.replace("[模型发布](https://example.com/model)", "模型发布"))


@pytest.mark.parametrize(
    "heading",
    [
        "[模型发布](http://example.com/model)",
        "[模型发布](https://example.com/model) [旁链](http://example.com/other)",
        "[模型发布](https://example.com/model) [旁链](https://example.com/other)",
    ],
)
def test_validate_report_contract_requires_exactly_one_https_heading_link(heading: str):
    with pytest.raises(ValueError, match="original URL"):
        validate_report_contract(
            SAMPLE.replace("[模型发布](https://example.com/model)", heading)
        )


def test_validate_report_contract_rejects_https_link_without_a_hostname():
    with pytest.raises(ValueError, match="original URL"):
        validate_report_contract(
            SAMPLE.replace("https://example.com/model", "https://")
        )


def test_validate_report_contract_requires_all_localized_blocks():
    with pytest.raises(ValueError, match="商业视角"):
        validate_report_contract(SAMPLE.replace("**「商业视角」** 有明确价值。\n", "", 1))


def test_validate_report_contract_rejects_evidence_heading_hidden_in_html_comment():
    markdown = SAMPLE.replace(
        "**「商业视角」** 有明确价值。\n",
        "<!-- **「商业视角」** 有明确价值。 -->\n",
        1,
    )

    with pytest.raises(ValueError, match="商业视角"):
        validate_report_contract(markdown)


def test_validate_report_contract_rejects_evidence_heading_hidden_in_raw_html():
    markdown = SAMPLE.replace(
        "**「商业视角」** 有明确价值。\n",
        "<div hidden>\n**「商业视角」** 有明确价值。\n</div>\n",
        1,
    )

    with pytest.raises(ValueError, match="raw HTML"):
        validate_report_contract(markdown)


def test_validate_report_contract_rejects_evidence_in_an_unclosed_hidden_container():
    markdown = SAMPLE.replace(
        "**「商业视角」** 有明确价值。\n",
        "<div hidden>\n**「商业视角」** 有明确价值。\n",
        1,
    )

    with pytest.raises(ValueError, match="raw HTML"):
        validate_report_contract(markdown)


def test_validate_report_contract_rejects_hidden_wrapper_opened_before_item_heading():
    with pytest.raises(ValueError, match="raw HTML"):
        validate_report_contract("<div hidden>\n" + SAMPLE)


def test_validate_report_contract_rejects_visibility_hidden_evidence_and_wrapper():
    hidden_evidence = SAMPLE.replace(
        "**「商业视角」** 有明确价值。\n",
        '<div style="visibility: hidden">\n'
        "**「商业视角」** 有明确价值。\n"
        "</div>\n",
        1,
    )

    with pytest.raises(ValueError, match="raw HTML"):
        validate_report_contract(hidden_evidence)
    with pytest.raises(ValueError, match="raw HTML"):
        validate_report_contract('<div style="visibility: hidden">\n' + SAMPLE)


@pytest.mark.parametrize(
    "html",
    [
        "<span aria-hidden=\"false\"></span>",
        "<span data-hidden=\"true\"></span>",
        "<span class=\"hidden helper\"></span>",
        "<span title=\"hidden value\"></span>",
        "<span data-state=hidden></span>",
    ],
)
def test_validate_report_contract_does_not_reject_non_hiding_html_attributes(html: str):
    assert validate_report_contract(SAMPLE + "\n" + html) == 4


def test_validate_report_contract_ignores_hidden_html_literal_in_fenced_code():
    markdown = SAMPLE + "\n```html\n<div hidden>\n**「商业视角」** 示例\n```\n"

    assert validate_report_contract(markdown) == 4


def test_validate_report_contract_rejects_duplicate_or_extra_evidence_blocks():
    duplicated = SAMPLE.replace(
        "**「今日行动」** 用 20–40 分钟整理证据。\n",
        "**「今日行动」** 用 20–40 分钟整理证据。\n"
        "**「今日行动」** 再做一次。\n",
        1,
    )
    extra = SAMPLE.replace(
        "**「今日行动」** 用 20–40 分钟整理证据。\n",
        "**「今日行动」** 用 20–40 分钟整理证据。\n"
        "**「额外区块」** 不应出现。\n",
        1,
    )

    with pytest.raises(ValueError, match="exactly six"):
        validate_report_contract(duplicated)
    with pytest.raises(ValueError, match="exactly six"):
        validate_report_contract(extra)


def test_validate_report_contract_does_not_allow_evidence_blocks_to_cross_h2_boundary():
    first_item_blocks = "\n".join(
        f"**「{title}」** 不能属于上一个项目。"
        for title in ("入选依据", "审美点评", "设计思维", "商业视角", "创作角度", "今日行动")
    )
    markdown = SAMPLE.replace(
        "**「今日行动」** 用 20–40 分钟整理证据。\n## AI 工具与工作流\n",
        "## AI 工具与工作流\n" + first_item_blocks + "\n",
        1,
    )

    with pytest.raises(ValueError, match="今日行动"):
        validate_report_contract(markdown)


def test_growth_guidance_starts_with_first_day_of_first_week():
    guidance = growth_guidance("2026-08-24")

    assert guidance["cycle"] == 1
    assert guidance["week"] == 1
    assert guidance["day"] == 1
    assert "20–40 分钟" in guidance["action"]
    assert guidance["deliverable"] == "一页 AI 信息源可信度清单"
    assert guidance["source"].startswith("https://")


def test_growth_guidance_rejects_dates_before_the_curriculum_start():
    with pytest.raises(ValueError, match="before"):
        growth_guidance("2026-08-23")


@pytest.mark.parametrize(
    ("offset", "week", "focus"),
    [
        (7, 2, "版式层级与网格"),
        (28, 5, "用户访谈与真实需求"),
        (56, 9, "模拟客户发现与项目范围"),
        (84, 13, "案例叙事与作品集"),
        (111, 16, "提案、试点与创业复盘"),
        (112, 1, "可靠信息与事实核查"),
    ],
)
def test_growth_guidance_advances_through_and_repeats_the_curriculum(
    offset: int, week: int, focus: str
):
    from datetime import date, timedelta

    guidance = growth_guidance((date(2026, 8, 24) + timedelta(days=offset)).isoformat())
    assert guidance["week"] == week
    assert guidance["focus"] == focus
    assert guidance["cycle"] == (2 if offset == 112 else 1)


def test_prepare_markdown_adds_exactly_one_growth_and_top_three_section():
    once = prepare_markdown(SAMPLE, "2026-08-24")
    twice = prepare_markdown(once, "2026-08-24")

    assert once == twice
    assert once.startswith(SAMPLE)
    assert once.count("## 今日成长行动") == 1
    assert once.count("## 今日优先创作与实践 Top 3") == 1
    assert "1. 模型发布" in once
    assert "2. 新工具上线" in once
    assert "3. 开源框架更新" in once


def test_prepare_markdown_keeps_available_items_when_fewer_than_three():
    two_items = re.sub(
        r"## 编程与开源项目\n### \[开源框架更新\].*?(?=## 商业、创业与变现)", "", SAMPLE, flags=re.S
    )
    two_items = re.sub(r"## 商业、创业与变现\n.*", "", two_items, flags=re.S)

    result = prepare_markdown(two_items, "2026-08-24")

    assert "1. 模型发布" in result
    assert "2. 新工具上线" in result
    assert "3. " not in result
    assert result.startswith(two_items)


def test_prepare_markdown_uses_titles_from_rendered_item_headings():
    rendered = SAMPLE.replace(
        "### [模型发布](https://example.com/model)",
        '<a id="item-1"></a>\n### [模型发布](https://example.com/model) ⭐️ 9/10',
    )

    result = prepare_markdown(rendered, "2026-08-24")
    top_three = result.split("## 今日优先创作与实践 Top 3", maxsplit=1)[1]

    assert "1. 模型发布" in result
    assert "模型发布](https://example.com/model)" not in top_three
    assert "⭐️ 9/10" not in top_three


def test_prepare_markdown_preserves_trailing_body_content_and_crlf():
    original = (SAMPLE + "尾部空白  \n\n").replace("\n", "\r\n")

    result = prepare_markdown(original, "2026-08-24")

    assert result.startswith(original)
    assert "尾部空白  \r\n\r\n" in result
    assert not any(
        character == "\n" and (index == 0 or result[index - 1] != "\r")
        for index, character in enumerate(result)
    )


def test_prepare_markdown_rejects_unowned_top_three_section():
    existing = SAMPLE + "\n## 今日优先创作与实践 Top 3\n\n1. 已有选题\n"

    with pytest.raises(ValueError, match="exactly one"):
        prepare_markdown(existing, "2026-08-24")


def test_prepare_markdown_rejects_incomplete_generated_final_sections():
    existing = prepare_markdown(SAMPLE, "2026-08-24").split(
        "## 今日优先创作与实践 Top 3", maxsplit=1
    )[0]

    with pytest.raises(ValueError, match="exactly one"):
        prepare_markdown(existing, "2026-08-24")


def test_prepare_markdown_rejects_duplicate_final_sections():
    prepared = prepare_markdown(SAMPLE, "2026-08-24")
    duplicated = prepared + (
        "\n## 今日成长行动\n\n"
        "## 今日优先创作与实践 Top 3\n"
    )

    with pytest.raises(ValueError, match="exactly one"):
        prepare_markdown(duplicated, "2026-08-24")


def test_prepare_markdown_rejects_pre_start_date_even_for_complete_report():
    complete = prepare_markdown(SAMPLE, "2026-08-24")

    with pytest.raises(ValueError, match="before"):
        prepare_markdown(complete, "2026-08-23")


def test_prepare_markdown_ignores_final_headings_inside_html_comments():
    commented = SAMPLE + (
        "\n<!--\n## 今日成长行动\n\n"
        "## 今日优先创作与实践 Top 3\n-->\n"
    )

    result = prepare_markdown(commented, "2026-08-24")
    visible_tail = result.split("-->", maxsplit=1)[1]

    assert "<!-- ai-frontier-radar:2026-08-24 -->" in result
    assert visible_tail.count("## 今日成长行动") == 1
    assert visible_tail.count("## 今日优先创作与实践 Top 3") == 1


@pytest.mark.parametrize(
    "concealed_marker",
    [
        "<!--\n<!-- ai-frontier-radar:2020-01-01 -->\n-->\n",
        "```html\n<!-- ai-frontier-radar:2020-01-01 -->\n```\n",
    ],
)
def test_prepare_markdown_ignores_generator_markers_in_hidden_markdown(
    concealed_marker: str,
):
    result = prepare_markdown(SAMPLE + concealed_marker, "2026-08-24")

    assert "<!-- ai-frontier-radar:2026-08-24 -->" in result
    assert result.count("## 今日成长行动") == 1
    assert result.count("## 今日优先创作与实践 Top 3") == 1


def test_prepare_markdown_rejects_final_sections_inside_hidden_report_wrapper():
    hidden_report = (
        "<div hidden>\n"
        + SAMPLE
        + "\n## 今日成长行动\n\n## 今日优先创作与实践 Top 3\n"
    )

    with pytest.raises(ValueError, match="raw HTML"):
        prepare_markdown(hidden_report, "2026-08-24")


def test_select_latest_chinese_post_uses_exact_renderer_filename(tmp_path: Path):
    older = tmp_path / "2026-08-21-summary-zh.md"
    wanted = tmp_path / "2026-08-22-summary-zh.md"
    unrelated = tmp_path / "2026-08-22-notes.md"
    unrelated_zh = tmp_path / "2026-08-22-z-notes-zh.md"
    older.write_text("old", encoding="utf-8")
    wanted.write_text("new", encoding="utf-8")
    unrelated.write_text("notes", encoding="utf-8")
    unrelated_zh.write_text("notes zh", encoding="utf-8")

    assert select_latest_chinese_post(tmp_path, "2026-08-22") == wanted


def test_main_updates_only_exact_renderer_filename(tmp_path: Path, monkeypatch):
    wanted = tmp_path / "2026-08-24-summary-zh.md"
    unrelated = tmp_path / "2026-08-24-z-notes-zh.md"
    wanted.write_text(SAMPLE, encoding="utf-8")
    unrelated_original = "# 私人笔记\n"
    unrelated.write_text(unrelated_original, encoding="utf-8")
    monkeypatch.setattr(
        "sys.argv",
        ["prepare_creator_brief.py", "--posts-dir", str(tmp_path), "--date", "2026-08-24"],
    )

    assert main() == 0
    assert "## 今日优先创作与实践 Top 3" in wanted.read_text(encoding="utf-8")
    assert unrelated.read_text(encoding="utf-8") == unrelated_original


def test_select_latest_chinese_post_rejects_missing_exact_renderer_filename(
    tmp_path: Path,
):
    (tmp_path / "2026-08-22-notes.md").write_text("notes", encoding="utf-8")
    (tmp_path / "2026-08-22-notes-zh.md").write_text("notes zh", encoding="utf-8")

    with pytest.raises(FileNotFoundError, match="No generated Chinese post"):
        select_latest_chinese_post(tmp_path, "2026-08-22")


def test_select_latest_chinese_post_rejects_ambiguous_near_matches(tmp_path: Path):
    (tmp_path / "2026-08-22-summary-zh-copy.md").write_text("one", encoding="utf-8")
    (tmp_path / "2026-08-22-summary-zh-old.md").write_text("two", encoding="utf-8")

    with pytest.raises(FileExistsError, match="Multiple generated Chinese posts"):
        select_latest_chinese_post(tmp_path, "2026-08-22")


def test_main_preserves_crlf_bytes_when_writing_post(tmp_path: Path, monkeypatch):
    post = tmp_path / "2026-08-24-summary-zh.md"
    original = (SAMPLE + "尾部空白  \n\n").replace("\n", "\r\n").encode("utf-8")
    post.write_bytes(original)
    monkeypatch.setattr(
        "sys.argv",
        ["prepare_creator_brief.py", "--posts-dir", str(tmp_path), "--date", "2026-08-24"],
    )

    assert main() == 0
    result = post.read_bytes()
    assert result.startswith(original)
    assert not any(
        byte == ord("\n") and (index == 0 or result[index - 1] != ord("\r"))
        for index, byte in enumerate(result)
    )


def test_main_reports_missing_post_without_traceback(tmp_path: Path, monkeypatch, capsys):
    monkeypatch.setattr(
        "sys.argv",
        ["prepare_creator_brief.py", "--posts-dir", str(tmp_path), "--date", "2026-08-22"],
    )

    assert main() == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err == "No generated Chinese post for 2026-08-22\n"


def test_main_reports_missing_item_heading_without_traceback(
    tmp_path: Path, monkeypatch, capsys
):
    post = tmp_path / "2026-08-24-summary-zh.md"
    post.write_text("# 空日报\n", encoding="utf-8")
    monkeypatch.setattr(
        "sys.argv",
        ["prepare_creator_brief.py", "--posts-dir", str(tmp_path), "--date", "2026-08-24"],
    )

    assert main() == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err == "No eligible briefing item headings were found\n"
