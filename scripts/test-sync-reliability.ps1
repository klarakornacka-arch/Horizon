$ErrorActionPreference = 'Stop'

$syncScript = Join-Path $PSScriptRoot 'sync-to-obsidian.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('horizon-sync-reliability-' + [guid]::NewGuid())
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$fixtures = @{}
$syncContent = [System.IO.File]::ReadAllText($syncScript)
foreach ($requiredTimeoutPrimitive in @(
    '[System.Net.Http.HttpClient]::new',
    '[System.Threading.CancellationTokenSource]::new',
    'ResponseHeadersRead',
    'ReadAsync'
)) {
    if (-not $syncContent.Contains($requiredTimeoutPrimitive)) {
        throw "Bounded HTTP implementation is missing: $requiredTimeoutPrimitive"
    }
}
if ($syncContent -match '\bInvoke-(?:WebRequest|RestMethod)\b') {
    throw 'Sync must not use request APIs whose timeout can degrade to a read-gap timeout.'
}

function Assert-Fails {
    param([scriptblock]$Action, [string]$ExpectedError)
    try { & $Action } catch {
        if ($_.Exception.Message -notmatch $ExpectedError) {
            throw "Expected '$ExpectedError', got: $($_.Exception.Message)"
        }
        return
    }
    throw "Expected failure matching '$ExpectedError'."
}

function New-TreeResponse {
    param([string[]]$Paths, [bool]$Truncated = $false)
    return [pscustomobject]@{
        truncated = $Truncated
        tree = @($Paths | ForEach-Object { [pscustomobject]@{ type = 'blob'; path = $_ } })
    }
}

