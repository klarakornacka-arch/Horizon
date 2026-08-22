[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$TaskName = 'AI Frontier Radar - Obsidian Sync',
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultPath,
    [string]$PowerShellPath,
    [scriptblock]$PowerShellVersionProvider = {
        param($Executable)
        & $Executable -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
    },
    [switch]$DefinitionOnly
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
    if ([System.IO.Path]::GetFileName($resolved) -ine 'pwsh.exe') {
        throw "PowerShell executable must be pwsh.exe: $resolved"
    }
    return $resolved
}

function Resolve-VaultDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [System.IO.Path]::IsPathFullyQualified($Path)) {
        throw 'VaultPath must be an absolute path.'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw 'VaultPath must exist and be a directory.'
    }
    return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
}

function Assert-PowerShell74OrLater {
    param(
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [Parameter(Mandatory = $true)][scriptblock]$VersionProvider
    )

    $versionOutput = @(& $VersionProvider $ExecutablePath)
    $reportedVersion = ([string]($versionOutput | Select-Object -Last 1)).Trim()
    $parsedVersion = $null
    if (-not [version]::TryParse($reportedVersion, [ref]$parsedVersion) -or $parsedVersion -lt [version]'7.4') {
        throw "PowerShell 7.4 or later is required; '$ExecutablePath' reported '$reportedVersion'."
    }
}

function New-ObsidianSyncTaskDefinition {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedVaultPath,
        [string]$RequestedPowerShellPath
    )

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

    $resolvedVaultPath = Resolve-VaultDirectory -Path $RequestedVaultPath
    $powerShellExecutable = Resolve-PowerShellExecutable -OverridePath $RequestedPowerShellPath
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        (ConvertTo-WindowsCommandLineArgument -Value $syncScript)
        '-VaultPath'
        (ConvertTo-WindowsCommandLineArgument -Value $resolvedVaultPath)
        '-TodayRetryAttempts'
        '6'
        '-TodayRetryDelaySeconds'
        '120'
        '-RequestTimeoutSeconds'
        '15'
        '-OverallDeadlineSeconds'
        '810'
        '-FallbackCandidateLimit'
        '3'
    ) -join ' '

    return [pscustomobject]@{
        TaskName = $TaskName
        VaultPath = $resolvedVaultPath
        Execute = $powerShellExecutable
        Argument = $arguments
        Triggers = @(
            [pscustomobject]@{ Type = 'Daily'; At = '19:15' }
            [pscustomobject]@{ Type = 'AtLogOn'; At = $null }
        )
        Settings = [pscustomobject]@{
            StartWhenAvailable = $true
            ExecutionTimeLimit = [TimeSpan]::FromMinutes(15)
        }
    }
}

$definition = New-ObsidianSyncTaskDefinition -RequestedVaultPath $VaultPath -RequestedPowerShellPath $PowerShellPath
if ($DefinitionOnly) {
    return $definition
}

Assert-PowerShell74OrLater -ExecutablePath $definition.Execute -VersionProvider $PowerShellVersionProvider

if (-not $PSCmdlet.ShouldProcess($definition.TaskName, 'Register or update Obsidian synchronization scheduled task')) {
    return
}

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if ([string]::IsNullOrWhiteSpace($currentUser)) {
    throw 'Unable to determine the current interactive Windows user.'
}
$action = New-ScheduledTaskAction -Execute $definition.Execute -Argument $definition.Argument
$triggers = foreach ($triggerDefinition in $definition.Triggers) {
    switch ($triggerDefinition.Type) {
        'Daily' {
            $dailyTime = [datetime]::ParseExact(
                $triggerDefinition.At,
                'HH:mm',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None
            )
            $dailyAt = Get-Date -Hour $dailyTime.Hour -Minute $dailyTime.Minute -Second 0 -Millisecond 0
            New-ScheduledTaskTrigger -Daily -At $dailyAt
        }
        'AtLogOn' {
            New-ScheduledTaskTrigger -AtLogOn
        }
        default {
            throw "Unsupported task trigger type: $($triggerDefinition.Type)"
        }
    }
}
$settingsArguments = @{ ExecutionTimeLimit = $definition.Settings.ExecutionTimeLimit }
if ($definition.Settings.StartWhenAvailable) {
    $settingsArguments.StartWhenAvailable = $true
}
$settings = New-ScheduledTaskSettingsSet @settingsArguments
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $definition.TaskName `
    -Action $action `
    -Trigger $triggers `
    -Settings $settings `
    -Principal $principal `
    -Description 'Sync AI Frontier Radar Markdown into Obsidian.' `
    -Force | Out-Null

Get-ScheduledTask -TaskName $definition.TaskName
