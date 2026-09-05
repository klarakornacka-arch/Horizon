$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Installer = Join-Path $PSScriptRoot 'install-personal-knowledge-base.ps1'
$Required = @(
    'knowledge-base\首页.md',
    'knowledge-base\AGENTS.md',
    'knowledge-base\Templates\原始资料.md',
    'knowledge-base\Templates\知识卡片.md',
    'knowledge-base\Templates\内容选题.md',
    'knowledge-base\Templates\项目简报.md',
    'knowledge-base\Templates\每周蒸馏.md',
    'knowledge-base\Templates\月度策略.md',
    'knowledge-base\05-复盘\知识库操作日志.md'
)

foreach ($Relative in $Required) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $Relative) -PathType Leaf)) {
        throw "Missing canonical asset: $Relative"
    }
}

$HomeContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'knowledge-base\首页.md') -Raw -Encoding utf8
foreach ($Target in @(
        '00-收集箱/',
        '01-原始资料/',
        '02-知识库/',
        '03-项目与作品集/',
        '04-内容生产/',
        '05-复盘/',
        '06-资源与素材/',
        'Templates/'
    )) {
    if ($HomeContent -notmatch [regex]::Escape("[[$Target|")) {
        throw "首页.md is missing exact wiki-link target: $Target"
    }
}

$Agents = Get-Content -LiteralPath (Join-Path $RepoRoot 'knowledge-base\AGENTS.md') -Raw -Encoding utf8
foreach ($Rule in @('不得删除', '原始资料只读', '事实与判断分开', '来源日期')) {
    if ($Agents -notmatch [regex]::Escape($Rule)) {
        throw "AGENTS.md is missing required rule: $Rule"
    }
}

$DerivedTemplates = @(
    'Templates\知识卡片.md',
    'Templates\内容选题.md',
    'Templates\项目简报.md',
    'Templates\每周蒸馏.md',
    'Templates\月度策略.md'
)
foreach ($Relative in $DerivedTemplates) {
    $Template = Get-Content -LiteralPath (Join-Path $RepoRoot "knowledge-base\$Relative") -Raw -Encoding utf8
    foreach ($Field in @('source_url', 'source_date')) {
        if ($Template -notmatch [regex]::Escape($Field)) {
            throw "$Relative is missing source provenance field: $Field"
        }
    }
}

if (-not (Test-Path -LiteralPath $Installer -PathType Leaf)) {
    throw "Installer is missing: $Installer"
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

function Get-VaultFileHashes {
    param([Parameter(Mandatory = $true)][string]$VaultRoot)

    $hashes = @{}
    Get-ChildItem -LiteralPath $VaultRoot -File -Recurse | ForEach-Object {
        $relative = [System.IO.Path]::GetRelativePath($VaultRoot, $_.FullName)
        $hashes[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    return $hashes
}

$TempVault = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-test-" + [guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path $TempVault | Out-Null
    Set-Content -LiteralPath (Join-Path $TempVault '首页.md') -Value '用户原有首页' -Encoding utf8
    $legacyDirectory = Join-Path $TempVault 'AI情报日报'
    New-Item -ItemType Directory -Path $legacyDirectory | Out-Null
    $legacyNote = Join-Path $legacyDirectory 'legacy.md'
    Set-Content -LiteralPath $legacyNote -Value '用户历史日报' -Encoding utf8
    $legacyHash = (Get-FileHash -LiteralPath $legacyNote -Algorithm SHA256).Hash

    $firstRun = @(& $Installer -VaultRoot $TempVault)
    if (-not ($firstRun -match '^Created:')) { throw 'Installer did not report any created paths.' }
    if (-not ($firstRun -match '^Preserved:.*首页\.md$')) { throw 'Installer did not report preservation of the existing 首页.md.' }
    if (-not ($firstRun -match '^Ready:')) { throw 'Installer did not report readiness.' }

    if ((Get-Content -LiteralPath (Join-Path $TempVault '首页.md') -Raw -Encoding utf8) -notmatch '用户原有首页') {
        throw 'Installer overwrote an existing note.'
    }
    if ((Get-FileHash -LiteralPath $legacyNote -Algorithm SHA256).Hash -ne $legacyHash) {
        throw 'Installer modified a legacy AI情报日报 note.'
    }

    foreach ($Relative in @(
            '00-收集箱',
            '01-原始资料\AI行业热点日报',
            '02-知识库\AI工具与工作流',
            '02-知识库\设计思维与品牌审美',
            '02-知识库\内容增长与商业化',
            '02-知识库\方法与模板',
            '03-项目与作品集',
            '04-内容生产\选题池',
            '04-内容生产\文案与脚本',
            '04-内容生产\已发布',
            '05-复盘\每周蒸馏',
            '05-复盘\月度策略',
            '06-资源与素材',
            'Templates'
        )) {
        if (-not (Test-Path -LiteralPath (Join-Path $TempVault $Relative) -PathType Container)) {
            throw "Installer did not create required directory: $Relative"
        }
    }

    $hashesBeforeSecondRun = Get-VaultFileHashes -VaultRoot $TempVault
    $secondRun = @(& $Installer -VaultRoot $TempVault)
    if (-not ($secondRun -match '^Preserved:')) { throw 'Installer did not report preserved files on the second run.' }
    if (-not ($secondRun -match '^Ready:')) { throw 'Installer did not report readiness on the second run.' }
    $hashesAfterSecondRun = Get-VaultFileHashes -VaultRoot $TempVault
    if ($hashesBeforeSecondRun.Count -ne $hashesAfterSecondRun.Count) {
        throw 'Installer changed the set of Vault files on the second run.'
    }
    foreach ($relative in $hashesBeforeSecondRun.Keys) {
        if (-not $hashesAfterSecondRun.ContainsKey($relative) -or $hashesBeforeSecondRun[$relative] -ne $hashesAfterSecondRun[$relative]) {
            throw "Installer changed existing file content on the second run: $relative"
        }
    }

    Assert-Fails -ExpectedError 'absolute' -Action { & $Installer -VaultRoot 'relative-vault' }
} finally {
    if (Test-Path -LiteralPath $TempVault) {
        Remove-Item -LiteralPath $TempVault -Recurse -Force
    }
}

$DirectoryCollisionVault = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-directory-collision-" + [guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path $DirectoryCollisionVault | Out-Null
    Set-Content -LiteralPath (Join-Path $DirectoryCollisionVault '00-收集箱') -Value 'must remain a file' -Encoding utf8
    Assert-Fails -ExpectedError 'required directory.*container' -Action { & $Installer -VaultRoot $DirectoryCollisionVault }
    if ((Get-ChildItem -LiteralPath $DirectoryCollisionVault -Force).Count -ne 1) {
        throw 'Directory collision preflight created partial Vault content.'
    }
} finally {
    if (Test-Path -LiteralPath $DirectoryCollisionVault) { Remove-Item -LiteralPath $DirectoryCollisionVault -Recurse -Force }
}

$FileCollisionVault = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-file-collision-" + [guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path $FileCollisionVault, (Join-Path $FileCollisionVault '首页.md') | Out-Null
    Assert-Fails -ExpectedError 'canonical file.*leaf' -Action { & $Installer -VaultRoot $FileCollisionVault }
    if ((Get-ChildItem -LiteralPath $FileCollisionVault -Force).Count -ne 1) {
        throw 'File collision preflight created partial Vault content.'
    }
} finally {
    if (Test-Path -LiteralPath $FileCollisionVault) { Remove-Item -LiteralPath $FileCollisionVault -Recurse -Force }
}

$SourceReparseTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-source-reparse-test-" + [guid]::NewGuid())
try {
    $fixtureRepository = Join-Path $SourceReparseTestRoot 'repository'
    $fixtureScripts = Join-Path $fixtureRepository 'scripts'
    $fixtureVault = Join-Path $SourceReparseTestRoot 'vault'
    $fixtureInstaller = Join-Path $fixtureScripts 'install-personal-knowledge-base.ps1'
    New-Item -ItemType Directory -Path $fixtureScripts, $fixtureVault | Out-Null
    Copy-Item -LiteralPath $Installer -Destination $fixtureInstaller
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'knowledge-base') -Destination $fixtureRepository -Recurse

    $outsideSourceFile = Join-Path $SourceReparseTestRoot 'outside-source.md'
    $linkedSourceFile = Join-Path $fixtureRepository 'knowledge-base\linked-source.md'
    Set-Content -LiteralPath $outsideSourceFile -Value 'outside canonical source' -Encoding utf8
    $sourceReparsePath = $null
    try {
        New-Item -ItemType SymbolicLink -Path $linkedSourceFile -Target $outsideSourceFile | Out-Null
        $sourceReparsePath = $linkedSourceFile
    } catch {
        if ($_.Exception.Message -notmatch '(?i)(privilege|permission|access is denied|not permitted|not supported)') {
            throw
        }
        $outsideSourceDirectory = Join-Path $SourceReparseTestRoot 'outside-source-directory'
        $linkedSourceDirectory = Join-Path $fixtureRepository 'knowledge-base\linked-source-directory'
        New-Item -ItemType Directory -Path $outsideSourceDirectory | Out-Null
        Set-Content -LiteralPath (Join-Path $outsideSourceDirectory 'outside.md') -Value 'outside canonical source directory' -Encoding utf8
        try {
            New-Item -ItemType Junction -Path $linkedSourceDirectory -Target $outsideSourceDirectory | Out-Null
            $sourceReparsePath = $linkedSourceDirectory
        } catch {
            if ($_.Exception.Message -notmatch '(?i)(privilege|permission|access is denied|not permitted|not supported)') {
                throw
            }
            Write-Warning "SKIP: source reparse test requires symbolic-link or junction creation support: $($_.Exception.Message)"
        }
    }

    if ($null -ne $sourceReparsePath) {
        Assert-Fails -ExpectedError 'reparse point' -Action { & $fixtureInstaller -VaultRoot $fixtureVault }
        if (@(Get-ChildItem -LiteralPath $fixtureVault -Force).Count -ne 0) {
            throw 'Installer changed the Vault before rejecting a linked canonical source file.'
        }
    }
} finally {
    if (Test-Path -LiteralPath $SourceReparseTestRoot) {
        Remove-Item -LiteralPath $SourceReparseTestRoot -Recurse -Force
    }
}

Write-Output 'PASS: knowledge-base asset and installer contract'