function New-BriefingFixture {
    param([string]$Date)
    $path = Join-Path $testRoot "$Date.md"
    [System.IO.File]::WriteAllText($path, @"
---
title: "AI 设计师成长雷达"
date: $Date
lang: zh
generated_at: 2026-08-22T11:00:00Z
source_version: "1234567"
---

# AI 设计师成长雷达

## 今日优先创作与实践 Top 3
1. $Date

## 今日成长行动
1. $Date
"@, $utf8NoBom)
    $fixtures[$Date] = $path
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    foreach ($date in @('2026-08-18', '2026-08-19', '2026-08-20', '2026-08-21', '2026-08-22')) {
        New-BriefingFixture -Date $date
    }

    # A transient discovery failure must not consume the entire evening run.
    $recoverTreeCalls = [System.Collections.Generic.List[int]]::new()
    $recoverContentCalls = [System.Collections.Generic.List[string]]::new()
    $recoverTimeouts = [System.Collections.Generic.List[int]]::new()
    $recoverSleeps = [System.Collections.Generic.List[int]]::new()
    $recoverResponse = New-TreeResponse -Paths @('_posts/2026-08-21-summary-zh.md', '_posts/2026-08-22-summary-zh.md')
    $recoverTree = {
        param($Repository, $TimeoutSeconds)
        [void]$recoverTreeCalls.Add($recoverTreeCalls.Count + 1)
        [void]$recoverTimeouts.Add($TimeoutSeconds)
        if ($recoverTreeCalls.Count -eq 1) { throw 'transient tree failure' }
        $recoverResponse
    }.GetNewClosure()
    $recoverContent = {
        param($Repository, $Date, $Destination, $TimeoutSeconds)
        [void]$recoverContentCalls.Add($Date)
        [void]$recoverTimeouts.Add($TimeoutSeconds)
        if ($recoverContentCalls.Count -eq 1) { throw 'today not ready' }
        [System.IO.File]::Copy($fixtures[$Date], $Destination, $true)
    }.GetNewClosure()
    $recoverSleep = { param($Seconds) [void]$recoverSleeps.Add($Seconds) }.GetNewClosure()
    & $syncScript -VaultPath (Join-Path $testRoot 'recover') -Now ([datetime]'2026-08-22T19:15:00') `
        -RemoteTreeProvider $recoverTree -RemoteContentProvider $recoverContent -SleepAction $recoverSleep
    if ($recoverTreeCalls.Count -ne 2 -or $recoverContentCalls.Count -ne 2 -or $recoverSleeps.Count -ne 1) {
        throw 'Evening retry did not repeat discovery and today fetch after a transient listing failure.'
    }
    if (($recoverTimeouts | Where-Object { $_ -ne 15 }).Count -ne 0) {
        throw 'Configured per-request timeout was not passed to every injected provider.'
    }

    # Keep the last successful fallback list when later discovery calls fail.
    $retainedTreeCalls = [System.Collections.Generic.List[int]]::new()
    $retainedContentCalls = [System.Collections.Generic.List[string]]::new()
    $retainedSleeps = [System.Collections.Generic.List[int]]::new()
    $retainedResponse = New-TreeResponse -Paths @('_posts/2026-08-21-summary-zh.md')
    $retainedTree = {
        param($Repository, $TimeoutSeconds)
        [void]$retainedTreeCalls.Add($retainedTreeCalls.Count + 1)
        if ($retainedTreeCalls.Count -gt 1) { throw 'later tree outage' }
        $retainedResponse
    }.GetNewClosure()
    $retainedContent = {
        param($Repository, $Date, $Destination, $TimeoutSeconds)
        [void]$retainedContentCalls.Add($Date)
        if ($Date -eq '2026-08-22') { throw 'today unavailable' }
        [System.IO.File]::Copy($fixtures[$Date], $Destination, $true)
    }.GetNewClosure()
    $retainedSleep = { param($Seconds) [void]$retainedSleeps.Add($Seconds) }.GetNewClosure()
    & $syncScript -VaultPath (Join-Path $testRoot 'retained') -Now ([datetime]'2026-08-22T20:00:00') `
        -RemoteTreeProvider $retainedTree -RemoteContentProvider $retainedContent -SleepAction $retainedSleep
    if ($retainedTreeCalls.Count -ne 6 -or $retainedSleeps.Count -ne 5 -or $retainedContentCalls[-1] -ne '2026-08-21') {
        throw 'Latest successful fallback list was not retained across later tree failures.'
    }

    $largeTreePaths = @(1..1001 | ForEach-Object { "misc/file-$_.txt" }) + @('_posts/2026-08-21-summary-zh.md')
    $largeTreeResponse = New-TreeResponse -Paths $largeTreePaths
    $largeTree = { param($Repository, $TimeoutSeconds) $largeTreeResponse }.GetNewClosure()
    $largeTreeContentCalls = [System.Collections.Generic.List[string]]::new()
    $largeTreeContent = {
        param($Repository, $Date, $Destination, $TimeoutSeconds)
        [void]$largeTreeContentCalls.Add($Date)
        [System.IO.File]::Copy($fixtures[$Date], $Destination, $true)
    }.GetNewClosure()
    $largeTreeVault = Join-Path $testRoot 'large-tree'
    & $syncScript -VaultPath $largeTreeVault -Now ([datetime]'2026-08-22T08:00:00') `
        -RemoteTreeProvider $largeTree -RemoteContentProvider $largeTreeContent
    if (($largeTreeContentCalls -join ',') -cne '2026-08-21' -or -not (Test-Path -LiteralPath (Join-Path (Join-Path $largeTreeVault '01-原始资料') 'AI行业热点日报\2026-08-21-AI行业热点日报.md'))) {
        throw 'A complete bounded tree with more than 1000 unrelated entries did not discover its valid report.'
    }
    $truncatedResponse = New-TreeResponse -Paths @('_posts/2026-08-21-summary-zh.md') -Truncated $true
    $truncatedTree = { param($Repository, $TimeoutSeconds) $truncatedResponse }.GetNewClosure()
    Assert-Fails -ExpectedError 'truncated' -Action {
        & $syncScript -VaultPath (Join-Path $testRoot 'truncated') -Now ([datetime]'2026-08-22T08:00:00') `
            -RemoteTreeProvider $truncatedTree `
            -RemoteContentProvider { throw 'content must not be requested' }
    }
    Assert-Fails -ExpectedError 'malformed' -Action {
        & $syncScript -VaultPath (Join-Path $testRoot 'malformed') -Now ([datetime]'2026-08-22T08:00:00') `
            -RemoteTreeProvider { param($Repository, $TimeoutSeconds) [pscustomobject]@{ tree = @() } } `
            -RemoteContentProvider { throw 'content must not be requested' }
    }

    $capCalls = [System.Collections.Generic.List[string]]::new()
    $capContent = { param($Repository, $Date) [void]$capCalls.Add($Date); throw 'invalid fallback' }.GetNewClosure()
    $capResponse = New-TreeResponse -Paths @(
        '_posts/2026-08-21-summary-zh.md', '_posts/2026-08-20-summary-zh.md',
        '_posts/2026-08-19-summary-zh.md', '_posts/2026-08-18-summary-zh.md'
    )
    $capTree = { param($Repository, $TimeoutSeconds) $capResponse }.GetNewClosure()
    Assert-Fails -ExpectedError 'No valid deployed|could be synchronized' -Action {
        & $syncScript -VaultPath (Join-Path $testRoot 'cap') -Now ([datetime]'2026-08-22T08:00:00') `
            -FallbackCandidateLimit 3 `
            -RemoteTreeProvider $capTree `
            -RemoteContentProvider $capContent
    }
    if (($capCalls -join ',') -cne '2026-08-21,2026-08-20,2026-08-19') {
        throw "Fallback candidate cap/order failed: $($capCalls -join ',')"
    }

    $clockState = [pscustomobject]@{ Value = [datetimeoffset]'2026-08-22T00:00:00Z' }
    $clock = { $clockState.Value }.GetNewClosure()
    $budgetContentCalls = [System.Collections.Generic.List[string]]::new()
    $budgetResponse = New-TreeResponse -Paths @('_posts/2026-08-21-summary-zh.md')
    $slowTree = {
        param($Repository, $TimeoutSeconds)
        $clockState.Value = $clockState.Value.AddSeconds(16)
        $budgetResponse
    }.GetNewClosure()
    $budgetContent = { param($Repository, $Date) [void]$budgetContentCalls.Add($Date); throw 'must not start' }.GetNewClosure()
    Assert-Fails -ExpectedError 'deadline|budget|No valid deployed' -Action {
        & $syncScript -VaultPath (Join-Path $testRoot 'budget') -Now ([datetime]'2026-08-22T08:00:00') `
            -RequestTimeoutSeconds 15 -OverallDeadlineSeconds 30 -ClockAction $clock `
            -RemoteTreeProvider $slowTree -RemoteContentProvider $budgetContent
    }
    if ($budgetContentCalls.Count -ne 0) { throw 'A content request started without a full request-timeout budget.' }

    $sleepClockState = [pscustomobject]@{ Value = [datetimeoffset]'2026-08-22T00:00:00Z' }
    $sleepClock = { $sleepClockState.Value }.GetNewClosure()
    $sleepResponse = New-TreeResponse -Paths @('_posts/2026-08-21-summary-zh.md')
    $sleepTreeCalls = [System.Collections.Generic.List[int]]::new()
    $sleepContentCalls = [System.Collections.Generic.List[string]]::new()
    $forbiddenSleeps = [System.Collections.Generic.List[int]]::new()
    $sleepTree = {
        param($Repository, $TimeoutSeconds)
        [void]$sleepTreeCalls.Add(1)
        $sleepResponse
    }.GetNewClosure()
    $slowFailure = {
        param($Repository, $Date)
        [void]$sleepContentCalls.Add($Date)
        $sleepClockState.Value = $sleepClockState.Value.AddSeconds(15)
        throw 'today failed at the request timeout'
    }.GetNewClosure()
    $forbiddenSleep = { param($Seconds) [void]$forbiddenSleeps.Add($Seconds) }.GetNewClosure()
    Assert-Fails -ExpectedError 'No valid deployed|deadline|budget' -Action {
        & $syncScript -VaultPath (Join-Path $testRoot 'sleep-budget') -Now ([datetime]'2026-08-22T20:00:00') `
            -RequestTimeoutSeconds 15 -OverallDeadlineSeconds 130 -ClockAction $sleepClock `
            -RemoteTreeProvider $sleepTree -RemoteContentProvider $slowFailure -SleepAction $forbiddenSleep
    }
    if ($sleepTreeCalls.Count -ne 1 -or $sleepContentCalls.Count -lt 1 -or $forbiddenSleeps.Count -ne 0) {
        throw 'A retry sleep started even though it could not fit before the overall deadline.'
    }

    'PASS'
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
