$ErrorActionPreference = 'Stop'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("horizon-sync-test-" + [guid]::NewGuid())
$source = Join-Path $testRoot 'source.md'
$vault = Join-Path $testRoot 'vault'
$date = '2026-08-22'
$target = Join-Path $vault "AI情报日报\\$date.md"
$unsafeVault = Join-Path $testRoot 'unsafe-vault'
$outside = Join-Path $testRoot 'outside'
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
title: "Horizon Summary: $date (ZH)"
date: $date
lang: zh
---

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
title: "Horizon Summary: $date (ZH)"
date: $date
lang: zh
---

## 今日 AI 核心趋势概览
更新后的测试摘要

## 今日优先选题 Top 3
1. 更新后的测试选题
"@
    & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    $secondHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($firstHash -eq $secondHash) { throw 'A changed valid briefing did not replace the existing note' }

    Write-Utf8File -Path $source -Content @"
---
layout: default
title: "Horizon Summary: $date (ZH)"
date: $date
lang: zh
---
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
date: $date
lang: zh
---
没有优先选题章节
"@
    Assert-Fails -Message 'Missing Top 3 heading was accepted' -ExpectedError 'exactly one' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Missing Top 3 validation damaged the existing note'

    Write-Utf8File -Path $source -Content @"
---
date: $date
lang: zh
---
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
date: $date
---
## 今日优先选题 Top 3
1. 没有中文元数据
"@
    Assert-Fails -Message 'Missing Chinese metadata was accepted' -ExpectedError 'lang: zh' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $vault -SourceFile $source
    }
    Assert-TargetHash -ExpectedHash $secondHash -Message 'Chinese metadata validation damaged the existing note'

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

    New-Item -ItemType Directory -Path $unsafeVault, $outside | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $unsafeVault 'AI情报日报') -Target $outside | Out-Null
    Assert-Fails -Message 'A destination junction outside the vault was accepted' -ExpectedError 'reparse point' -Action {
        & "$PSScriptRoot\sync-to-obsidian.ps1" -Date $date -VaultPath $unsafeVault -SourceFile $source
    }
    if (Test-Path -LiteralPath (Join-Path $outside "$date.md")) { throw 'Destination junction wrote outside the vault root' }

    $temporaryFiles = @(Get-ChildItem -LiteralPath (Split-Path -Parent $target) -Force -Filter '.ai-frontier-radar-*')
    if ($temporaryFiles.Count -ne 0) { throw 'Temporary or replacement-backup files were not cleaned up' }
    'PASS'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
