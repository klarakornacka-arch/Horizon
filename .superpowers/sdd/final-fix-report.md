# Final fix report

## Scope

Applied every Critical, Important, and requested minor-hardening item from `final-review-findings.md`. No real Vault, clipboard, secret, or external service was accessed or modified.

## RED evidence

- `tests/test_prepare_creator_brief.py`: before the contract changes, the new per-item-date and visible-payload tests failed because validation accepted a global date and HTML-only evidence; the integration fixture also exposed required model setup gaps before being corrected.
- `tests/test_ai_blogger_customization.py`: before configuration repair, the duplicate Google News RSS assertion failed because `config.github.json` still contained the Google News search URL in the generic RSS list.
- `scripts/test-sync-to-obsidian.ps1`: before the sync guard, the hidden-heading fixture failed with a missing-heading count instead of the required raw-HTML rejection.
- Installer collision fixtures were added before the preflight implementation; the old installer behavior was the reviewed `Preserved` path for wrong-type collisions. The final fixture run confirms the repaired fail-closed behavior.

## GREEN evidence

- `\.venv\Scripts\python.exe -m pytest tests/test_prepare_creator_brief.py tests/test_summarizer.py tests/test_ai_blogger_customization.py`: 83 passed.
- `\.venv\Scripts\python.exe -m pytest -q`: all tests pass except the two documented upstream Windows separator failures in `tests/test_setup_wizard.py` (`data\\presets.json` vs `data/presets.json`).
- `scripts/test-install-obsidian-sync-task.ps1`: PASS.
- `scripts/test-install-personal-knowledge-base.ps1`: PASS, including legacy `AI情报日报` hash preservation and file/directory collision no-partial-write fixtures.
- `scripts/test-sync-latest-report.ps1`: PASS.
- `scripts/test-sync-reliability.ps1`: PASS.
- `scripts/test-sync-to-obsidian.ps1`: PASS, including hidden raw-HTML heading fixtures.
- `git diff --check`: no whitespace errors.

## Files changed

- `scripts/prepare_creator_brief.py`: per-item ISO source-date validation; entity/zero-width/raw/inert HTML visible-text policy; CommonMark backtick-info restriction.
- `src/ai/summarizer.py`: canonical `发布日期：YYYY-MM-DD` line in every dated item.
- `data/config.github.json`: removed duplicate Google News search feed from generic RSS.
- `tests/test_prepare_creator_brief.py`, `tests/test_ai_blogger_customization.py`: regression and summarizer/render/prepare integration coverage.
- `scripts/sync-to-obsidian.ps1`: fail-closed hidden/aria-hidden/inert/display-none/visibility-hidden raw HTML guard before heading counts.
- `scripts/test-sync-to-obsidian.ps1`: hidden HTML destination-integrity fixtures.
- `scripts/install-personal-knowledge-base.ps1`: destination type and parent preflight before any creation.
- `scripts/test-install-personal-knowledge-base.ps1`: wrong-type collision and no-partial-write fixtures.

## Concerns

- The only remaining Python failures are the two pre-existing Windows path-separator expectation failures documented in `.superpowers/sdd/progress.md`.
- Secret scan results contain only existing documentation/test placeholders (for example `sk-test` and `xxx`); no real credential value was read or added.
