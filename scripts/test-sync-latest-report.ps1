$ErrorActionPreference = 'Stop'

$syncScript = Join-Path $PSScriptRoot 'sync-to-obsidian.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('horizon-latest-sync-' + [guid]::NewGuid())
$vault = Join-Path $testRoot 'vault'
$fixtures = @{}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function New-BriefingFixture {
    param([Parameter(Mandatory = $true)][string]$Date)

    $path = Join-Path $testRoot "$Date-summary-zh.md"
    [System.IO.File]::WriteAllText($path, @"
---
layout: default
title: "AI 前沿雷达"
date: $Date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: abcdef1234567890
---

# AI 前沿雷达

## 今日优先选题 Top 3
1. $Date 的有效选题
"@, $utf8NoBom)
    $fixtures[$Date] = $path
}

function New-ContentProvider {
    $availableFixtures = $fixtures
    return {
        param($Repository, $Date, $Destination)
        [System.IO.File]::Copy($availableFixtures[$Date], $Destination, $true)
    }.GetNewClosure()
}

function New-TreeResponse {
    param([string[]]$Paths)
    return [pscustomobject]@{
        truncated = $false
        tree = @($Paths | ForEach-Object { [pscustomobject]@{ type = 'blob'; path = $_ } })
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    New-BriefingFixture -Date '2026-08-21'
    New-BriefingFixture -Date '2026-08-22'

    $listingCalls = [System.Collections.Generic.List[string]]::new()
    $todayContentCalls = [System.Collections.Generic.List[string]]::new()
    $sleepCalls = [System.Collections.Generic.List[int]]::new()
    $eveningResponse = New-TreeResponse -Paths @('_posts/2026-08-21-summary-zh.md', '_posts/2026-08-22-summary-zh.md')
    $eveningListingProvider = {
        param($Repository)
        [void]$listingCalls.Add($Repository)
        return $eveningResponse
    }.GetNewClosure()
    $delayedContentProvider = {
        param($Repository, $Date, $Destination)
        [void]$todayContentCalls.Add($Date)
        if ($Date -eq '2026-08-22' -and $todayContentCalls.Count -lt 6) {
            throw 'Today is listed but its raw content is not deployed yet.'
        }
        [System.IO.File]::Copy($fixtures[$Date], $Destination, $true)
    }.GetNewClosure()
    $sleepAction = { param($Seconds) [void]$sleepCalls.Add($Seconds) }.GetNewClosure()

    & $syncScript `
        -VaultPath $vault `
        -Now ([datetime]'2026-08-22T19:15:00') `
        -TodayRetryAttempts 6 `
        -TodayRetryDelaySeconds 120 `
        -RemoteTreeProvider $eveningListingProvider `
        -RemoteContentProvider $delayedContentProvider `
        -SleepAction $sleepAction

    if ($listingCalls.Count -ne 6) { throw "Evening discovery made $($listingCalls.Count) tree requests instead of 6." }
    if ($todayContentCalls.Count -ne 6 -or ($todayContentCalls | Where-Object { $_ -ne '2026-08-22' }).Count -ne 0) {
        throw 'Evening sync did not retry today content exactly 6 times before succeeding.'
    }
    if ($sleepCalls.Count -ne 5 -or ($sleepCalls | Where-Object { $_ -ne 120 }).Count -ne 0) {
        throw 'Evening sync did not apply five injected 120-second waits.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $vault 'AI情报日报\2026-08-22.md'))) {
        throw 'Evening discovery did not prefer today when it became available.'
    }

    $firstReportVault = Join-Path $testRoot 'first-report-vault'
    $firstReportFixture = $fixtures['2026-08-22']
    $emptyTreeResponse = New-TreeResponse -Paths @()
    $emptyTreeProvider = { param($Repository) $emptyTreeResponse }.GetNewClosure()
    $firstReportContentProvider = {
        param($Repository, $Date, $Destination)
        [System.IO.File]::Copy($firstReportFixture, $Destination, $true)
    }.GetNewClosure()
    & $syncScript `
        -VaultPath $firstReportVault `
        -Now ([datetime]'2026-08-22T19:15:00') `
        -RemoteTreeProvider $emptyTreeProvider `
        -RemoteContentProvider $firstReportContentProvider `
        -SleepAction { param($Seconds) throw 'Available today content should not sleep.' }
    if (-not (Test-Path -LiteralPath (Join-Path $firstReportVault 'AI情报日报\2026-08-22.md'))) {
        throw 'Evening sync did not attempt today when no older deployed report existed.'
    }

    $morningVault = Join-Path $testRoot 'morning-vault'
    $morningCalls = [System.Collections.Generic.List[string]]::new()
    $morningResponse = New-TreeResponse -Paths @(
        'README.md',
        '../2026-08-22-summary-zh.md',
        '_posts/2026-08-23-summary-zh.md',
        '_posts/2026-08-20-summary-zh.md',
        '_posts/2026-08-21-summary-zh.md'
    )
    $morningListingProvider = {
        param($Repository)
        [void]$morningCalls.Add($Repository)
        return $morningResponse
    }.GetNewClosure()
    $unexpectedSleep = { param($Seconds) throw 'Morning discovery must not sleep.' }

    & $syncScript `
        -VaultPath $morningVault `
        -Now ([datetime]'2026-08-22T08:00:00') `
        -RemoteTreeProvider $morningListingProvider `
        -RemoteContentProvider (New-ContentProvider) `
        -SleepAction $unexpectedSleep

    if ($morningCalls.Count -ne 1) { throw 'Morning discovery did not use exactly one listing request.' }
    if (-not (Test-Path -LiteralPath (Join-Path $morningVault 'AI情报日报\2026-08-21.md'))) {
        throw 'Morning discovery did not backfill the latest deployed post not later than today.'
    }

    $fallbackVault = Join-Path $testRoot 'fallback-vault'
    $fallbackCalls = [System.Collections.Generic.List[string]]::new()
    $fallbackContentCalls = [System.Collections.Generic.List[string]]::new()
    $fallbackSleeps = [System.Collections.Generic.List[int]]::new()
    $fallbackResponse = New-TreeResponse -Paths @('_posts/2026-08-20-summary-zh.md', '_posts/2026-08-21-summary-zh.md')
    $fallbackListingProvider = {
        param($Repository)
        [void]$fallbackCalls.Add($Repository)
        return $fallbackResponse
    }.GetNewClosure()
    $fallbackContentProvider = {
        param($Repository, $Date, $Destination)
        [void]$fallbackContentCalls.Add($Date)
        if ($Date -eq '2026-08-22') { throw 'Today is still unavailable.' }
        [System.IO.File]::Copy($fixtures[$Date], $Destination, $true)
    }.GetNewClosure()
    $fallbackSleep = { param($Seconds) [void]$fallbackSleeps.Add($Seconds) }.GetNewClosure()

    & $syncScript `
        -VaultPath $fallbackVault `
        -Now ([datetime]'2026-08-22T20:00:00') `
        -TodayRetryAttempts 6 `
        -TodayRetryDelaySeconds 120 `
        -RemoteTreeProvider $fallbackListingProvider `
        -RemoteContentProvider $fallbackContentProvider `
        -SleepAction $fallbackSleep

    if ($fallbackCalls.Count -ne 6 -or $fallbackSleeps.Count -ne 5) {
        throw 'Evening fallback did not exhaust the bounded retry policy.'
    }
    if (($fallbackContentCalls | Where-Object { $_ -eq '2026-08-22' }).Count -ne 6 -or $fallbackContentCalls[-1] -ne '2026-08-21') {
        throw 'Evening fallback did not retry today six times before trying the latest deployed post.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $fallbackVault 'AI情报日报\2026-08-21.md'))) {
        throw 'Evening retry exhaustion did not fall back to the latest deployed post.'
    }

    'PASS'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
