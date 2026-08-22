# AI 前沿雷达：Horizon 配置与发布设计

## 目标

为 AI 博主构建一套每日信息系统。系统从中英文一手信息和技术社区采集内容，使用 OpenAI API 去重、评分、筛选和总结，每天北京时间 19:00 左右生成 12–15 条中文 AI 情报，同时发布到 GitHub Pages，并同步到本地 Obsidian Vault。

## 用户与发布位置

- GitHub 用户：`klarakornacka-arch`
- 目标 Fork：`https://github.com/klarakornacka-arch/Horizon`
- 预期 Pages：`https://klarakornacka-arch.github.io/Horizon/`
- 本地 Horizon：`D:\obsidian\Horizon`
- Obsidian Vault：`D:\obsidian\人工智能尝试`
- 日报目录：`D:\obsidian\人工智能尝试\AI情报日报`
- 日报名称：AI 前沿雷达

## 总体架构

采用“云端生成 + 本地同步”。GitHub Actions 是权威生成端，电脑关机不影响日报生成和公开发布。本地 PowerShell 同步脚本只获取已生成的 Markdown，并将其安全写入 Obsidian。

数据流：

1. GitHub Actions 每天 UTC 11:00 触发，对应北京时间 19:00。
2. Horizon 并发抓取已启用的信息源。
3. 系统合并重复链接和同主题内容。
4. OpenAI 模型按 AI 博主专用规则评分和筛选。
5. 系统只对最终候选内容做中文总结和创作角度提炼。
6. 日报写入仓库的发布目录并部署到 GitHub Pages。
7. 本地任务于 19:15 运行，并在 Windows 登录时补运行，把最新日报同步到 Obsidian。

同一天重复执行时覆盖当天目标文件，不创建带序号的副本。

## 信息源

首版只使用不需要额外抓取密钥的来源：

- RSS/Atom：OpenAI News、Google DeepMind、Hugging Face、Simon Willison，以及实施阶段验证可访问性的其他一手 AI 技术来源。
- Hacker News：热门技术新闻与高质量评论。
- Reddit：MachineLearning、LocalLLaMA、ArtificialIntelligence 等社区。
- GitHub Releases：Codex、OpenAI SDK、Transformers、LangChain、AutoGen、LlamaIndex 等项目。
- OSS Insight：过去 24 小时快速增长的 AI 开源项目。

Twitter/X、邮件、Telegram 和 OpenBB 在首版中关闭。这样可避免 Apify Token、邮箱授权、公共频道质量管理和金融数据依赖。

实施时必须逐个验证 RSS URL；不可用的来源不得写入启用配置。单个来源失败不得中断其他来源处理。

## 内容分类与配额

每期最多 15 条，目标范围为 12–15 条：

- 模型与行业动态：最多 4 条。
- AI 工具与工作流：最多 4 条。
- 编程与开源项目：最多 4 条。
- 商业、创业与变现：最多 3 条。

若某栏目没有达到质量阈值，不使用低质量内容补足数量。未使用的栏目额度可由其他高质量栏目补充，但总数不得超过 15 条。

## AI 处理配置

默认模型为 `gpt-5.6-luna`，用于成本敏感的批量筛选与总结。若实际输出在连续三期人工复核中明显缺乏准确性或深度，再评估将总结阶段升级为 `gpt-5.6-terra`；首版不做双模型路由。

专用处理配置 ID 为 `ai-blogger`。评分权重：

- 新闻重要性：35%。
- 对内容创作者的选题价值：30%。
- 新颖性：20%。
- 来源可信度：15%。

入选阈值为 7/10。评分提示必须降低软文、重复发布、无可靠来源传闻和标题党内容的分数。

每条入选内容应输出：

- 中文标题。
- 核心摘要。
- 为什么值得关注。
- 原始来源链接。
- 1–2 个文章或短视频选题角度。

每期还应输出趋势概览和最值得优先制作的 3 个选题。

## 日报结构

Obsidian 日报文件名使用 `YYYY-MM-DD.md`，包含日期、生成时间、标签和来源版本信息。正文顺序如下：

