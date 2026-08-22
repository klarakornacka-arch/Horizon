from pathlib import Path

import pytest

from scripts.prepare_creator_brief import (
    main,
    prepare_markdown,
    select_latest_chinese_post,
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
    assert once.startswith(SAMPLE)
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
    assert result.startswith(two_items)


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


def test_prepare_markdown_preserves_trailing_body_content_and_crlf():
    original = (SAMPLE + "尾部空白  \n\n").replace("\n", "\r\n")

    result = prepare_markdown(original, "2026-08-22")

    assert result.startswith(original)
    assert "尾部空白  \r\n\r\n" in result
    assert not any(
        character == "\n" and (index == 0 or result[index - 1] != "\r")
        for index, character in enumerate(result)
    )


def test_prepare_markdown_does_not_duplicate_existing_top_three_without_marker():
    existing = SAMPLE + "\n## 今日优先选题 Top 3\n\n1. 已有选题\n"

    assert prepare_markdown(existing, "2026-08-23") == existing


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
    wanted = tmp_path / "2026-08-22-summary-zh.md"
    unrelated = tmp_path / "2026-08-22-z-notes-zh.md"
    wanted.write_text(SAMPLE, encoding="utf-8")
    unrelated_original = "# 私人笔记\n"
    unrelated.write_text(unrelated_original, encoding="utf-8")
    monkeypatch.setattr(
        "sys.argv",
        ["prepare_creator_brief.py", "--posts-dir", str(tmp_path), "--date", "2026-08-22"],
    )

    assert main() == 0
    assert "## 今日优先选题 Top 3" in wanted.read_text(encoding="utf-8")
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
    post = tmp_path / "2026-08-22-summary-zh.md"
    original = (SAMPLE + "尾部空白  \n\n").replace("\n", "\r\n").encode("utf-8")
    post.write_bytes(original)
    monkeypatch.setattr(
        "sys.argv",
        ["prepare_creator_brief.py", "--posts-dir", str(tmp_path), "--date", "2026-08-22"],
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
    post = tmp_path / "2026-08-22-summary-zh.md"
    post.write_text("# 空日报\n", encoding="utf-8")
    monkeypatch.setattr(
        "sys.argv",
        ["prepare_creator_brief.py", "--posts-dir", str(tmp_path), "--date", "2026-08-22"],
    )

    assert main() == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err == "No eligible briefing item headings were found\n"
