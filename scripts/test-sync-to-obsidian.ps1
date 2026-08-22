$ErrorActionPreference = 'Stop'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("horizon-sync-test-" + [guid]::NewGuid())
$source = Join-Path $testRoot 'source.md'
$vault = Join-Path $testRoot 'vault'
$date = '2026-08-22'
$target = Join-Path $vault "AI情报日报\\$date.md"
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

New-Item -ItemType Directory -Path $testRoot | Out-Null
Write-Utf8File -Path $source -Content @"
---
layout: default
title: "AI 前沿雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 前沿雷达

## 今日 AI 核心趋势概览
测试摘要

## 今日优先选题 Top 3
1. 测试选题
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
title: "AI 前沿雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 前沿雷达

## 今日 AI 核心趋势概览
更新后的测试摘要

## 今日优先选题 Top 3
1. 更新后的测试选题
"@
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($firstHash -eq $secondHash) { throw 'A changed valid briefing did not replace the existing note' }

    Write-Utf8File -Path $source -Content (@'
---
layout: default
title: "AI 前沿雷达"
date: {0}
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 前沿雷达

## 今日优先选题 Top 3
1. 围栏外的有效选题

```html
<body>Example code, not a document.</body>
## 今日优先选题 Top 3
```
'@ -f $date)
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

    Write-Utf8File -Path $source -Content (@'
---
layout: default
title: "AI 前沿雷达"
description: "Example <body> text is metadata, not a document"
date: {0}
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 前沿雷达

Use `<html>` as an inline-code example.

## 今日优先选题 Top 3
1. 元数据与内联代码是允许的
'@ -f $date)
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

    Write-Utf8File -Path $source -Content (@'
---
title: "AI 前沿雷达"
date: {0}
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 前沿雷达

## 今日优先选题 Top 3
1. 围栏关闭必须严格

```text
<body>仍在围栏内</body>
``` not a closing fence
## 今日优先选题 Top 3
```
'@ -f $date)
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

    Write-Utf8File -Path $source -Content @"
---
title: "AI 前沿雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 前沿雷达

## 今日优先选题 Top 3
1. 缩进代码块外的有效选题

    <body>四空格代码块内的标签</body>
    ## 今日优先选题 Top 3
"@
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

    Write-Utf8File -Path $source -Content @"
---
layout: default
title: "AI 前沿雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 前沿雷达
<!-- A proxy can prepend text before an HTML error page. -->
<html><body>GitHub error page</body></html>

## 今日优先选题 Top 3
1. 错误页伪装选题
"@
    Assert-Fails -Message 'HTML error content was accepted' -ExpectedError 'HTML/error page' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Invalid sync damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "AI 前沿雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 前沿雷达
没有优先选题章节
"@
    Assert-Fails -Message 'Missing Top 3 heading was accepted' -ExpectedError 'exactly one' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Missing Top 3 validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "AI 前沿雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 前沿雷达
## 今日优先选题 Top 3
1. 一

## 今日优先选题 Top 3
1. 二
"@
    Assert-Fails -Message 'Duplicate Top 3 headings were accepted' -ExpectedError 'exactly one' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Duplicate Top 3 validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
title: "AI 前沿雷达"
date: $date
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
# AI 前沿雷达
## 今日优先选题 Top 3
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
## 今日优先选题 Top 3
1. 标题错误
"@
    Assert-Fails -Message 'Non-canonical title was accepted' -ExpectedError 'canonical briefing title' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }

    Write-Utf8File -Path $source -Content @"
---
title: "AI 前沿雷达"
date: $date
lang: zh
generated_at: 2026-08-22 11:00:00
source_version: abcdef1234567890
---
## 今日优先选题 Top 3
1. 时间戳错误
"@
    Assert-Fails -Message 'Non-UTC generation timestamp was accepted' -ExpectedError 'UTC ISO-8601 generated_at' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }

    Write-Utf8File -Path $source -Content @"
---
title: "AI 前沿雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: ../../private-checkout
---
## 今日优先选题 Top 3
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
## 今日优先选题 Top 3
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
## 今日优先选题 Top 3
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
## 今日优先选题 Top 3
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
## 今日优先选题 Top 3
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
## 今日优先选题 Top 3
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
## 今日优先选题 Top 3
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
## 今日优先选题 Top 3
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
title: "AI 前沿雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
## 今日优先选题 Top 3
1. 用于路径安全测试的有效选题
"@
    New-Item -ItemType Directory -Path $vaultRootTarget, $vaultAncestorTarget | Out-Null
    New-Item -ItemType Junction -Path $vaultRootJunction -Target $vaultRootTarget | Out-Null
    Assert-Fails -Message 'A VaultPath junction was accepted' -ExpectedError 'VaultPath component is a reparse point' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vaultRootJunction -SourceFile $source
    }
    if (Test-Path -LiteralPath (Join-Path $vaultRootTarget "AI情报日报\\$date.md")) { throw 'VaultPath junction wrote outside the requested root' }

    New-Item -ItemType Junction -Path $vaultAncestorJunction -Target $vaultAncestorTarget | Out-Null
    Assert-Fails -Message 'A VaultPath ancestor junction was accepted' -ExpectedError 'VaultPath component is a reparse point' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath (Join-Path $vaultAncestorJunction 'nested-vault') -SourceFile $source
    }
    if (Test-Path -LiteralPath (Join-Path $vaultAncestorTarget "nested-vault\\AI情报日报\\$date.md")) { throw 'VaultPath ancestor junction wrote outside the requested root' }

    New-Item -ItemType Directory -Path $unsafeVault, $outside | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $unsafeVault 'AI情报日报') -Target $outside | Out-Null
    Assert-Fails -Message 'A destination junction outside the vault was accepted' -ExpectedError 'reparse point' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $unsafeVault -SourceFile $source
    }
    if (Test-Path -LiteralPath (Join-Path $outside "$date.md")) { throw 'Destination junction wrote outside the vault root' }

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
title: "AI 前沿雷达"
date: $date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---
## 今日优先选题 Top 3
1. 在锁定目标上的有效更新
"@
        Assert-Fails -Message 'A locked destination was overwritten' -Action {
            & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
        }
        Assert-TargetHash -ExpectedHash $secondHash -Message 'A failed overwrite damaged the existing note'
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
