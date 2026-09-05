# AI Designer Growth Radar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a sourced Chinese AI industry and design report every day, guide a beginner through a repeatable 16-week AI brand-design and entrepreneurship curriculum, and synchronize the report into a dedicated D-drive Obsidian folder.

**Architecture:** GitHub Actions performs collection and DeepSeek analysis in the cloud. Horizon profiles classify and enrich at most 15 sourced items; a deterministic postprocessor adds the dated growth action and creator Top 3; GitHub Pages publishes the result; the existing hardened PowerShell synchronizer validates and writes a canonically named note into the D-drive vault.

**Tech Stack:** Python 3.12, pytest, Horizon processing profiles, DeepSeek OpenAI-compatible API, GitHub Actions, Jekyll/GitHub Pages, PowerShell 7.6, Windows Task Scheduler, Obsidian Markdown

## Global Constraints

- Use provider `deepseek`, model `deepseek-v4-flash`, secret `DEEPSEEK_API_KEY`, and base URL `https://api.deepseek.com`.
- Write reports under `D:\obsidian\人工智能尝试\AI行业热点日报` as `YYYY-MM-DD-AI行业热点日报.md`; never store project-controlled output or caches on C:.
- Keep the cloud schedule at approximately 19:00 Asia/Shanghai and local synchronization at 19:15 plus logon.
- Select at most 15 report items and never pad quotas with weak or unverifiable content.
- Every report item must retain a direct original URL and source date when available, separate facts from interpretation, and include `入选依据`, `审美点评`, `设计思维`, `商业视角`, `创作角度`, and `今日行动`.
- Use exactly one `今日优先创作与实践 Top 3` section.
- The daily action is 20–40 minutes, accumulates toward a weekly portfolio artifact, and follows the approved 16-week path.
- Never print, commit, or write an API key to a local file. The existing OpenAI secret remains unused and is not deleted in this change.

---

### Task 1: Switch the cloud runtime from OpenAI to DeepSeek

**Files:**
- Modify: `tests/test_ai_blogger_customization.py`
- Modify: `data/config.github.json`
- Modify: `.github/workflows/daily-summary.yml`

**Interfaces:**
- Consumes: Horizon's existing `AIProvider.DEEPSEEK` path and default `https://api.deepseek.com` base URL.
- Produces: Runtime configuration for `deepseek-v4-flash` and workflow exposure of `DEEPSEEK_API_KEY` only to the Horizon process.

- [ ] **Step 1: Write failing provider assertions**

Add this test and replace the OpenAI workflow assertions:

```python
def test_github_runtime_uses_deepseek_v4_flash():
    config = json.loads((ROOT / "data" / "config.github.json").read_text(encoding="utf-8"))
    assert config["ai"]["provider"] == "deepseek"
    assert config["ai"]["model"] == "deepseek-v4-flash"
    assert config["ai"]["api_key_env"] == "DEEPSEEK_API_KEY"


def test_daily_workflow_is_enabled_and_minimal():
    text = (ROOT / ".github" / "workflows" / "daily-summary.yml").read_text(encoding="utf-8")
    assert "0 11 * * *" in text
    assert "DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}" in text
    assert "OPENAI_API_KEY" not in text
    assert "prepare_creator_brief.py" in text
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
$env:UV_PYTHON_INSTALL_DIR='D:\obsidian\.tools\uv-python'
$env:UV_CACHE_DIR='D:\obsidian\.tools\uv-cache'
& 'D:\obsidian\.tools\uv\uv.exe' run pytest tests/test_ai_blogger_customization.py -q
```

Expected: failure showing `openai`, `gpt-5.6-luna`, or `OPENAI_API_KEY`.

- [ ] **Step 3: Apply the minimal provider change**

Change only these `ai` values in `data/config.github.json`:

```json
"provider": "deepseek",
"model": "deepseek-v4-flash",
"api_key_env": "DEEPSEEK_API_KEY"
```

Change the workflow environment to:

```yaml
        env:
          DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}
          HORIZON_REPORT_DATE: ${{ env.DATE }}
```

- [ ] **Step 4: Verify GREEN and provider compatibility**

Run:

```powershell
& 'D:\obsidian\.tools\uv\uv.exe' run pytest tests/test_ai_blogger_customization.py tests/test_minimax_client.py -q
```

Expected: all tests pass, including DeepSeek OpenAI-client construction.

- [ ] **Step 5: Commit**

