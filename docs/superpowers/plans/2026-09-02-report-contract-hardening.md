# Report Contract Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish only reports with visible sourced evidence and direct publisher links, while regenerating one date-correct growth/action ending on every run.

**Architecture:** Replace the creator-brief script's coupled regex masking with a line-oriented visible-Markdown representation that feeds both validation and Top-3 extraction. Normalize Google News links during ingestion by following the redirect to a non-Google publisher URL. Reuse the same visible-section invariants in the PowerShell vault guard.

**Tech Stack:** Python 3.11, pytest, httpx, PowerShell 7, GitHub Actions.

## Global Constraints

- Keep `deepseek-v4-flash`, `DEEPSEEK_API_KEY`, the D-drive Vault root, and report quota unchanged.
- Never log, read, or write secret values.
- A report item requires exactly one direct HTTPS publisher link, a source date, and six non-empty visible evidence blocks.
- Google News redirect links must be resolved to non-`news.google.com` HTTPS hosts or skipped.
- The final report contains exactly one generated `今日成长行动` and one generated `今日优先创作与实践 Top 3` section.
- Preserve UTF-8, atomic copy, containment, reparse-point, retry, and task-idempotency protections.

---

### Task 1: Visible Markdown Contract and Regenerated Final Sections

**Files:**
- Modify: `scripts/prepare_creator_brief.py`
- Modify: `tests/test_prepare_creator_brief.py`

**Interfaces:**
- Consumes: report Markdown and ISO `report_date`.
- Produces: `visible_markdown(markdown: str) -> str`, internal `parse_report_items(markdown: str) -> list[ReportItem]`, backward-compatible `validate_report_contract(markdown: str) -> int`, and `prepare_markdown(markdown: str, report_date: str) -> str`.

- [ ] **Step 1: Write failing parser/contract tests**

```python
def test_contract_ignores_indented_fence_with_longer_closer() -> None:
    fenced = "   ```md\n### [fake](https://fake.example)\n````\n"
    assert validate_report_contract(SAMPLE + fenced) == 4

def test_contract_rejects_empty_evidence_and_missing_source_date() -> None:
    with pytest.raises(ValueError, match="商业视角"):
        validate_report_contract(SAMPLE.replace("**「商业视角」** 有明确价值。", "**「商业视角」**"))
    with pytest.raises(ValueError, match="source date"):
        validate_report_contract(SAMPLE.replace("发布日期：2026-08-22", ""))

def test_prepare_markdown_regenerates_stale_final_sections() -> None:
    stale = prepare_markdown(SAMPLE, "2026-08-24").replace("第 1 天", "第 7 天")
    refreshed = prepare_markdown(stale, "2026-08-25")
    assert "第 1 天" in refreshed and "第 7 天" not in refreshed
```

- [ ] **Step 2: Run tests to verify RED**

Run: `uv run pytest tests/test_prepare_creator_brief.py -q`

Expected: new tests fail because fence masking, content/date validation, and stale final-section regeneration are absent.

- [ ] **Step 3: Implement line-oriented visible parser and item model**

```python
def visible_markdown(markdown: str) -> str:
    # Walk lines; mask comments and fenced blocks opened with <=3 spaces.
    # A close fence uses the opener character and has length >= opener.
    ...

@dataclass(frozen=True)
class ReportItem:
    title: str
    url: str

def parse_report_items(markdown: str) -> list[ReportItem]:
    # Build visible text once; validate direct source, date, and six non-empty blocks.
    ...

def validate_report_contract(markdown: str) -> int:
    return len(parse_report_items(markdown))
```

Remove generator-owned visible final sections before deriving titles, then append fresh date-specific sections. Reject duplicate or malformed final-section ownership rather than trusting arbitrary existing content.

- [ ] **Step 4: Run creator-brief tests to verify GREEN**

Run: `uv run pytest tests/test_prepare_creator_brief.py -q`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/prepare_creator_brief.py tests/test_prepare_creator_brief.py
git commit -m "feat: harden visible report contract"
```

### Task 2: Normalize Google News Original URLs

**Files:**
- Modify: `src/scrapers/google_news.py`
- Modify: `tests/test_google_news.py`

**Interfaces:**
- Consumes: Google News entry link and shared `httpx.AsyncClient`.
- Produces: `GoogleNewsScraper._resolve_original_url(link: str) -> str | None`; emitted item URLs are direct external HTTPS URLs.

- [ ] **Step 1: Write failing redirect tests**

