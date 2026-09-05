from datetime import datetime, timezone
from pathlib import Path

import pytest

import src.orchestrator as orchestrator_module


def test_explicit_report_date_wins_at_utc_boundary(monkeypatch) -> None:
    monkeypatch.setenv("HORIZON_REPORT_DATE", "2026-08-23")

    assert orchestrator_module.resolve_report_date(
        now_utc=datetime(2026, 8, 22, 16, 30, tzinfo=timezone.utc)
    ) == "2026-08-23"


def test_report_date_falls_back_to_utc_and_rejects_invalid_override(monkeypatch) -> None:
    monkeypatch.delenv("HORIZON_REPORT_DATE", raising=False)
    now = datetime(2026, 8, 22, 23, 59, tzinfo=timezone.utc)
    assert orchestrator_module.resolve_report_date(now_utc=now) == "2026-08-22"

    monkeypatch.setenv("HORIZON_REPORT_DATE", "2026-8-23")
    with pytest.raises(ValueError, match="HORIZON_REPORT_DATE"):
        orchestrator_module.resolve_report_date(now_utc=now)


def test_published_post_has_canonical_identity_and_metadata() -> None:
    post = orchestrator_module.render_jekyll_post(
        "# Old generated heading\n\nDigest body",
        report_date="2026-08-23",
        language="zh",
        generated_at=datetime(2026, 8, 22, 16, 30, tzinfo=timezone.utc),
        source_version="abcdef1234567890",
    )

    assert 'title: "AI 设计师成长雷达"' in post
    assert "date: 2026-08-23" in post
    assert "generated_at: 2026-08-22T16:30:00Z" in post
    assert 'source_version: "abcdef1234567890"' in post
    assert post.count("# AI 设计师成长雷达") == 1
    assert "Old generated heading" not in post
    assert "Digest body" in post


def test_source_version_is_quoted_even_when_sha_looks_numeric() -> None:
    post = orchestrator_module.render_jekyll_post(
        "Digest body",
        report_date="2026-08-23",
        language="zh",
        generated_at=datetime(2026, 8, 22, 16, 30, tzinfo=timezone.utc),
        source_version="1234567",
    )
    unsafe = orchestrator_module.render_jekyll_post(
        "Digest body",
        report_date="2026-08-23",
        language="zh",
        generated_at=datetime(2026, 8, 22, 16, 30, tzinfo=timezone.utc),
        source_version='abcdef1"\nunsafe: true',
    )

    assert 'source_version: "1234567"' in post
    assert 'source_version: "local"' in unsafe
    assert "unsafe: true" not in unsafe


def test_workflow_passes_shanghai_date_to_horizon() -> None:
    workflow = (
        Path(__file__).resolve().parents[1] / ".github" / "workflows" / "daily-summary.yml"
    ).read_text(encoding="utf-8")

    assert "HORIZON_REPORT_DATE: ${{ env.DATE }}" in workflow