```powershell
& 'D:\obsidian\.tools\git\cmd\git.exe' add tests/test_ai_blogger_customization.py data/config.github.json .github/workflows/daily-summary.yml
& 'D:\obsidian\.tools\git\cmd\git.exe' commit -m 'feat: run AI radar with DeepSeek'
```

### Task 2: Add AI designer profiles, evidence fields, quotas, and verified sources

**Files:**
- Modify: `tests/test_ai_blogger_customization.py`
- Modify: `profiles/ai-blogger/{match.md,analysis.md,enrichment.md,profile.json}`
- Modify: `profiles/ai-blogger-tools/{match.md,analysis.md,enrichment.md,profile.json}`
- Modify: `profiles/ai-blogger-dev/{match.md,analysis.md,enrichment.md,profile.json}`
- Modify: `profiles/ai-blogger-business/{match.md,analysis.md,enrichment.md,profile.json}`
- Create: `profiles/ai-blogger-growth/{match.md,analysis.md,enrichment.md,profile.json}`
- Modify: `data/config.github.json`

**Interfaces:**
- Consumes: Horizon's profile loader, automatic profile classifier, artifact block renderer, RSS scraper, and digest quota allocator.
- Produces: Five Chinese report groups with required evidence/design/business/action blocks and a total quota of 15.

- [ ] **Step 1: Write failing profile, quota, prompt, and source tests**

Assert the five IDs and display names:

```python
expected = {
    "ai-blogger": "AI 行业与模型热点",
    "ai-blogger-tools": "AI 设计工具与工作流",
    "ai-blogger-dev": "设计思维与品牌审美",
    "ai-blogger-business": "自媒体选题与商业机会",
    "ai-blogger-growth": "小白成长与当日行动",
}
required_blocks = {
    "summary", "selection_rationale", "aesthetic_review", "design_thinking",
    "business_lens", "creator_angle", "today_action",
}
```

For every profile, load `profile.json` and assert its localized display name and exact required block IDs. Assert every `enrichment.md` contains `事实与判断必须分开`, `不得编造`, all six Chinese evidence headings, and `20–40 分钟`. Assert digest limits are `4, 3, 3, 3, 2`, sum to 15, and the profile order contains all five IDs. Assert configured RSS URLs include:

```python
{
    "https://www.nngroup.com/feed/rss/",
    "https://www.designboom.com/feed/",
    "https://www.creativeboom.com/feed/",
    "https://www.ycombinator.com/blog/rss",
}
```

- [ ] **Step 2: Verify RED**

Run the customization test file and expect failures for missing growth profile, old group names, old blocks, quotas, and sources.

- [ ] **Step 3: Implement the five profile contracts**

Use these profile IDs, localized names, and matching responsibilities:

```text
ai-blogger          -> AI 行业与模型热点       -> models, policy, research, platform changes
ai-blogger-tools    -> AI 设计工具与工作流     -> creator tools, image/video/design workflows, automation
ai-blogger-dev      -> 设计思维与品牌审美      -> branding, identity, typography, UX, case studies
ai-blogger-business -> 自媒体选题与商业机会     -> creator distribution, services, pricing, clients, startups
ai-blogger-growth   -> 小白成长与当日行动      -> first-party learning resources and beginner practice
```

Each `profile.json` must use this exact block list:

```json
[
  {"id": "summary", "type": "section", "tools": [], "primary": true},
  {"id": "selection_rationale", "type": "section", "tools": []},
  {"id": "aesthetic_review", "type": "section", "tools": []},
  {"id": "design_thinking", "type": "section", "tools": []},
  {"id": "business_lens", "type": "section", "tools": []},
  {"id": "creator_angle", "type": "section", "tools": []},
  {"id": "today_action", "type": "section", "tools": []}
]
```

Each enrichment prompt must demand exact localized titles `入选依据`, `审美点评`, `设计思维`, `商业视角`, `创作角度`, `今日行动`; direct attribution to the supplied URL/date; explicit `不适用：...` when a lens does not apply; fact-versus-interpretation separation; and no invented facts, URLs, prices, dates, metrics, funding, partnerships, or product claims. `今日行动` must take 20–40 minutes and contribute to a visible weekly artifact.

- [ ] **Step 4: Configure quotas and verified feeds**

Set digest groups to:

```json
"models": {"name": "AI 行业与模型热点", "limit": 4, "categories": ["model-industry"]},
"tools": {"name": "AI 设计工具与工作流", "limit": 3, "categories": ["ai-tools", "dev-open-source"]},
"design": {"name": "设计思维与品牌审美", "limit": 3, "categories": ["design-brand", "design-thinking"]},
"business": {"name": "自媒体选题与商业机会", "limit": 3, "categories": ["ai-business", "creator-business"]},
"growth": {"name": "小白成长与当日行动", "limit": 2, "categories": ["designer-growth"]}
```

