[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$TaskName = 'AI Frontier Radar - Obsidian Sync',
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultPath,
    [string]$PowerShellPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-WindowsCommandLineArgument {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($Value.IndexOf([char]0) -ge 0) {
        throw 'Scheduled task arguments cannot contain a null character.'
    }

    $quoted = [System.Text.StringBuilder]::new()
    [void]$quoted.Append([char]'"')
    $backslashCount = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]'\') {
            $backslashCount++
            continue
        }
        if ($character -eq [char]'"') {
            [void]$quoted.Append([char]'\', ($backslashCount * 2) + 1)
            [void]$quoted.Append($character)
            $backslashCount = 0
            continue
        }
        if ($backslashCount -gt 0) {
            [void]$quoted.Append([char]'\', $backslashCount)
            $backslashCount = 0
        }
        [void]$quoted.Append($character)
    }
    if ($backslashCount -gt 0) {
        [void]$quoted.Append([char]'\', $backslashCount * 2)
    }
    [void]$quoted.Append([char]'"')
    return $quoted.ToString()
}

function Resolve-PowerShellExecutable {
    param([string]$OverridePath)

    if ([string]::IsNullOrWhiteSpace($OverridePath)) {
        $candidate = (Get-Command -Name pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    } else {
        $candidate = $OverridePath
    }

    $resolved = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "PowerShell executable is not a file: $resolved"
    }
    return $resolved
}

function Assert-PowerShell7OrLater {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)

    $majorVersionText = & $ExecutablePath -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.Major'
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to determine the PowerShell version for '$ExecutablePath'."
    }
    $majorVersion = 0
    if (-not [int]::TryParse(($majorVersionText | Select-Object -Last 1).ToString().Trim(), [ref]$majorVersion) -or $majorVersion -lt 7) {
        throw "PowerShell 7 or later is required; '$ExecutablePath' reported '$majorVersionText'."
    }
}

$scriptDirectory = (Resolve-Path -LiteralPath $PSScriptRoot -ErrorAction Stop).ProviderPath
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDirectory '..') -ErrorAction Stop).ProviderPath
$expectedSyncScript = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory 'sync-to-obsidian.ps1'))
$syncScript = (Resolve-Path -LiteralPath $expectedSyncScript -ErrorAction Stop).ProviderPath
if (-not [string]::Equals($syncScript, $expectedSyncScript, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Resolved sync script does not match the installer repository path.'
}
if (-not (Test-Path -LiteralPath $syncScript -PathType Leaf)) {
    throw "Sync script is not a file: $syncScript"
}
if (-not (Test-Path -LiteralPath $repositoryRoot -PathType Container)) {
    throw "Repository root is not a directory: $repositoryRoot"
}

$powerShellExecutable = Resolve-PowerShellExecutable -OverridePath $PowerShellPath
Assert-PowerShell7OrLater -ExecutablePath $powerShellExecutable

$arguments = @(
    '-NoProfile'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    (ConvertTo-WindowsCommandLineArgument -Value $syncScript)
    '-VaultPath'
    (ConvertTo-WindowsCommandLineArgument -Value $VaultPath)
) -join ' '

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if ([string]::IsNullOrWhiteSpace($currentUser)) {
    throw 'Unable to determine the current interactive Windows user.'
}

if (-not $PSCmdlet.ShouldProcess($TaskName, 'Register or update Obsidian synchronization scheduled task')) {
    return
}

$action = New-ScheduledTaskAction -Execute $powerShellExecutable -Argument $arguments
$dailyAt = Get-Date -Hour 19 -Minute 15 -Second 0 -Millisecond 0
$triggers = @(
    New-ScheduledTaskTrigger -Daily -At $dailyAt
    New-ScheduledTaskTrigger -AtLogOn
)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $triggers `
    -Settings $settings `
    -Principal $principal `
    -Description 'Sync AI Frontier Radar Markdown into Obsidian.' `
    -Force | Out-Null

Get-ScheduledTask -TaskName $TaskName
