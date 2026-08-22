[CmdletBinding()]
param(
    [string]$Date = (Get-Date).ToString('yyyy-MM-dd'),
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultPath,
    [string]$Repository = 'klarakornacka-arch/Horizon',
    [string]$SourceFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-IsoDate {
    param([Parameter(Mandatory = $true)][string]$Value)

    $parsed = [datetime]::MinValue
    $valid = [datetime]::TryParseExact(
        $Value,
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
    if (-not $valid -or $parsed.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) -cne $Value) {
        throw "Date must be an ISO calendar date in yyyy-MM-dd form; received '$Value'."
    }
    return $Value
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $rootWithSeparator = [System.IO.Path]::TrimEndingDirectorySeparator($Root) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $Candidate.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description escapes the resolved VaultPath."
    }
}

function Get-StrictUtf8Text {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { throw 'Downloaded briefing is empty.' }
    try {
        return ([System.Text.UTF8Encoding]::new($false, $true)).GetString($bytes).TrimStart([char]0xFEFF)
    } catch [System.Text.DecoderFallbackException] {
        throw 'Downloaded briefing is not valid UTF-8 Markdown.'
    }
}

function Assert-Briefing {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedDate
    )

    $content = Get-StrictUtf8Text -Path $Path
    if ([string]::IsNullOrWhiteSpace($content)) { throw 'Downloaded briefing is empty.' }
    if ($content -match '(?is)<\s*(?:!doctype|html|head|body)\b') {
        throw 'Downloaded content looks like an HTML/error page, not Markdown.'
    }
    $frontMatterMatch = [regex]::Match($content, '\A---\r?\n(?<frontMatter>.*?)\r?\n---(?:\r?\n|$)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $frontMatterMatch.Success) {
        throw 'Expected Jekyll front matter is missing from the generated briefing.'
    }
    $frontMatter = $frontMatterMatch.Groups['frontMatter'].Value
    $expectedDatePattern = '(?m)^date:\s*{0}[ \t]*\r?$' -f [regex]::Escape($ExpectedDate)
    if ($frontMatter -notmatch $expectedDatePattern) {
        throw "Briefing front matter does not contain the expected date $ExpectedDate."
    }
    if ($frontMatter -notmatch '(?m)^lang:\s*zh[ \t]*\r?$') {
        throw 'Expected Chinese briefing front matter "lang: zh" is missing.'
    }

    $topThreeHeadings = [regex]::Matches($content, '(?m)^##\s+今日优先选题 Top 3[ \t]*\r?$')
    if ($topThreeHeadings.Count -ne 1) {
        throw "Expected exactly one '## 今日优先选题 Top 3' heading; found $($topThreeHeadings.Count)."
    }
}

function Test-ReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $attributes = (Get-Item -LiteralPath $Path -Force).Attributes
    return (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

$temporaryPath = $null
$backupPath = $null
try {
    $dateText = Get-IsoDate -Value $Date

    $vaultInput = [System.IO.Path]::GetFullPath($VaultPath)
    [System.IO.Directory]::CreateDirectory($vaultInput) | Out-Null
    $resolvedVault = (Resolve-Path -LiteralPath $vaultInput).ProviderPath
    $destinationInput = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($resolvedVault, 'AI情报日报'))
    Assert-ChildPath -Root $resolvedVault -Candidate $destinationInput -Description 'Destination directory'
    if (Test-ReparsePoint -Path $destinationInput) {
        throw 'Destination directory is a reparse point; refusing to write through it.'
    }
    [System.IO.Directory]::CreateDirectory($destinationInput) | Out-Null
    $destinationDirectory = (Resolve-Path -LiteralPath $destinationInput).ProviderPath
    Assert-ChildPath -Root $resolvedVault -Candidate $destinationDirectory -Description 'Destination directory'

    $destination = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($destinationDirectory, "$dateText.md"))
    Assert-ChildPath -Root $destinationDirectory -Candidate $destination -Description 'Destination file'
    Assert-ChildPath -Root $resolvedVault -Candidate $destination -Description 'Destination file'
    if (Test-ReparsePoint -Path $destination) {
        throw 'Destination file is a reparse point; refusing to replace it.'
    }

    $temporaryPath = [System.IO.Path]::Combine($destinationDirectory, ".ai-frontier-radar-$([guid]::NewGuid()).tmp")
    Assert-ChildPath -Root $destinationDirectory -Candidate $temporaryPath -Description 'Temporary file'
    $stream = [System.IO.File]::Open($temporaryPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $stream.Dispose()

    if ([string]::IsNullOrWhiteSpace($SourceFile)) {
        if ([string]::IsNullOrWhiteSpace($Repository) -or $Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
            throw 'Repository must be an owner/name value suitable for the public GitHub raw URL.'
        }
        $rawUri = "https://raw.githubusercontent.com/$Repository/gh-pages/_posts/$dateText-summary-zh.md"
        Invoke-WebRequest -Uri $rawUri -Headers @{ 'User-Agent' = 'AI-Frontier-Radar-Sync'; 'Accept' = 'text/plain' } -OutFile $temporaryPath -MaximumRedirection 5
    } else {
        $resolvedSource = [System.IO.Path]::GetFullPath($SourceFile)
        if (-not [System.IO.File]::Exists($resolvedSource)) {
            throw "Local source file does not exist: $SourceFile"
        }
        [System.IO.File]::Copy($resolvedSource, $temporaryPath, $true)
    }

    Assert-Briefing -Path $temporaryPath -ExpectedDate $dateText
    if ([System.IO.File]::Exists($destination)) {
        $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        $temporaryHash = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash
        if ($destinationHash -eq $temporaryHash) {
            Write-Output "Unchanged: $destination"
            return
        }
        $backupPath = [System.IO.Path]::Combine($destinationDirectory, ".ai-frontier-radar-$([guid]::NewGuid()).bak")
        Assert-ChildPath -Root $destinationDirectory -Candidate $backupPath -Description 'Replacement backup file'
        [System.IO.File]::Replace($temporaryPath, $destination, $backupPath)
    } else {
        [System.IO.File]::Move($temporaryPath, $destination)
    }
    Write-Output "Synced: $destination"
} finally {
    if ($null -ne $temporaryPath -and [System.IO.File]::Exists($temporaryPath)) {
        [System.IO.File]::Delete($temporaryPath)
    }
    if ($null -ne $backupPath -and [System.IO.File]::Exists($backupPath)) {
        [System.IO.File]::Delete($backupPath)
    }
}