```python
def test_google_news_resolves_redirect_to_publisher_url() -> None:
    client = _mock_client_with_redirect("https://news.google.com/rss/articles/x", "https://publisher.example/story")
    item = asyncio.run(GoogleNewsScraper(config, client).fetch(...))[0]
    assert item.url == "https://publisher.example/story"

def test_google_news_skips_unresolved_google_redirect() -> None:
    client = _mock_client_with_redirect("https://news.google.com/rss/articles/x", "https://news.google.com/rss/articles/x")
    assert asyncio.run(GoogleNewsScraper(config, client).fetch(...)) == []
```

- [ ] **Step 2: Run tests to verify RED**

Run: `uv run pytest tests/test_google_news.py -q`

Expected: redirect URL is retained or resolver is missing.

- [ ] **Step 3: Implement async URL normalization**

```python
async def _resolve_original_url(self, link: str) -> Optional[str]:
    response = await self.client.get(link, follow_redirects=True)
    resolved = urlparse(str(response.url))
    if resolved.scheme != "https" or not resolved.hostname or resolved.hostname.endswith("news.google.com"):
        return None
    return str(response.url)
```

Call it before constructing `ContentItem`; handle `httpx.HTTPError` by skipping that entry, and preserve Google News source metadata.

- [ ] **Step 4: Run scraper tests to verify GREEN**

Run: `uv run pytest tests/test_google_news.py -q`

Expected: all Google News tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/scrapers/google_news.py tests/test_google_news.py
git commit -m "fix: require direct Google News publisher links"
```

### Task 3: Require Growth Section Before Vault Sync

**Files:**
- Modify: `scripts/sync-to-obsidian.ps1`
- Modify: `scripts/test-sync-to-obsidian.ps1`
- Modify: `scripts/test-sync-reliability.ps1`

**Interfaces:**
- Consumes: downloaded report visible Markdown.
- Produces: sync succeeds only with exactly one visible growth heading and exactly one visible Top 3 heading.

- [ ] **Step 1: Write failing PowerShell tests**

```powershell
$contentWithoutGrowth = $validContent -replace '(?ms)^## 今日成长行动.*?(?=^## |\z)', ''
Assert-Throws { Invoke-SyncFixture -Content $contentWithoutGrowth } '今日成长行动'

$duplicateGrowth = $validContent + "`n## 今日成长行动`n"
Assert-Throws { Invoke-SyncFixture -Content $duplicateGrowth } 'exactly one'
```

- [ ] **Step 2: Run tests to verify RED**

Run: `pwsh -File scripts/test-sync-to-obsidian.ps1`

Expected: the missing/duplicate-growth tests fail because only Top 3 is currently counted.

- [ ] **Step 3: Implement visible growth heading assertion**

```powershell
$growthHeadings = [regex]::Matches($visibleMarkdown, '(?m)^##\s+今日成长行动[ \t]*\r?$')
if ($growthHeadings.Count -ne 1) {
    throw "Expected exactly one '## 今日成长行动' heading; found $($growthHeadings.Count)."
}
```

Keep this immediately alongside the existing Top 3 assertion after fence/comment removal.

- [ ] **Step 4: Run all sync tests to verify GREEN**

Run: `pwsh -File scripts/test-sync-to-obsidian.ps1`

Run: `pwsh -File scripts/test-sync-latest-report.ps1`

Run: `pwsh -File scripts/test-sync-reliability.ps1`

Expected: every suite prints PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-to-obsidian.ps1 scripts/test-sync-to-obsidian.ps1 scripts/test-sync-reliability.ps1
git commit -m "fix: require one growth action before vault sync"
```

### Task 4: Review and Verify the Hardening

**Files:**
- Verify only: `scripts/prepare_creator_brief.py`, `src/scrapers/google_news.py`, `scripts/sync-to-obsidian.ps1`, associated tests.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: reviewed branch ready for the existing deploy sequence.

- [ ] **Step 1: Run targeted validation**

Run: `uv run pytest tests/test_prepare_creator_brief.py tests/test_google_news.py tests/test_ai_blogger_customization.py -q`

Expected: all selected tests pass.

- [ ] **Step 2: Run full Python suite**

Run: `uv run pytest -q`

Expected: only the two documented Windows separator failures in `tests/test_setup_wizard.py`; no new failures.

- [ ] **Step 3: Inspect safety and diff state**

Run: `git diff --check main...HEAD`

Run: `git status --short`

Expected: diff check has no output; status has no uncommitted tracked changes.

- [ ] **Step 4: Request independent review and record result**

Review the complete hardening range for parser bypasses, direct-link enforcement, and vault safety. Fix all Critical and Important findings before deployment.