1. 今日 AI 核心趋势概览。
2. 模型与行业动态。
3. AI 工具与工作流。
4. 编程与开源项目。
5. 商业、创业与变现。
6. 今日优先选题 Top 3。

公开站点与 Obsidian 使用同一份核心 Markdown 内容；只允许发布层添加站点导航或展示元数据，不能产生两套不同摘要。

## 密钥与权限

必需密钥只有 OpenAI API 密钥：

- GitHub Actions 使用仓库 Secret `OPENAI_API_KEY`。
- 本地调试使用仓库根目录 `.env` 中的 `OPENAI_API_KEY`。
- `data/config.json` 的 `api_key_env` 只保存变量名 `OPENAI_API_KEY`，不保存密钥值。
- `.env` 必须被 `.gitignore` 排除。

GitHub Actions 优先使用仓库自动提供的 `GITHUB_TOKEN` 完成 Pages 发布，不创建长期个人访问令牌，除非实际工作流权限不足且没有更小权限的替代方案。

任何密钥都不得出现在提交、工作流日志、日报、错误通知或脚本参数中。

## 自动化

GitHub Actions 的 cron 表达式使用 `0 11 * * *`。GitHub 定时任务可能延迟数分钟，因此 19:00 是目标时间而非秒级保证。

本地同步任务包含两个触发器：

- 每天北京时间 19:15。
- 用户登录 Windows 时。

同步脚本应先下载到临时文件，验证 HTTP 成功状态、非空内容、Markdown 标题和目标日期，再原子替换目标笔记。已存在且内容一致时不写入。

## 错误处理

- 单个采集源失败：记录来源和错误，继续其他来源。
- OpenAI 限流或瞬时错误：使用有限次数的指数退避；不得无限重试。
- 有效内容少于 1 条：本次生成失败，不覆盖 Pages 当前版本，也不创建空 Obsidian 笔记。
- 部分栏目为空：允许发布，但趋势概览不得声称该栏目有新动态。
- Pages 发布失败：保留生成产物和 Actions 日志，供手动重试。
- 本地同步失败：保留已有笔记，只写本地日志，不删除任何文件。
- 同一天重复运行：更新同名日报，不创建重复文件。

## 文件结构

```text
D:\obsidian\
├─ Horizon\
│  ├─ data\config.json
│  ├─ profiles\ai-blogger\
│  ├─ .github\workflows\daily-summary.yml
│  ├─ scripts\sync-to-obsidian.ps1
│  ├─ .env.example
│  └─ docs\
└─ 人工智能尝试\
   └─ AI情报日报\
      └─ YYYY-MM-DD.md
```

具体 profile 文件名和 Pages 产物路径以当前 Horizon 主分支的既有结构为准；实施不得为了匹配本文示意而绕过上游项目约定。

## 验证与验收

首次上线先手动触发 GitHub Action，并依次验证：

1. 配置通过 Horizon 自身的加载与校验。
2. 所有启用来源至少有一个能正常抓取，单源失败不会终止流程。
3. OpenAI 调用成功，输出为简体中文且保留来源链接。
4. 日报总数不超过 15，低于 12 时必须是因为没有足够高分内容。
5. 四个栏目与 Top 3 选题结构正确。
6. GitHub Pages 能公开访问当天日报。
7. 本地同步把同一份 Markdown 写入 `AI情报日报\YYYY-MM-DD.md`。
8. 第二次同步不产生副本，且内容相同时不改写文件。
9. 仓库、Git 历史、Actions 日志和生成内容中均不存在 API 密钥。
10. 模拟下载失败时，现有 Obsidian 日报保持不变。

## 首版范围外

- Twitter/X 与 Apify。
- Telegram 频道。
- 邮件订阅和 Webhook 推送。
- OpenBB 金融数据。
- 自动生成完整文章、视频脚本或社交媒体成稿。
- 多模型自动路由。
- 将 Horizon 程序文件放进 Obsidian Vault。

这些功能可在首版稳定运行后按独立需求设计和实施。
