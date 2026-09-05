# Report Contract Hardening Design

## Goal

Make daily AI-designer reports publish only when each visible item has a direct
publisher source and complete, meaningful evidence. Always regenerate the
date-specific growth and Top 3 sections from validated visible items.

## Chosen approach

Use a small line-oriented Markdown view rather than layered regular-expression
masking. The parser will:

1. mask HTML comments and CommonMark fenced-code blocks, including up to three
   leading spaces and closing fences at least as long as the opener;
2. reject raw HTML that actually hides rendered content;
3. identify visible H3/H4 item sections and their source/evidence blocks;
4. reject missing source dates and empty evidence content; and
5. derive both Top 3 titles and final-section counts from that same visible
   item model.

Before generation, existing visible growth/Top 3 final sections are removed
only when they match the generator-owned section boundary. The generator then
emits exactly one date-specific growth section and exactly one Top 3 section.
This prevents stale content while retaining the original sourced report.

For Google News, ingestion will follow the article redirect and accept an item
only when the resolved HTTPS URL is outside `news.google.com`; unresolved or
non-direct entries are skipped. Google News attribution remains in metadata.

## Alternatives considered

- Continue adding regex exceptions: rejected because repeated edge cases show
  that visibility and section ownership need one shared representation.
- Stop using Google News entirely: safer but unnecessarily removes useful
  discovery coverage when redirects resolve correctly.
- Use a third-party Markdown parser: rejected for this focused guard because
  it adds dependency/renderer compatibility risk; the line-oriented parser is
  testable and limited to the contract constructs.

## Safety and tests

Tests will first demonstrate code-fence, hidden-content, stale-final-section,
empty-block/source-date, and Google News redirect failures. Tests will cover
valid indented and longer-closing fences plus valid visible HTML attributes.
The PowerShell synchronizer will require exactly one visible growth section as
well as exactly one Top 3 section before copying to the D-drive Vault.

## Non-goals

This change does not alter the selected DeepSeek model, report quotas, Vault
destination, schedule, or secret handling.