Add NN/g with category `designer-growth` and forced profile `ai-blogger-growth`; add Designboom and Creative Boom with category `design-brand` and `profile: "auto"`; add YC Blog with category `creator-business` and `profile: "auto"`. Keep existing feeds and the total `max_items` at 15.

- [ ] **Step 5: Verify GREEN and commit**

Run:

```powershell
& 'D:\obsidian\.tools\uv\uv.exe' run pytest tests/test_ai_blogger_customization.py tests/test_profiles.py -q
```

Commit all profile and configuration changes as `feat: tailor radar for AI designer growth`.

### Task 3: Enforce the sourced report contract and add the 16-week daily action

**Files:**
- Modify: `tests/test_prepare_creator_brief.py`
- Modify: `scripts/prepare_creator_brief.py`
- Modify: `.github/workflows/daily-summary.yml`

**Interfaces:**
- Consumes: Rendered Markdown item headings and required localized enrichment blocks from Task 2.
- Produces: A validated report containing no more than 15 linked items, one deterministic growth action, and exactly one `今日优先创作与实践 Top 3` section.

- [ ] **Step 1: Write failing report-contract and growth-path tests**

Extend the sample so each linked `###` item contains all required rendered blocks. Add tests proving:

```python
assert validate_report_contract(valid_markdown) == 4
with pytest.raises(ValueError, match="15"):
    validate_report_contract(markdown_with_16_items)
with pytest.raises(ValueError, match="original URL"):
    validate_report_contract(markdown_with_plain_item_heading)
with pytest.raises(ValueError, match="商业视角"):
    validate_report_contract(markdown_missing_business_lens)
```

Assert `growth_guidance("2026-08-24")` returns week 1/day 1, a 20–40 minute task, its weekly deliverable, and an HTTPS learning source. Assert dates 7, 28, 56, 84, and 111 days later map to the correct approved stages, and day 112 starts cycle 2. Assert repeated preparation is byte-idempotent and produces exactly one `今日成长行动` and one `今日优先创作与实践 Top 3`.

- [ ] **Step 2: Verify RED**

Run `pytest tests/test_prepare_creator_brief.py -q` and expect missing validator/growth interfaces and old Top 3 wording.

- [ ] **Step 3: Implement the deterministic curriculum**

Define 16 week records with these exact focus/deliverable pairs:

```python
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
```

Use seven reusable day verbs—观察、拆解、复刻、改造、讲解、包装、复盘—to turn the current week's focus into one 20–40 minute action. Compute cycle/week/day from fixed start date `2026-08-24`; use modulo 112 so later cycles continue rather than freezing. Map weeks 1–4 to `https://www.nngroup.com/articles/`, weeks 5–12 to `https://designthinking.ideo.com/introduction`, and weeks 13–16 to `https://www.ycombinator.com/library`.

- [ ] **Step 4: Validate and append the final sections**

Implement `validate_report_contract(markdown: str) -> int` to count only linked level-3/4 item headings, require HTTPS original links and all six rendered localized block titles for each item, and reject more than 15 items. `prepare_markdown` must validate before appending:

```markdown
## 今日成长行动

- 当前阶段：第 N 轮 · 第 N 周 · 第 N 天
- 本周主题：...
- 今日练习（20–40 分钟）：...
- 本周作品集成果：...
- 学习依据：[来源名称](https://...)

## 今日优先创作与实践 Top 3

1. ...
```

Update the workflow assertion step to require exactly one new Top 3 heading.

- [ ] **Step 5: Verify GREEN and commit**

Run `pytest tests/test_prepare_creator_brief.py tests/test_ai_blogger_customization.py -q`, then commit as `feat: add sourced designer growth briefing`.

### Task 4: Rename the publication and write canonically named notes to D:

**Files:**
- Modify: `src/orchestrator.py`
- Modify: `docs/_config.yml`
- Modify: `tests/test_publication.py`
- Modify: `tests/test_pages_identity.py`
- Modify: `scripts/sync-to-obsidian.ps1`
- Modify: `scripts/test-sync-to-obsidian.ps1`
- Modify: `scripts/test-sync-latest-report.ps1`
- Modify: `scripts/test-sync-reliability.ps1`

**Interfaces:**
- Consumes: The published `YYYY-MM-DD-summary-zh.md` report from Task 3.
- Produces: Public identity `AI 设计师成长雷达` and local note `AI行业热点日报\YYYY-MM-DD-AI行业热点日报.md` under the user-supplied D-drive vault.

