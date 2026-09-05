$ErrorActionPreference = 'Stop'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("horizon-sync-test-" + [guid]::NewGuid())
$source = Join-Path $testRoot 'source.md'
$vault = Join-Path $testRoot 'vault'
$date = '2026-08-22'
$target = Join-Path (Join-Path $vault '01-原始资料') "AI行业热点日报\\$date-AI行业热点日报.md"
$unsafeVault = Join-Path $testRoot 'unsafe-vault'
$outside = Join-Path $testRoot 'outside'
$vaultRootTarget = Join-Path $testRoot 'vault-root-target'
$vaultRootJunction = Join-Path $testRoot 'vault-root-junction'
$vaultAncestorTarget = Join-Path $testRoot 'vault-ancestor-target'
$vaultAncestorJunction = Join-Path $testRoot 'vault-ancestor-junction'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Assert-Fails {
    param([scriptblock]$Action, [string]$Message, [string]$ExpectedError)
    try {
        & $Action
    } catch {
        if ($ExpectedError -and $_.Exception.Message -notmatch $ExpectedError) {
            throw "Expected failure matching '$ExpectedError', got: $($_.Exception.Message)"
        }
        return
    }
    throw $Message
}

function Assert-TargetHash {
    param([string]$ExpectedHash, [string]$Message)
    $actualHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($actualHash -ne $ExpectedHash) { throw $Message }
}

