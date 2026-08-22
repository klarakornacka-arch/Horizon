$ErrorActionPreference = 'Stop'

$installer = Join-Path $PSScriptRoot 'install-obsidian-sync-task.ps1'

if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Installer is missing: $installer"
}

$errors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $installer,
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -gt 0) {
    throw "Installer has parser errors: $($errors | Out-String)"
}

$parameters = @{}
foreach ($parameter in $ast.ParamBlock.Parameters) {
    $parameters[$parameter.Name.VariablePath.UserPath] = $parameter
}

if ($parameters['VaultPath'] -isnot [System.Management.Automation.Language.ParameterAst]) {
    throw 'VaultPath parameter is missing.'
}
$hasMandatoryAttribute = $false
foreach ($attribute in $parameters['VaultPath'].Attributes) {
    if ($attribute.TypeName.FullName -ne 'Parameter') { continue }
    foreach ($argument in $attribute.NamedArguments) {
        if ($argument.ArgumentName -eq 'Mandatory' -and $argument.Argument.Extent.Text -match '\$true') {
            $hasMandatoryAttribute = $true
        }
    }
}
if (-not $hasMandatoryAttribute) {
    throw 'VaultPath must be mandatory.'
}
if ($null -ne $parameters['VaultPath'].DefaultValue) {
    throw 'VaultPath must not have a committed default value.'
}

$content = [System.IO.File]::ReadAllText($installer)
foreach ($requiredText in @(
    "[string]`$TaskName = 'AI Frontier Radar - Obsidian Sync'",
    '[CmdletBinding(SupportsShouldProcess = $true',
    'Resolve-Path -LiteralPath',
    'sync-to-obsidian.ps1',
    'Get-Command -Name pwsh',
    'New-ScheduledTaskAction',
    'New-ScheduledTaskTrigger -Daily -At',
    'New-ScheduledTaskTrigger -AtLogOn',
    'New-ScheduledTaskSettingsSet',
    'StartWhenAvailable = $true',
    '[TimeSpan]::FromMinutes(15)',
    'New-ScheduledTaskPrincipal',
    '-LogonType Interactive',
    '-RunLevel Limited',
    'Register-ScheduledTask',
    '-Force',
    'Get-ScheduledTask -TaskName'
)) {
    if (-not $content.Contains($requiredText)) {
        throw "Installer contract is missing: $requiredText"
    }
}

if ($content -match '(?im)^\s*\[string\]\s*\$VaultPath\s*=') {
    throw 'VaultPath must not use a default value.'
}
if ($content -match '(?i)(?:D:\\obsidian|人工智能尝试)') {
    throw 'Installer contains a committed Vault-local path.'
}

$shouldProcessIndex = $content.IndexOf('$PSCmdlet.ShouldProcess', [System.StringComparison]::Ordinal)
$firstSchedulerCommandIndex = $content.IndexOf('New-ScheduledTaskAction', [System.StringComparison]::Ordinal)
if ($shouldProcessIndex -lt 0 -or $shouldProcessIndex -gt $firstSchedulerCommandIndex) {
    throw 'WhatIf must gate Scheduler API calls before task objects are constructed.'
}
$runtimeTriggerDefinitionIndex = $content.IndexOf('$definition.Triggers', $firstSchedulerCommandIndex, [System.StringComparison]::Ordinal)
$runtimeSettingsDefinitionIndex = $content.IndexOf('$definition.Settings', $firstSchedulerCommandIndex, [System.StringComparison]::Ordinal)
if ($runtimeTriggerDefinitionIndex -lt 0 -or $runtimeSettingsDefinitionIndex -lt 0) {
    throw 'Registration must consume the shared trigger and settings definition.'
}

function Assert-Fails {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$ExpectedError
    )

    try {
        & $Action
    } catch {
        if ($_.Exception.Message -notmatch $ExpectedError) {
            throw "Expected error matching '$ExpectedError', got: $($_.Exception.Message)"
        }
        return
    }
    throw "Expected an error matching '$ExpectedError'."
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('horizon task definition [test] & ' + [guid]::NewGuid())
$scriptDirectory = Join-Path $testRoot 'repo [safe] & space\scripts'
$copiedInstaller = Join-Path $scriptDirectory 'install-obsidian-sync-task.ps1'
$copiedSyncScript = Join-Path $scriptDirectory 'sync-to-obsidian.ps1'
$vault = Join-Path $testRoot 'Vault [notes] & space'
$missingVault = Join-Path $testRoot 'missing vault'
$vaultFile = Join-Path $testRoot 'vault-file.txt'
$fakePwsh = Join-Path $testRoot 'pwsh.exe'
$wrongExecutable = Join-Path $testRoot 'other.exe'
$wrongCommand = Join-Path $testRoot 'pwsh.cmd'

