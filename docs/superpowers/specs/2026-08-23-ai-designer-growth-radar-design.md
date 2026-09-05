# AI Designer Growth Radar Design

## Goal

Turn the daily AI information system into a practical development path for a beginner who wants to become an AI brand and content visual designer with strong aesthetics, commercial judgment, and the ability to acquire and independently deliver client projects. Product design and AI automation remain supporting capabilities rather than the primary specialization.

## Audience and Positioning

The report is written for one reader with three connected roles: AI design learner, self-media creator, and future independent founder. It must explain unfamiliar concepts in plain Chinese, distinguish durable signals from short-lived hype, and convert information into a small action that builds professional capability or commercial leverage.

## Storage and Schedule

- Cloud collection runs through GitHub Actions at approximately 19:00 Asia/Shanghai so collection and AI processing do not consume local C-drive project storage.
- Local synchronization runs at approximately 19:15 and at Windows logon.
- The dedicated report directory is `D:\obsidian\人工智能尝试\AI行业热点日报`.
- The canonical local filename is `YYYY-MM-DD-AI行业热点日报.md`.
- Project tools, project-controlled caches, generated reports, and synchronization outputs remain on D:. Windows, Codex, Git, or other operating-system components may still maintain their own small system-managed files on C:.
- Synchronization is idempotent: repeated runs for the same published report must not create duplicates or alter an unchanged note.

## Daily Report Structure

The report contains no more than 15 selected items and uses these sections and target quotas:

1. `AI 行业与模型热点`: 3–4 items.
2. `AI 设计工具与工作流`: 2–3 items.
3. `设计思维与品牌审美`: 2–3 items.
4. `自媒体选题与商业机会`: 2–3 items.
5. `小白成长与当日行动`: 1–2 items.
6. `今日优先创作与实践 Top 3`: exactly one final priority section containing up to three selections supported by report evidence.

The quota allocator may roll unused capacity into another section but must never exceed 15 report items. It must not pad a section with weak or unverifiable material solely to meet a target.

## Item Evidence Contract

Every selected item must contain:

- A concise Chinese title and summary.
- The named source and a directly accessible original URL.
- The original publication date when exposed by the source.
- A short selection rationale explaining why the item matters now.
- `审美点评`: relevant typography, color, composition, visual language, interaction, or brand-consistency observations.
- `设计思维`: the user problem, target audience, constraint, hypothesis, or validation method revealed by the case.
- `商业视角`: the customer value, purchasing reason, monetization path, or delivery implication.
- `创作角度`: a concrete self-media angle suitable for a post, short video, carousel, or case commentary.
- `今日行动`: one beginner-safe exercise that does not pretend the learner has client experience.

Fields that are not applicable must say why briefly instead of inventing analysis. The model must clearly separate facts from interpretation.

## Source Policy

Sources are ordered by evidentiary strength:

1. Official model, product, company, design-studio, standards, or project announcements.
2. Original GitHub repositories, research papers, case studies, and first-party design documentation.
3. Established design, technology, product, and business publications that link to primary material.
4. Community discussion only as a signal of practitioner response, never as sole evidence for a factual claim.

An item without a valid original URL is excluded. Claims must remain traceable to the linked source, and summaries must not add unsupported dates, metrics, partnerships, funding amounts, or product capabilities. Design-learning foundations may include IDEO human-centered design resources, Nielsen Norman Group UX research, original studio case studies, and Y Combinator's founder library; their inclusion does not exempt an item from the URL and date rules.

## Sixteen-Week Growth Path

### Weeks 1–4: Information, Tools, and Visual Foundations

Practice source verification, prompt literacy, layout hierarchy, typography, color, composition, and controlled use of AI image/design tools. Weekly outputs are small visual studies with a written rationale, not disconnected image generations.

### Weeks 5–8: Brand Strategy and Design Thinking

Practice user interviews, problem framing, audience definition, competitive review, moodboards, brand positioning, visual direction, and low-cost prototype validation. Weekly outputs combine a short strategy document with a coherent visual direction.

### Weeks 9–12: Simulated Commercial Delivery

Choose a realistic small-business or creator brief and complete discovery, scope, proposal, brand direction, core identity/content system, revisions, usage guidance, and delivery packaging. The report must label this as a simulated project unless a real client participated.

### Weeks 13–16: Portfolio, Offer, and Market Entry

Turn the strongest work into a case study, define a narrow service offer, estimate scope and price, prepare a client questionnaire and proposal, publish useful content, contact appropriate prospects, and conduct a small paid or carefully bounded pilot when available.

## Daily and Weekly Learning Loop

- Each daily report includes one action sized for approximately 20–40 minutes.
- Actions accumulate toward the current week's visible deliverable instead of producing unrelated exercises.
- The weekly review records what was learned, what evidence changed the designer's judgment, what artifact was produced, and the next commercial or portfolio step.
- A weekly artifact should be suitable for later portfolio inclusion after honest editing and labeling.

## AI Processing

- Use Horizon's native `deepseek` provider with `deepseek-v4-flash`.
- Generate Chinese output while retaining original source names and URLs.
- Favor concise, structured analysis over generic motivational language.
- Never represent model interpretation as direct source wording.
- A failed API call, empty eligible set, missing source URL, or exhausted balance must prevent publication of a misleading complete-looking report.

## Public and Local Delivery

The canonical generated report is deployed to GitHub Pages and then synchronized locally. Public and local versions must contain the same report body and one priority Top 3 section. Local naming may differ from the Jekyll post filename, but synchronization must deterministically map the report date to `YYYY-MM-DD-AI行业热点日报.md`.

## Verification and Acceptance

1. Configuration and workflow tests prove DeepSeek secret wiring and the intended model.
2. Report-format tests cover section names, the 15-item ceiling, evidence fields, fact-versus-interpretation language, and exactly one Top 3 section.
3. Synchronization tests prove the D-drive folder, canonical local filename, path containment, UTF-8 content, and repeat-run idempotency.
4. A real workflow run selects at least one sourced item and successfully deploys GitHub Pages.
5. The public report returns HTTP 200 and exposes source links.
6. The local note exists at the dedicated D-drive path, matches the published report content, and remains byte-identical after a second synchronization.
7. The Windows scheduled task remains Ready with daily and logon triggers.
