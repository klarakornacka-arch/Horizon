from pathlib import Path

from scripts.prepare_creator_brief import prepare_markdown, select_latest_chinese_post


SAMPLE = """---
title: Horizon Daily
date: 2026-08-22
---
# 今日 AI 核心趋势概览
今天的重点是模型、工具和开源生态。
## 模型与行业动态
### [模型发布](https://example.com/model)
正文
## AI 工具与工作流
### 新工具上线
正文
## 编程与开源项目
### 开源框架更新
正文
## 商业、创业与变现
### 融资案例
正文
"""


def test_prepare_markdown_adds_exactly_one_top_three_section():
    once = prepare_markdown(SAMPLE, "2026-08-22")
    twice = prepare_markdown(once, "2026-08-22")

    assert once == twice
    assert once.startswith(SAMPLE.rstrip())
    assert once.count("## 今日优先选题 Top 3") == 1
    assert "1. 模型发布" in once
    assert "2. 新工具上线" in once
    assert "3. 开源框架更新" in once


def test_prepare_markdown_keeps_available_items_when_fewer_than_three():
    two_items = SAMPLE.replace("### 开源框架更新\n正文\n", "").replace(
        "### 融资案例\n正文\n", ""
    )

    result = prepare_markdown(two_items, "2026-08-22")

    assert "1. 模型发布" in result
    assert "2. 新工具上线" in result
    assert "3. " not in result
    assert result.startswith(two_items.rstrip())


def test_prepare_markdown_uses_titles_from_rendered_item_headings():
    rendered = SAMPLE.replace(
        "### [模型发布](https://example.com/model)",
        '<a id="item-1"></a>\n### [模型发布](https://example.com/model) ⭐️ 9/10',
    )

    result = prepare_markdown(rendered, "2026-08-22")
    top_three = result.split("## 今日优先选题 Top 3", maxsplit=1)[1]

    assert "1. 模型发布" in result
    assert "模型发布](https://example.com/model)" not in top_three
    assert "⭐️ 9/10" not in top_three


def test_select_latest_chinese_post_prefers_requested_date(tmp_path: Path):
    older = tmp_path / "2026-08-21-horizon-daily-zh.md"
    wanted = tmp_path / "2026-08-22-horizon-daily-zh.md"
    older.write_text("old", encoding="utf-8")
    wanted.write_text("new", encoding="utf-8")

    assert select_latest_chinese_post(tmp_path, "2026-08-22") == wanted