try {
    New-Item -ItemType Directory -Path $scriptDirectory, $vault | Out-Null
    Copy-Item -LiteralPath $installer -Destination $copiedInstaller
    [System.IO.File]::WriteAllText($copiedSyncScript, @'
param([Parameter(Mandatory = $true)][string]$VaultPath)
Write-Output $VaultPath
'@)
    [System.IO.File]::WriteAllText($vaultFile, 'not a directory')
    [System.IO.File]::WriteAllText($fakePwsh, 'not executable')
    [System.IO.File]::WriteAllText($wrongExecutable, 'not executable')
    [System.IO.File]::WriteAllText($wrongCommand, 'not executable')

    $realPwsh = (Get-Command -Name pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $definition = & $copiedInstaller -VaultPath $vault -PowerShellPath $realPwsh -DefinitionOnly
    $canonicalVault = (Resolve-Path -LiteralPath $vault).ProviderPath
    $canonicalSync = (Resolve-Path -LiteralPath $copiedSyncScript).ProviderPath
    $expectedArgument = "-NoProfile -ExecutionPolicy Bypass -File `"$canonicalSync`" -VaultPath `"$canonicalVault`""

    if ($definition.TaskName -ne 'AI Frontier Radar - Obsidian Sync') { throw 'Definition has an unexpected task name.' }
    if ($definition.VaultPath -ne $canonicalVault) { throw 'Definition did not canonicalize VaultPath.' }
    if ($definition.Execute -ne (Resolve-Path -LiteralPath $realPwsh).ProviderPath) { throw 'Definition did not resolve the PowerShell executable.' }
    if ($definition.Argument -ne $expectedArgument) { throw "Definition action arguments did not quote paths as expected: $($definition.Argument)" }
    if ($definition.Triggers.Count -ne 2 -or $definition.Triggers[0].Type -ne 'Daily' -or $definition.Triggers[0].At -ne '19:15' -or $definition.Triggers[1].Type -ne 'AtLogOn') {
        throw 'Definition trigger contract is incorrect.'
    }
    if (-not $definition.Settings.StartWhenAvailable -or $definition.Settings.ExecutionTimeLimit -ne [TimeSpan]::FromMinutes(15)) {
        throw 'Definition settings contract is incorrect.'
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo.FileName = $definition.Execute
    $process.StartInfo.Arguments = $definition.Argument
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    [void]$process.Start()
    $roundTripVault = $process.StandardOutput.ReadToEnd().Trim()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or $roundTripVault -ne $canonicalVault) {
        throw 'Definition action arguments did not round-trip to the sync script.'
    }

    $fakeDefinition = & $copiedInstaller -VaultPath $vault -PowerShellPath $fakePwsh -DefinitionOnly
    if ($fakeDefinition.Execute -ne (Resolve-Path -LiteralPath $fakePwsh).ProviderPath) {
        throw 'DefinitionOnly unexpectedly executed or rejected a validly named PowerShell override.'
    }

    Assert-Fails -ExpectedError 'absolute path' -Action { & $copiedInstaller -VaultPath 'relative-vault' -DefinitionOnly }
    Assert-Fails -ExpectedError 'exist and be a directory' -Action { & $copiedInstaller -VaultPath $missingVault -DefinitionOnly }
    Assert-Fails -ExpectedError 'exist and be a directory' -Action { & $copiedInstaller -VaultPath $vaultFile -DefinitionOnly }
    Assert-Fails -ExpectedError 'must be pwsh.exe' -Action { & $copiedInstaller -VaultPath $vault -PowerShellPath $wrongExecutable -DefinitionOnly }
    Assert-Fails -ExpectedError 'must be pwsh.exe' -Action { & $copiedInstaller -VaultPath $vault -PowerShellPath $wrongCommand -DefinitionOnly }
    Assert-Fails -ExpectedError 'Cannot find path' -Action { & $copiedInstaller -VaultPath $vault -PowerShellPath (Join-Path $testRoot 'missing.exe') -DefinitionOnly }

    'BEHAVIOR PASS'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

'PASS'
