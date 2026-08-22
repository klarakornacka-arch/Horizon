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
    'New-ScheduledTaskSettingsSet -StartWhenAvailable',
    'New-TimeSpan -Minutes 15',
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

'PASS'