- [ ] **Step 1: Write failing publication and sync assertions**

Change publication tests to expect front matter and H1 `AI 设计师成长雷达`. Change PowerShell fixtures to expect the same title and exactly one new Top 3 heading. Set the canonical test target to:

```powershell
$target = Join-Path $vault "AI行业热点日报\$date-AI行业热点日报.md"
```

Update every junction/path-safety assertion to use `AI行业热点日报` and the suffixed filename.

- [ ] **Step 2: Verify RED**

Run:

```powershell
& 'D:\obsidian\.tools\uv\uv.exe' run pytest tests/test_publication.py tests/test_pages_identity.py -q
& 'D:\obsidian\.tools\pwsh\pwsh.exe' -NoProfile -File scripts/test-sync-to-obsidian.ps1
```

Expected: old title, folder, filename, and Top 3 wording failures.

- [ ] **Step 3: Apply the identity and destination mapping**

Set Jekyll front matter title, report H1, and `docs/_config.yml` title to `AI 设计师成长雷达`. In the synchronizer, use:

```powershell
$destinationInput = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($resolvedVault, 'AI行业热点日报')
)
$destination = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($destinationDirectory, "$dateText-AI行业热点日报.md")
)
```

Require canonical front-matter title `AI 设计师成长雷达` and exactly one `今日优先创作与实践 Top 3` heading. Preserve all existing path-containment, reparse-point, atomic replacement, UTF-8, timeout, retry, and idempotency protections.

- [ ] **Step 4: Verify GREEN**

Run the two Python publication tests and all three synchronization test scripts. Expected: PASS with the new title/path contract.

- [ ] **Step 5: Commit**

Commit as `feat: publish AI designer growth radar to Obsidian`.

### Task 5: Store the secret, review, merge, run, and verify delivery

**Files:**
- No intended tracked implementation changes.
- Verify output: `D:\obsidian\人工智能尝试\AI行业热点日报\2026-08-23-AI行业热点日报.md` or the actual run date.

**Interfaces:**
- Consumes: Tasks 1–4, clipboard-held DeepSeek key, GitHub repository, Pages deployment, and installed Windows task.
- Produces: A merged, scheduled, publicly reachable report and an idempotently synchronized D-drive Obsidian note.

- [ ] **Step 1: Store the clipboard key securely**

The root agent—not a subagent—reads and trims the Windows clipboard, rejects an empty or multiline value, pipes it to `gh secret set DEEPSEEK_API_KEY --repo klarakornacka-arch/Horizon`, clears the clipboard in `finally`, and verifies only the secret name. Output must contain no key material.

- [ ] **Step 2: Run full verification**

Run the full pytest suite and these scripts:

```powershell
scripts/test-sync-to-obsidian.ps1
scripts/test-sync-latest-report.ps1
scripts/test-sync-reliability.ps1
scripts/test-install-obsidian-sync-task.ps1
```

Confirm any failures are limited to the two documented upstream Windows separator tests. Scan tracked files for secret-shaped values, run `git diff --check`, and confirm a clean worktree.

- [ ] **Step 3: Complete review and merge**

Perform per-task reviews, a whole-branch review, push `codex/deepseek-provider`, create pull request `Switch AI designer growth radar to DeepSeek`, and squash-merge only after required review findings are fixed.

- [ ] **Step 4: Dispatch and monitor the workflow**

Dispatch `daily-summary.yml` on `main`. Require success for Horizon, creator/growth postprocessing, report assertion, and Pages deployment. Logs must show at least one selected item and no authentication, quota, model, or missing-contract errors.

- [ ] **Step 5: Enable or verify Pages and public evidence**

If Pages is not configured after `gh-pages` exists, create legacy Pages configuration for branch `gh-pages` and path `/`. Verify `https://klarakornacka-arch.github.io/Horizon/` returns HTTP 200 and the latest report contains source links, all required evidence lenses, one growth action, at most 15 items, and exactly one Top 3 section.

- [ ] **Step 6: Synchronize and verify D-drive idempotency**

Run the synchronization script with vault `D:\obsidian\人工智能尝试`, verify the canonically named note exists under `AI行业热点日报`, then run the sync again. Expected: `Unchanged` and byte-identical content.

- [ ] **Step 7: Verify the scheduled task**

Confirm `AI Frontier Radar - Obsidian Sync` is `Ready`, uses D-drive PowerShell and repository paths, and retains daily 19:15 plus logon triggers. Do not create an obsolete duplicate task.
