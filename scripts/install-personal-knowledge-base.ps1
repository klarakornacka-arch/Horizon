[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return (((Get-Item -LiteralPath $Path -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Assert-NoReparsePointsInExistingPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "$Description has no filesystem root."
    }
    if (Test-ReparsePoint -Path $root) {
        throw "$Description component is a reparse point: $root"
    }

    $current = $root
    $relative = $fullPath.Substring($root.Length)
    foreach ($component in ($relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $current = [System.IO.Path]::Combine($current, $component)
        if (Test-ReparsePoint -Path $current) {
            throw "$Description component is a reparse point: $current"
        }
    }
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $rootWithSeparator = [System.IO.Path]::TrimEndingDirectorySeparator($Root) + [System.IO.Path]::DirectorySeparatorChar
    if (
        -not [string]::Equals($Candidate, $Root, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $Candidate.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "$Description escapes Vault root."
    }
}

function Assert-DirectoryDestination {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        throw "$Description must be a container; existing path is a file: $Path"
    }
}

function Assert-FileDestination {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if (Test-Path -LiteralPath $Path -PathType Container) {
        throw "$Description must be a leaf; existing path is a directory: $Path"
    }
}

function Assert-ExistingParentsAreContainers {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Description
    )
    $parent = [System.IO.Path]::GetDirectoryName($Path)
    while ($null -ne $parent -and $parent -ne $Root) {
        if (Test-Path -LiteralPath $parent -PathType Leaf) {
            throw "$Description parent must be a container; existing path is a file: $parent"
        }
        $parent = [System.IO.Path]::GetDirectoryName($parent)
    }
}

function Get-ValidatedCanonicalFiles {
    param([Parameter(Mandatory = $true)][string]$CanonicalRoot)

    Assert-NoReparsePointsInExistingPath -Path $CanonicalRoot -Description 'Canonical knowledge-base directory'
    $files = [System.Collections.Generic.List[string]]::new()
    $directories = [System.Collections.Generic.Stack[string]]::new()
    $directories.Push($CanonicalRoot)

    while ($directories.Count -gt 0) {
        $directory = $directories.Pop()
        Assert-ChildPath -Root $CanonicalRoot -Candidate $directory -Description 'Canonical source directory'
        Assert-NoReparsePointsInExistingPath -Path $directory -Description 'Canonical source directory'

        foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
            $relative = [System.IO.Path]::GetRelativePath($CanonicalRoot, $item.FullName)
            Assert-ChildPath -Root $CanonicalRoot -Candidate $item.FullName -Description "Canonical source item '$relative'"
            Assert-NoReparsePointsInExistingPath -Path $item.FullName -Description "Canonical source item '$relative'"

            if ($item.PSIsContainer) {
                $directories.Push($item.FullName)
            } else {
                $files.Add($item.FullName)
            }
        }
    }

    return $files.ToArray()
}

if (-not [System.IO.Path]::IsPathFullyQualified($VaultRoot)) {
    throw 'VaultRoot must be absolute.'
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$canonicalRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'knowledge-base'))
if (-not (Test-Path -LiteralPath $canonicalRoot -PathType Container)) {
    throw "Canonical knowledge-base directory is missing: $canonicalRoot"
}
$canonicalFiles = Get-ValidatedCanonicalFiles -CanonicalRoot $canonicalRoot

$resolvedVault = [System.IO.Path]::GetFullPath($VaultRoot)
Assert-NoReparsePointsInExistingPath -Path $resolvedVault -Description 'Vault root'
[System.IO.Directory]::CreateDirectory($resolvedVault) | Out-Null
Assert-NoReparsePointsInExistingPath -Path $resolvedVault -Description 'Vault root'

$requiredDirectories = @(
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
)

# Preflight every destination before creating the Vault root, directories, or files.
$requiredDirectoryTargets = @()
foreach ($relative in $requiredDirectories) {
    $target = [System.IO.Path]::GetFullPath((Join-Path $resolvedVault $relative))
    Assert-ChildPath -Root $resolvedVault -Candidate $target -Description "Directory '$relative'"
    Assert-DirectoryDestination -Path $target -Description "Required directory '$relative'"
    Assert-ExistingParentsAreContainers -Path $target -Root $resolvedVault -Description "Required directory '$relative'"
    $requiredDirectoryTargets += $target
}

$canonicalDestinationTargets = @()
foreach ($source in $canonicalFiles) {
    $relative = [System.IO.Path]::GetRelativePath($canonicalRoot, $source)
    $target = [System.IO.Path]::GetFullPath((Join-Path $resolvedVault $relative))
    Assert-ChildPath -Root $resolvedVault -Candidate $target -Description "Canonical file '$relative'"
    Assert-FileDestination -Path $target -Description "Canonical file '$relative'"
    Assert-ExistingParentsAreContainers -Path $target -Root $resolvedVault -Description "Canonical file '$relative'"
    $canonicalDestinationTargets += $target
}

foreach ($relative in $requiredDirectories) {
    $target = [System.IO.Path]::GetFullPath((Join-Path $resolvedVault $relative))
    Assert-ChildPath -Root $resolvedVault -Candidate $target -Description "Directory '$relative'"
    Assert-NoReparsePointsInExistingPath -Path $target -Description "Directory '$relative'"

    Assert-DirectoryDestination -Path $target -Description "Required directory '$relative'"
    if (Test-Path -LiteralPath $target) {
        Write-Output "Preserved: $target"
        continue
    }

    [System.IO.Directory]::CreateDirectory($target) | Out-Null
    Write-Output "Created: $target"
}

foreach ($source in $canonicalFiles) {
    $relative = [System.IO.Path]::GetRelativePath($canonicalRoot, $source)
    Assert-ChildPath -Root $canonicalRoot -Candidate $source -Description "Canonical file '$relative'"
    Assert-NoReparsePointsInExistingPath -Path $source -Description "Canonical file '$relative'"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Canonical source is no longer a file: $source"
    }
    $target = [System.IO.Path]::GetFullPath((Join-Path $resolvedVault $relative))
    Assert-ChildPath -Root $resolvedVault -Candidate $target -Description "Canonical file '$relative'"
    $parent = [System.IO.Path]::GetDirectoryName($target)
    Assert-NoReparsePointsInExistingPath -Path $parent -Description "Parent directory for '$relative'"
    Assert-NoReparsePointsInExistingPath -Path $target -Description "Canonical file '$relative'"

    Assert-FileDestination -Path $target -Description "Canonical file '$relative'"
    if (Test-Path -LiteralPath $target) {
        Write-Output "Preserved: $target"
        continue
    }

    [System.IO.File]::Copy($source, $target, $false)
    Write-Output "Created: $target"
}

Write-Output "Ready: $resolvedVault"
