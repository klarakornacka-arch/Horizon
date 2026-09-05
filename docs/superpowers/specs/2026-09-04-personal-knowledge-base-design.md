# AI Designer Personal Knowledge Base Design

## Goal

Extend `D:\obsidian\人工智能尝试` into a locally stored, self-growing personal
knowledge base for an AI designer and creator. It must turn automated daily
AI reports into source-grounded knowledge, reusable content ideas, and
portfolio/project evidence without overwriting existing notes.

## Information architecture

```text
00-收集箱/                 temporary captured links, notes, and unprocessed material
01-原始资料/AI行业热点日报/ trusted automatic daily-report intake
02-知识库/                 durable concepts, tools, methods, and design/business insight
03-项目与作品集/           active projects, simulated briefs, and case-study evidence
04-内容生产/               topic backlog, scripts, drafts, and published content
05-复盘/                   weekly distillation and monthly strategy review
06-资源与素材/             reusable references and assets
Templates/                 canonical note templates
首页.md                    navigation and operating dashboard
AGENTS.md                  Codex maintenance contract
```

The old `AI情报日报` folder is preserved untouched. The current radar will use
the canonical new path under `01-原始资料/AI行业热点日报` only after its sync
safety checks are deployed.

## Operating loop

1. **连**: Codex operates on the Vault through explicit local file rules.
2. **收**: daily radar notes are saved as immutable, sourced raw inputs.
3. **整**: a weekly distillation converts selected raw items into linked
   knowledge notes and content opportunities; facts retain source URLs and
   dates, while interpretation is marked as such.
4. **创**: content and project notes cite the knowledge notes from which they
   were derived. A monthly review selects a small number of themes to deepen.

## Maintenance rules

- Raw notes are never silently rewritten; derived notes link back to them.
- Every durable knowledge note records source, source date, confidence, and
  the distinction between facts and interpretation.
- Codex may create/update structured notes only according to `AGENTS.md` and
  appends an operation log; it never deletes user notes without explicit user
  authorization.
- Weekly distillation selects no more than five high-value items, prioritizing
  relevance to AI design, brand/aesthetic judgment, commercial opportunity,
  and an actionable creator experiment.
- The system ships templates for raw capture, knowledge notes, content ideas,
  project briefs, and weekly/monthly review.

## Deliverables

The first setup creates only folders, templates, a linked home dashboard,
`AGENTS.md`, and a setup log. It does not migrate or delete existing notes,
does not create external accounts, and does not schedule a new automation.

## Verification

Verify every required directory/file exists under the Vault root; validate
that template links on `首页.md` resolve to real paths; confirm legacy files
remain unchanged; and check the rules forbid destructive changes and require
source provenance.