function Get-DestinationHashes {
    $destinationDirectory = Join-Path (Join-Path $vault '01-原始资料') 'AI行业热点日报'
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) { return @{} }
    $hashes = @{}
    Get-ChildItem -LiteralPath $destinationDirectory -File | ForEach-Object {
        $hashes[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    return $hashes
}

function Assert-DestinationHashes {
    param([hashtable]$Expected, [string]$Message)
    $actual = Get-DestinationHashes
    if ($actual.Count -ne $Expected.Count) { throw $Message }
    foreach ($name in $Expected.Keys) {
        if (-not $actual.ContainsKey($name) -or $actual[$name] -ne $Expected[$name]) { throw $Message }
    }
}

New-Item -ItemType Directory -Path $testRoot | Out-Null
Write-Utf8File -Path $source -Content @"
---
layout: default
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 设计师成长雷达

## 今日 AI 核心趋势概览
测试摘要

## 今日优先创作与实践 Top 3
1. 测试选题

## 今日成长行动
1. 完成测试行动
"@

try {
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -Repository 'not-a-remote-repository' -SourceFile $source
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Target was not created' }
    if (-not [System.Linq.Enumerable]::SequenceEqual([System.IO.File]::ReadAllBytes($source), [System.IO.File]::ReadAllBytes($target))) {
        throw 'Sync did not preserve local UTF-8 source bytes'
    }

    $firstHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($firstHash -ne $secondHash) { throw 'Idempotent sync changed identical content' }

    Write-Utf8File -Path $source -Content @"
---
layout: default
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 设计师成长雷达

## 今日 AI 核心趋势概览
更新后的测试摘要

## 今日优先创作与实践 Top 3
1. 更新后的测试选题

## 今日成长行动
1. 完成更新行动
"@
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $changedHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    $revisionTarget = Join-Path (Join-Path $vault '01-原始资料') "AI行业热点日报\$date-AI行业热点日报-rev-$($changedHash.Substring(0, 12)).md"
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $firstHash) { throw 'A changed valid briefing rewrote the immutable original note' }
    if (-not (Test-Path -LiteralPath $revisionTarget -PathType Leaf)) { throw 'A changed valid briefing did not create a revision note' }
    if (-not [System.Linq.Enumerable]::SequenceEqual([System.IO.File]::ReadAllBytes($source), [System.IO.File]::ReadAllBytes($revisionTarget))) {
        throw 'Revision note did not preserve local UTF-8 source bytes'
    }
    $revisionsBeforeRepeat = @(Get-ChildItem -LiteralPath (Split-Path -Parent $revisionTarget) -Filter "$date-AI行业热点日报-rev-*.md" -File).Count
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    if (@(Get-ChildItem -LiteralPath (Split-Path -Parent $revisionTarget) -Filter "$date-AI行业热点日报-rev-*.md" -File).Count -ne $revisionsBeforeRepeat) {
        throw 'Resyncing identical revision content created a duplicate note'
    }

    $collisionContent = (Get-Content -LiteralPath $source -Raw -Encoding utf8).Replace('更新后的测试摘要', '碰撞解决测试摘要')
    Write-Utf8File -Path $source -Content $collisionContent
    $collisionHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    $collisionTarget = Join-Path (Split-Path -Parent $revisionTarget) "$date-AI行业热点日报-rev-$($collisionHash.Substring(0, 12)).md"
    Write-Utf8File -Path $collisionTarget -Content '用户已有的同名前缀修订，绝不可覆盖'
    $collisionTargetHash = (Get-FileHash -LiteralPath $collisionTarget -Algorithm SHA256).Hash
    $extendedRevisionTarget = Join-Path (Split-Path -Parent $revisionTarget) "$date-AI行业热点日报-rev-$($collisionHash.Substring(0, 16)).md"
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $firstHash) { throw 'Revision collision rewrote the immutable original note' }
    if ((Get-FileHash -LiteralPath $collisionTarget -Algorithm SHA256).Hash -ne $collisionTargetHash) { throw 'Revision collision overwrote an existing revision note' }
    if (-not (Test-Path -LiteralPath $extendedRevisionTarget -PathType Leaf)) { throw 'Revision collision did not select a longer safe hash prefix' }
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    if (@(Get-ChildItem -LiteralPath (Split-Path -Parent $revisionTarget) -Filter "$date-AI行业热点日报-rev-*.md" -File).Count -ne 3) {
        throw 'Resyncing collided revision content created a duplicate note'
    }
    $secondHash = $firstHash

    foreach ($hiddenContainer in @(
            '<div style=display:none>',
            '<div style=visibility:hidden>',
            '<div style="display:/* hidden */none">',
            '<script>',
            '<template>',
            '<style>'
        )) {
        $closingContainer = if ($hiddenContainer -match '^<(?<tag>[A-Za-z]+)') { "</$($Matches['tag'])>" } else { '</div>' }
        Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
$hiddenContainer
## 今日优先创作与实践 Top 3
1. 隐藏选题
## 今日成长行动
1. 隐藏行动
$closingContainer
"@
        $destinationHashes = Get-DestinationHashes
        Assert-Fails -Message "Hidden container '$hiddenContainer' was accepted" -ExpectedError 'raw HTML' -Action {
            & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
        }
        Assert-DestinationHashes -Expected $destinationHashes -Message "Hidden container '$hiddenContainer' changed destination notes"
    }

    foreach ($hiddenSection in @('今日优先创作与实践 Top 3', '今日成长行动')) {
        $visibleSection = if ($hiddenSection -eq '今日优先创作与实践 Top 3') { '今日成长行动' } else { '今日优先创作与实践 Top 3' }
        Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
<div title=">" hidden>
## $hiddenSection
1. 不应计入的隐藏章节
</div>
## $visibleSection
1. 可见章节
"@
        $destinationHashes = Get-DestinationHashes
        Assert-Fails -Message "Quoted-angle hidden $hiddenSection was accepted" -ExpectedError 'raw HTML' -Action {
            & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
        }
        Assert-DestinationHashes -Expected $destinationHashes -Message "Quoted-angle hidden $hiddenSection changed destination notes"
    }

    foreach ($hiddenSection in @('今日优先创作与实践 Top 3', '今日成长行动')) {
        $hiddenSource = Join-Path $testRoot ("hidden-" + [guid]::NewGuid() + '.md')
        $hiddenDate = '2026-08-23'
        $hiddenTarget = Join-Path (Join-Path $vault '01-原始资料') "AI行业热点日报\$hiddenDate-AI行业热点日报.md"
        Write-Utf8File -Path $hiddenSource -Content @"
---
layout: default
title: "AI 设计师成长雷达"
date: $hiddenDate
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 设计师成长雷达

<div hidden>
## $hiddenSection
1. 隐藏内容
</div>
"@
        Assert-Fails -ExpectedError 'raw HTML' -Action { & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $hiddenDate -VaultPath $vault -SourceFile $hiddenSource }
        if (Test-Path -LiteralPath $hiddenTarget) { throw "Hidden HTML briefing created destination: $hiddenTarget" }
    }

    Write-Utf8File -Path $source -Content (@'
---
layout: default
title: "AI 设计师成长雷达"
date: {0}
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 设计师成长雷达

## 今日优先创作与实践 Top 3
1. 围栏外的有效选题

## 今日成长行动
1. 围栏外的成长行动

```html
<body>Example code, not a document.</body>
## 今日优先创作与实践 Top 3
```
'@ -f $date)
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

    Write-Utf8File -Path $source -Content (@'
---
title: "AI 设计师成长雷达"
date: {0}
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
## 今日优先创作与实践 Top 3
1. 波浪围栏外的有效选题
## 今日成长行动
1. 波浪围栏外的有效行动
~~~lang`with-backtick
<div title=">" hidden>波浪围栏内的字面量</div>
~~~
'@ -f $date)
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source

    Write-Utf8File -Path $source -Content (@'
---
title: "AI 设计师成长雷达"
date: {0}
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
```bad`info
<div title=">" hidden>
## 今日优先创作与实践 Top 3
1. 不应被无效反引号围栏掩盖的选题
## 今日成长行动
1. 不应被无效反引号围栏掩盖的行动
</div>
```
'@ -f $date)
    $destinationHashes = Get-DestinationHashes
    Assert-Fails -Message 'Invalid backtick fence concealed raw HTML' -ExpectedError 'raw HTML' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-DestinationHashes -Expected $destinationHashes -Message 'Invalid backtick fence changed destination notes'

    Write-Utf8File -Path $source -Content (@'
---
layout: default
title: "AI 设计师成长雷达"
description: "Example <body> text is metadata, not a document"
date: {0}
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 设计师成长雷达

Use `<html>` as an inline-code example.

## 今日优先创作与实践 Top 3
1. 元数据与内联代码是允许的

## 今日成长行动
1. 内联代码外的成长行动
'@ -f $date)
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

    Write-Utf8File -Path $source -Content (@'
---
title: "AI 设计师成长雷达"
date: {0}
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 设计师成长雷达

## 今日优先创作与实践 Top 3
1. 围栏关闭必须严格

## 今日成长行动
1. 严格围栏外的成长行动

```text
<body>仍在围栏内</body>
``` not a closing fence
## 今日优先创作与实践 Top 3
```
'@ -f $date)
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

    Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达

## 今日优先创作与实践 Top 3
1. 缩进代码块外的有效选题

## 今日成长行动
1. 缩进代码块外的成长行动

    <body>四空格代码块内的标签</body>
    ## 今日优先创作与实践 Top 3
"@
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

    Write-Utf8File -Path $source -Content @"
---
layout: default
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
<!-- A proxy can prepend text before an HTML error page. -->
<html><body>GitHub error page</body></html>

## 今日优先创作与实践 Top 3
1. 错误页伪装选题
"@
    Assert-Fails -Message 'HTML error content was accepted' -ExpectedError 'HTML/error page' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Invalid sync damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
## 今日优先创作与实践 Top 3
1. 真实可见的优先选题

<!--
## 今日成长行动
1. 注释中的成长行动不应满足报告契约
-->
"@
    Assert-Fails -Message 'Comment-hidden growth heading was accepted' -ExpectedError '今日成长行动' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Comment-hidden growth validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
没有优先选题章节
"@
    Assert-Fails -Message 'Missing Top 3 heading was accepted' -ExpectedError 'exactly one' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Missing Top 3 validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
## 今日优先创作与实践 Top 3
1. 有优先选题但没有成长行动
"@
    Assert-Fails -Message 'Missing growth heading was accepted' -ExpectedError '今日成长行动' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Missing growth validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
## 今日优先创作与实践 Top 3
1. 有优先选题

## 今日成长行动
1. 第一个成长行动

## 今日成长行动
1. 第二个成长行动
"@
    Assert-Fails -Message 'Duplicate growth headings were accepted' -ExpectedError 'exactly one' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Duplicate growth validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
## 今日优先创作与实践 Top 3
1. 一

## 今日优先创作与实践 Top 3
1. 二
"@
    Assert-Fails -Message 'Duplicate Top 3 headings were accepted' -ExpectedError 'exactly one' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Duplicate Top 3 validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 设计师成长雷达
## 今日优先创作与实践 Top 3
1. 没有中文元数据
"@
    Assert-Fails -Message 'Missing Chinese metadata was accepted' -ExpectedError 'exactly one lang|lang: zh' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Chinese metadata validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "Horizon Summary"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
## 今日优先创作与实践 Top 3
1. 标题错误
"@
    Assert-Fails -Message 'Non-canonical title was accepted' -ExpectedError 'canonical briefing title' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }

    Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22 11:00:00
source_version: abcdef1234567890
---
## 今日优先创作与实践 Top 3
1. 时间戳错误
"@
    Assert-Fails -Message 'Non-UTC generation timestamp was accepted' -ExpectedError 'UTC ISO-8601 generated_at' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }

    Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: ../../private-checkout
---
## 今日优先创作与实践 Top 3
1. 来源版本错误
"@
    Assert-Fails -Message 'Unsafe source version was accepted' -ExpectedError 'safe source_version' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }

    Write-Utf8File -Path $source -Content @"
---
date: $date
date: $date
lang: zh
---
## 今日优先创作与实践 Top 3
1. 重复日期键
"@
    Assert-Fails -Message 'Duplicate date keys were accepted' -ExpectedError 'Duplicate top-level|exactly one date' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Duplicate date validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
date: $date
'date': $date
lang: zh
---
## 今日优先创作与实践 Top 3
1. 带引号的重复日期键
"@
    Assert-Fails -Message 'Quoted duplicate date keys were accepted' -ExpectedError 'canonical bare|Duplicate top-level|exactly one date' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Quoted duplicate date validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
date: $date
"da\u0074e": $date
lang: zh
---
## 今日优先创作与实践 Top 3
1. 转义日期键不能绕过验证
"@
    Assert-Fails -Message 'Escaped date key was accepted' -ExpectedError 'canonical bare' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Escaped key validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
? date
: $date
lang: zh
---
## 今日优先创作与实践 Top 3
1. 显式键语法不能绕过验证
"@
    Assert-Fails -Message 'Explicit key syntax was accepted' -ExpectedError 'canonical bare' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Explicit key validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
date: $date
lang: zh
<<: { extra: value }
---
## 今日优先创作与实践 Top 3
1. 合并键不能绕过验证
"@
    Assert-Fails -Message 'Merge key syntax was accepted' -ExpectedError 'canonical bare' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Merge key validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
date: $date
lang: zh
lang: zh
---
## 今日优先创作与实践 Top 3
1. 重复语言键
"@
    Assert-Fails -Message 'Duplicate language keys were accepted' -ExpectedError 'Duplicate top-level|exactly one lang' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Duplicate language validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
date: $date
lang: zh
"lang": zh
---
## 今日优先创作与实践 Top 3
1. 带引号的重复语言键
"@
    Assert-Fails -Message 'Quoted duplicate language keys were accepted' -ExpectedError 'canonical bare|Duplicate top-level|exactly one lang' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Quoted duplicate language validation damaged the existing note'

    [System.IO.File]::WriteAllBytes($source, [byte[]](0xFF, 0xFE, 0x00))
    Assert-Fails -Message 'Malformed UTF-8 was accepted' -ExpectedError 'valid UTF-8' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'UTF-8 validation damaged the existing note'

    Assert-Fails -Message 'A non-ISO date was accepted' -ExpectedError 'ISO calendar date' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date '2026-08-22..\\escape' -VaultPath $vault -SourceFile $source
    }
    if (Test-Path -LiteralPath (Join-Path $testRoot 'escape.md')) { throw 'Date path traversal wrote outside the vault root' }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Date validation failure damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
## 今日优先创作与实践 Top 3
1. 用于路径安全测试的有效选题

## 今日成长行动
1. 用于路径安全测试的有效行动
"@
    New-Item -ItemType Directory -Path $vaultRootTarget, $vaultAncestorTarget | Out-Null
    New-Item -ItemType Junction -Path $vaultRootJunction -Target $vaultRootTarget | Out-Null
    Assert-Fails -Message 'A VaultPath junction was accepted' -ExpectedError 'VaultPath component is a reparse point' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vaultRootJunction -SourceFile $source
    }
    if (Test-Path -LiteralPath (Join-Path (Join-Path $vaultRootTarget '01-原始资料') "AI行业热点日报\\$date-AI行业热点日报.md")) { throw 'VaultPath junction wrote outside the requested root' }

    New-Item -ItemType Junction -Path $vaultAncestorJunction -Target $vaultAncestorTarget | Out-Null
    Assert-Fails -Message 'A VaultPath ancestor junction was accepted' -ExpectedError 'VaultPath component is a reparse point' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath (Join-Path $vaultAncestorJunction 'nested-vault') -SourceFile $source
    }
    if (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $vaultAncestorTarget 'nested-vault') '01-原始资料') "AI行业热点日报\\$date-AI行业热点日报.md")) { throw 'VaultPath ancestor junction wrote outside the requested root' }

    New-Item -ItemType Directory -Path $unsafeVault, $outside, (Join-Path $unsafeVault '01-原始资料') | Out-Null
    New-Item -ItemType Junction -Path (Join-Path (Join-Path $unsafeVault '01-原始资料') 'AI行业热点日报') -Target $outside | Out-Null
    Assert-Fails -Message 'A destination junction outside the vault was accepted' -ExpectedError 'reparse point' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $unsafeVault -SourceFile $source
    }
    if (Test-Path -LiteralPath (Join-Path $outside "$date-AI行业热点日报.md")) { throw 'Destination junction wrote outside the vault root' }

    Assert-Fails -Message 'Repository owner dot component was accepted' -ExpectedError 'safe owner/repository' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath (Join-Path $testRoot 'remote-validation') -Repository './repo'
    }
    Assert-Fails -Message 'Repository repository dot-dot component was accepted' -ExpectedError 'safe owner/repository' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath (Join-Path $testRoot 'remote-validation') -Repository 'owner/..'
    }

    $lockedTarget = [System.IO.File]::Open($target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        Write-Utf8File -Path $source -Content @"
---
title: "AI 设计师成长雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
## 今日优先创作与实践 Top 3
1. 在锁定目标上的有效更新

## 今日成长行动
1. 在锁定目标上的有效行动
"@
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
        Assert-TargetHash -ExpectedHash $secondHash -Message 'A locked immutable original note was modified'
    } finally {
        $lockedTarget.Dispose()
    }

    $temporaryFiles = @(Get-ChildItem -LiteralPath (Split-Path -Parent $target) -Force -Filter '.ai-frontier-radar-*')
    if ($temporaryFiles.Count -ne 0) { throw 'Temporary or replacement-backup files were not cleaned up' }
    'PASS'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
