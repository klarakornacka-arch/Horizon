# AI Designer Personal Knowledge Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `D:\obsidian\人工智能尝试` into a safe, source-grounded, self-growing knowledge base for AI design, content creation, commercial thinking, and portfolio work.

**Architecture:** Store the canonical structure and note templates as versioned assets in Horizon, then use an idempotent PowerShell installer to create only missing Vault directories/files. Route the existing daily radar into the Raw layer, while preserving all legacy notes and sync safety checks.

**Tech Stack:** Obsidian Markdown, PowerShell 7, Python/pytest for existing publication checks, Git.

## Global Constraints

- Vault root is exactly `D:\obsidian\人工智能尝试`.
- Never delete, rename, migrate, or overwrite existing user notes.
- Preserve the legacy `AI情报日报` directory untouched.
- Canonical automated report directory is `01-原始资料\AI行业热点日报`.
- Raw notes remain immutable; derived notes retain source URL, source date, confidence, and fact/interpretation separation.
- Weekly distillation selects at most five high-value items.
- Do not create a new external account or recurring automation in this plan.
- Preserve the radar synchronizer's containment, reparse-point, UTF-8, retry, atomic-replace, and idempotence safeguards.

---

### Task 1: Version the Knowledge Base Structure and Templates

**Files:**
- Create: `knowledge-base/首页.md`
- Create: `knowledge-base/AGENTS.md`
- Create: `knowledge-base/Templates/原始资料.md`
- Create: `knowledge-base/Templates/知识卡片.md`
- Create: `knowledge-base/Templates/内容选题.md`
- Create: `knowledge-base/Templates/项目简报.md`
- Create: `knowledge-base/Templates/每周蒸馏.md`
- Create: `knowledge-base/Templates/月度策略.md`
- Create: `knowledge-base/05-复盘/知识库操作日志.md`
- Test: `scripts/test-install-personal-knowledge-base.ps1`

**Interfaces:**
- Consumes: the approved information architecture and AI designer/creator workflow.
- Produces: canonical Markdown assets copied by Task 2 without modification.

- [ ] **Step 1: Write a failing asset-contract test**

Create `scripts/test-install-personal-knowledge-base.ps1` with assertions that all nine canonical assets exist, `首页.md` links to each top-level area, `AGENTS.md` contains `不得删除`, `原始资料只读`, `事实与判断分开`, and `来源日期`, and each derived-note template includes source provenance fields.

```powershell
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Required = @(
    'knowledge-base\首页.md',
    'knowledge-base\AGENTS.md',
    'knowledge-base\Templates\原始资料.md',
    'knowledge-base\Templates\知识卡片.md',
    'knowledge-base\Templates\内容选题.md',
    'knowledge-base\Templates\项目简报.md',
    'knowledge-base\Templates\每周蒸馏.md',
    'knowledge-base\Templates\月度策略.md',
    'knowledge-base\05-复盘\知识库操作日志.md'
)
foreach ($Relative in $Required) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $Relative) -PathType Leaf)) {
        throw "Missing canonical asset: $Relative"
    }
}
```

- [ ] **Step 2: Run the asset test to verify RED**

Run: `pwsh -NoProfile -File scripts/test-install-personal-knowledge-base.ps1`

Expected: FAIL with `Missing canonical asset`.

- [ ] **Step 3: Create the canonical assets**

Use Obsidian links and front matter consistently. The knowledge card contract is:

```markdown
---
type: knowledge
status: evergreen
source_url:
source_date:
confidence: medium
created:
updated:
tags: []
---
# {{title}}
## 可核查事实
## 我的判断
## 对设计与品牌的启发
## 商业与创作机会
## 下一步行动
## 关联笔记
```

`AGENTS.md` must say raw notes are read-only, derived facts require URL/date, interpretations are labeled, edits are incremental, operations append to `05-复盘/知识库操作日志.md`, and deletion/migration needs explicit user approval.

- [ ] **Step 4: Run the asset test to verify GREEN**

Run: `pwsh -NoProfile -File scripts/test-install-personal-knowledge-base.ps1`

Expected: PASS for the asset-contract phase.

- [ ] **Step 5: Commit**

```bash
git add knowledge-base scripts/test-install-personal-knowledge-base.ps1
git commit -m "feat: add AI designer knowledge base assets"
```

### Task 2: Build an Idempotent Vault Installer

**Files:**
- Create: `scripts/install-personal-knowledge-base.ps1`
- Modify: `scripts/test-install-personal-knowledge-base.ps1`

**Interfaces:**
- Consumes: `-VaultRoot <absolute path>` and canonical files in `knowledge-base/`.
- Produces: required directories and missing files; prints `Created`, `Preserved`, and `Ready` statuses without overwriting existing files.

- [ ] **Step 1: Extend the test with a temporary Vault**

```powershell
$TempVault = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $TempVault | Out-Null
Set-Content -LiteralPath (Join-Path $TempVault '首页.md') -Value '用户原有首页' -Encoding utf8
& $Installer -VaultRoot $TempVault
if ((Get-Content -LiteralPath (Join-Path $TempVault '首页.md') -Raw) -notmatch '用户原有首页') {
    throw 'Installer overwrote an existing note.'
}
```

Assert the exact directories `00-收集箱`, `01-原始资料\AI行业热点日报`, `02-知识库\AI工具与工作流`, `02-知识库\设计思维与品牌审美`, `02-知识库\内容增长与商业化`, `02-知识库\方法与模板`, `03-项目与作品集`, `04-内容生产\选题池`, `04-内容生产\文案与脚本`, `04-内容生产\已发布`, `05-复盘\每周蒸馏`, `05-复盘\月度策略`, `06-资源与素材`, and `Templates` exist. Run the installer twice and compare every existing file hash.

- [ ] **Step 2: Run the installer test to verify RED**

Run: `pwsh -NoProfile -File scripts/test-install-personal-knowledge-base.ps1`

Expected: FAIL because the installer does not exist.

- [ ] **Step 3: Implement safe create-only installation**

```powershell
param([Parameter(Mandatory = $true)][string]$VaultRoot)
$resolvedVault = [System.IO.Path]::GetFullPath($VaultRoot)
if (-not [System.IO.Path]::IsPathFullyQualified($resolvedVault)) {
    throw 'VaultRoot must be absolute.'
}
foreach ($relative in $RequiredDirectories) {
    $target = [System.IO.Path]::GetFullPath((Join-Path $resolvedVault $relative))
    if (-not $target.StartsWith($resolvedVault + [System.IO.Path]::DirectorySeparatorChar)) {
        throw "Target escapes Vault root: $relative"
    }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
}
```

For files, copy only when the target does not exist. Reject reparse points on the Vault root and every existing ancestor. Never use `-Force` when copying canonical files.

- [ ] **Step 4: Run installer tests to verify GREEN**

Run: `pwsh -NoProfile -File scripts/test-install-personal-knowledge-base.ps1`

Expected: PASS, including second-run hash equality and preservation of the pre-existing `首页.md`.

- [ ] **Step 5: Commit**

```bash
git add scripts/install-personal-knowledge-base.ps1 scripts/test-install-personal-knowledge-base.ps1
git commit -m "feat: install knowledge base without overwriting notes"
```

### Task 3: Route Daily Reports into the Raw Layer

**Files:**
- Modify: `scripts/sync-to-obsidian.ps1`
- Modify: `scripts/test-sync-to-obsidian.ps1`
- Modify: `scripts/test-sync-latest-report.ps1`
- Modify: `scripts/test-sync-reliability.ps1`

**Interfaces:**
- Consumes: validated daily report and Vault root.
- Produces: `D:\obsidian\人工智能尝试\01-原始资料\AI行业热点日报\YYYY-MM-DD-AI行业热点日报.md`.

- [ ] **Step 1: Write failing destination and comment-visibility tests**

Update expected destination paths to include `01-原始资料`. Add a regression fixture containing a real Top 3 heading and only a comment-hidden growth heading:

```powershell
$commentOnlyGrowth = $validContent -replace '(?ms)^## 今日成长行动.*?(?=^## |\z)', ''
$commentOnlyGrowth += "`n<!--`n## 今日成长行动`n-->`n"
Assert-SyncRejectedWithoutDestinationChange -Content $commentOnlyGrowth
```

- [ ] **Step 2: Run tests to verify RED**

Run: `pwsh -NoProfile -File scripts/test-sync-to-obsidian.ps1`

Expected: FAIL because the current path omits `01-原始资料` and HTML comments still count as headings.

- [ ] **Step 3: Update destination and visible-Markdown sanitization**

Set the destination folder with:

```powershell
$destinationFolder = Join-Path (Join-Path $resolvedVaultRoot '01-原始资料') 'AI行业热点日报'
```

Mask HTML comments before counting both `今日成长行动` and `今日优先创作与实践 Top 3`. Keep the assertions before temporary file creation or final move.

- [ ] **Step 4: Run all sync suites to verify GREEN**

Run: `pwsh -NoProfile -File scripts/test-sync-to-obsidian.ps1`

Run: `pwsh -NoProfile -File scripts/test-sync-latest-report.ps1`

Run: `pwsh -NoProfile -File scripts/test-sync-reliability.ps1`

Expected: every suite prints PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-to-obsidian.ps1 scripts/test-sync-to-obsidian.ps1 scripts/test-sync-latest-report.ps1 scripts/test-sync-reliability.ps1
git commit -m "feat: route daily reports into raw knowledge layer"
```

### Task 4: Install and Verify the Real D-Drive Vault

**Files:**
- Create through installer: directories and missing Markdown files under `D:\obsidian\人工智能尝试`.
- Verify: existing files and legacy `AI情报日报` remain byte-identical.

**Interfaces:**
- Consumes: Tasks 1–3 and real Vault root.
- Produces: ready-to-use personal knowledge base with working navigation and no destructive changes.

- [ ] **Step 1: Snapshot existing file hashes**

Run a read-only PowerShell command that records SHA-256 hashes for all existing files under `D:\obsidian\人工智能尝试`, excluding `.obsidian`, `.claudian`, and `.codex-cli`, into a temporary file outside the Vault.

- [ ] **Step 2: Run the installer**

Run: `pwsh -NoProfile -File scripts/install-personal-knowledge-base.ps1 -VaultRoot 'D:\obsidian\人工智能尝试'`

Expected: directories and missing canonical files are created; existing `首页.md` is reported as Preserved if present.

- [ ] **Step 3: Verify structure and preservation**

Confirm every required path exists, legacy `AI情报日报` still exists, and every pre-install file hash matches the snapshot.

- [ ] **Step 4: Run the installer again**

Run the same installer command a second time.

Expected: all canonical files report Preserved and no file hash changes.

- [ ] **Step 5: Review navigation and rules**

Verify every `首页.md` top-level link resolves to a real path, every template can be opened as UTF-8, and `AGENTS.md` includes the source, append-only log, and no-delete rules.

### Task 5: Final Review and Handoff

**Files:**
- Verify only: all Task 1–4 outputs.

**Interfaces:**
- Consumes: installed Vault and feature branch.
- Produces: reviewed setup ready for the existing radar deployment and later automation phase.

- [ ] **Step 1: Run the knowledge-base and sync tests**

Run: `pwsh -NoProfile -File scripts/test-install-personal-knowledge-base.ps1`

Run all three sync test scripts. Expected: all print PASS.

- [ ] **Step 2: Run tracked-file and secret checks**

Run: `git diff --check main...HEAD`

Scan tracked files for obvious API-key assignment patterns. Expected: no embedded secret values.

- [ ] **Step 3: Request independent whole-change review**

Review the branch for preservation of user files, source provenance, create-only installation, direct report routing, and Vault path containment. Fix all Critical and Important findings.

- [ ] **Step 4: Hand off daily use**

Open `D:\obsidian\人工智能尝试\首页.md` in Codex and explain the daily capture, weekly distillation, content creation, and monthly review loop. A separate approved phase may add recurring weekly/monthly automations after the base system is verified.
