[CmdletBinding()]
param(
    [string]$Date,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultPath,
    [string]$Repository = 'klarakornacka-arch/Horizon',
    [string]$SourceFile,
    [datetime]$Now = (Get-Date),
    [ValidateRange(1, 20)]
    [int]$TodayRetryAttempts = 6,
    [ValidateRange(0, 600)]
    [int]$TodayRetryDelaySeconds = 120,
    [ValidateRange(1, 60)]
    [int]$RequestTimeoutSeconds = 15,
    [ValidateRange(30, 810)]
    [int]$OverallDeadlineSeconds = 810,
    [ValidateRange(1, 10)]
    [int]$FallbackCandidateLimit = 3,
    [scriptblock]$RemoteTreeProvider = {
        param($RequestedRepository, $TimeoutSeconds)
        $uri = "https://api.github.com/repos/$RequestedRepository/git/trees/gh-pages?recursive=1"
        $bytes = Invoke-BoundedHttpGet -Uri $uri -TimeoutSeconds $TimeoutSeconds -MaximumBytes 2097152
        $json = ([System.Text.UTF8Encoding]::new($false, $true)).GetString($bytes)
        return ($json | ConvertFrom-Json -Depth 5)
    },
    [scriptblock]$RemoteContentProvider = {
        param($RequestedRepository, $RequestedDate, $Destination, $TimeoutSeconds)
        $rawUri = "https://raw.githubusercontent.com/$RequestedRepository/gh-pages/_posts/$RequestedDate-summary-zh.md"
        $bytes = Invoke-BoundedHttpGet -Uri $rawUri -TimeoutSeconds $TimeoutSeconds -MaximumBytes 2097152
        [System.IO.File]::WriteAllBytes($Destination, $bytes)
    },
    [scriptblock]$SleepAction = { param($Seconds) Start-Sleep -Seconds $Seconds },
    [scriptblock]$ClockAction = { [datetimeoffset]::UtcNow }
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

function Get-UnfencedMarkdown {
    param([Parameter(Mandatory = $true)][string]$Markdown)

    $visible = [System.Text.StringBuilder]::new()
    $insideFence = $false
    $fenceCharacter = $null
    $fenceLength = 0
    foreach ($line in [regex]::Split($Markdown, '\r?\n')) {
        if (-not $insideFence) {
            if ($line -match '^(?:    |\t)') { continue }
            $openingFence = [regex]::Match($line, '^\s{0,3}(?<fence>`{3,}|~{3,})')
            if ($openingFence.Success) {
                $fence = $openingFence.Groups['fence'].Value
                $insideFence = $true
                $fenceCharacter = $fence[0]
                $fenceLength = $fence.Length
                continue
            }
        } else {
            $closingFence = [regex]::Match($line, '^\s{0,3}(?<fence>`{3,}|~{3,})[ \t]*$')
            if ($closingFence.Success) {
                $fence = $closingFence.Groups['fence'].Value
                if ($fence[0] -eq $fenceCharacter -and $fence.Length -ge $fenceLength) {
                    $insideFence = $false
                }
            }
            continue
        }
        [void]$visible.AppendLine($line)
    }
    return $visible.ToString()
}

function Remove-InlineCodeSpans {
    param([Parameter(Mandatory = $true)][string]$Markdown)

    return [regex]::Replace($Markdown, '(?s)(`+).*?\1', '')
}

function Get-CanonicalFrontMatterValues {
    param([Parameter(Mandatory = $true)][string]$FrontMatter)

    $values = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in [regex]::Split($FrontMatter, '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $match = [regex]::Match($line, '^(?<key>[A-Za-z_][A-Za-z0-9_-]*):[ \t]*(?<value>.*)$')
        if (-not $match.Success) {
            throw 'Jekyll front matter must use canonical bare ASCII top-level mapping keys.'
        }
        $key = $match.Groups['key'].Value
        $canonicalKeys = @('title', 'date', 'lang', 'generated_at', 'source_version')
        if ($canonicalKeys -icontains $key -and $canonicalKeys -cnotcontains $key) {
            throw 'Jekyll front matter must use canonical bare lowercase metadata keys.'
        }
        if ($values.ContainsKey($key)) {
            throw "Duplicate top-level front matter key '$key' is not allowed."
        }
        $values.Add($key, $match.Groups['value'].Value)
    }
    return $values
}

function Get-RequiredFrontMatterValue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.Dictionary[string, string]]$Values,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if (-not $Values.ContainsKey($Key)) {
        throw "Expected exactly one $Key key in Jekyll front matter; found 0."
    }
    $value = $Values[$Key].Trim()
    if ($value.Length -ge 2 -and $value[0] -eq $value[$value.Length - 1] -and ($value[0] -eq '"' -or $value[0] -eq "'")) {
        return $value.Substring(1, $value.Length - 2)
    }
    return $value
}

function Assert-NoReparsePointsInExistingPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if ([string]::IsNullOrEmpty($root)) { throw "$Description has no filesystem root." }
    if (Test-ReparsePoint -Path $root) { throw "$Description component is a reparse point: $root" }

    $current = $root
    $relative = $fullPath.Substring($root.Length)
    foreach ($component in ($relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $current = [System.IO.Path]::Combine($current, $component)
        if (Test-ReparsePoint -Path $current) {
            throw "$Description component is a reparse point: $current"
        }
    }
}

function Assert-SafeRepository {
    param([Parameter(Mandatory = $true)][string]$Value)

    $parts = $Value -split '/'
    if ($parts.Count -ne 2) { throw 'Repository must use safe owner/repository components.' }
    foreach ($part in $parts) {
        if ($part -eq '.' -or $part -eq '..' -or $part -notmatch '^[A-Za-z0-9_.-]+$') {
            throw 'Repository must use safe owner/repository components.'
        }
    }
}

function Invoke-BoundedHttpGet {
    param(
        [Parameter(Mandatory = $true)][uri]$Uri,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$MaximumBytes
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $handler.MaxAutomaticRedirections = 5
    $client = [System.Net.Http.HttpClient]::new($handler, $true)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('AI-Frontier-Radar-Sync')
    $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    $cancellation = [System.Threading.CancellationTokenSource]::new()
    $cancellation.CancelAfter([TimeSpan]::FromSeconds($TimeoutSeconds))
    $response = $null
    $stream = $null
    $memory = [System.IO.MemoryStream]::new()
    try {
        $response = $client.GetAsync(
            $Uri,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead,
            $cancellation.Token
        ).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode() | Out-Null
        $contentLength = $response.Content.Headers.ContentLength
        if ($null -ne $contentLength -and $contentLength -gt $MaximumBytes) {
            throw "HTTP response is oversized (maximum $MaximumBytes bytes)."
        }
        $stream = $response.Content.ReadAsStreamAsync($cancellation.Token).GetAwaiter().GetResult()
        $buffer = [byte[]]::new(8192)
        while (($read = $stream.ReadAsync($buffer, 0, $buffer.Length, $cancellation.Token).GetAwaiter().GetResult()) -gt 0) {
            if ($memory.Length + $read -gt $MaximumBytes) {
                throw "HTTP response is oversized (maximum $MaximumBytes bytes)."
            }
            $memory.Write($buffer, 0, $read)
        }
        return $memory.ToArray()
    } catch [System.OperationCanceledException] {
        throw "HTTP request timed out after $TimeoutSeconds seconds."
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        $memory.Dispose()
        $cancellation.Dispose()
        $client.Dispose()
    }
}

function Get-TreePostDates {
    param(
        [Parameter(Mandatory = $true)]$Response,
        [Parameter(Mandatory = $true)][string]$NotLaterThan
    )

    if ($Response.PSObject.Properties.Name -notcontains 'truncated' -or $Response.truncated -isnot [bool]) {
        throw 'Git tree response is malformed: truncated must be a Boolean.'
    }
    if ($Response.truncated) {
        throw 'Git tree response is truncated; refusing incomplete discovery.'
    }
    if ($Response.PSObject.Properties.Name -notcontains 'tree' -or $null -eq $Response.tree) {
        throw 'Git tree response is malformed: tree is missing.'
    }
    $entries = @($Response.tree)
    if ($entries.Count -gt 1000) {
        throw 'Git tree response exceeds the bounded 1000-entry limit.'
    }

    $dates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $entries) {
        if ($null -eq $entry -or $entry.PSObject.Properties.Name -notcontains 'type' -or $entry.PSObject.Properties.Name -notcontains 'path') {
            throw 'Git tree response contains a malformed entry.'
        }
        if ($entry.type -isnot [string] -or $entry.path -isnot [string]) {
            throw 'Git tree response contains a malformed entry type or path.'
        }
        if ($entry.type -cne 'blob') { continue }
        $match = [regex]::Match($entry.path, '^_posts/(?<date>\d{4}-\d{2}-\d{2})-summary-zh\.md$', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if (-not $match.Success) { continue }
        $candidate = Get-IsoDate -Value $match.Groups['date'].Value
        if ([string]::CompareOrdinal($candidate, $NotLaterThan) -le 0) {
            [void]$dates.Add($candidate)
        }
    }
    return @($dates | Sort-Object -Descending)
}

function Get-RemoteCandidateDates {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedRepository,
        [Parameter(Mandatory = $true)][string]$Today,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][scriptblock]$TreeProvider
    )

    $response = & $TreeProvider $RequestedRepository $TimeoutSeconds
    $latestDates = @(Get-TreePostDates -Response $response -NotLaterThan $Today)
    if ($latestDates.Count -eq 0) {
        throw "No deployed Chinese report was found not later than $Today."
    }
    return $latestDates
}

function Assert-TimeBudget {
    param(
        [Parameter(Mandatory = $true)][datetimeoffset]$Deadline,
        [Parameter(Mandatory = $true)][int]$RequiredSeconds,
        [Parameter(Mandatory = $true)][scriptblock]$Clock,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    if (-not (Test-TimeBudget -Deadline $Deadline -RequiredSeconds $RequiredSeconds -Clock $Clock)) {
        throw "Overall deadline budget cannot accommodate $Operation ($RequiredSeconds seconds required)."
    }
}

function Test-TimeBudget {
    param(
        [Parameter(Mandatory = $true)][datetimeoffset]$Deadline,
        [Parameter(Mandatory = $true)][int]$RequiredSeconds,
        [Parameter(Mandatory = $true)][scriptblock]$Clock
    )
    $now = [datetimeoffset](& $Clock)
    return (($Deadline - $now).TotalSeconds -ge $RequiredSeconds)
}

function Remove-TemporaryFile {
    param([string]$Path, [string]$Description)

    if ($null -eq $Path -or -not [System.IO.File]::Exists($Path)) { return }
    try {
        [System.IO.File]::Delete($Path)
    } catch {
        Write-Warning "Sync completed or failed, but could not remove $Description '$Path': $($_.Exception.Message)"
    }
}

function Assert-Briefing {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedDate
    )

    $content = Get-StrictUtf8Text -Path $Path
    if ([string]::IsNullOrWhiteSpace($content)) { throw 'Downloaded briefing is empty.' }
    $frontMatterMatch = [regex]::Match($content, '\A---\r?\n(?<frontMatter>.*?)\r?\n---(?:\r?\n|$)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $frontMatterMatch.Success) {
        throw 'Expected Jekyll front matter is missing from the generated briefing.'
    }
    $frontMatter = $frontMatterMatch.Groups['frontMatter'].Value
    $frontMatterValues = Get-CanonicalFrontMatterValues -FrontMatter $frontMatter
    $bodyStart = $frontMatterMatch.Index + $frontMatterMatch.Length
    $visibleMarkdown = Get-UnfencedMarkdown -Markdown $content.Substring($bodyStart)
    $visibleMarkdown = Remove-InlineCodeSpans -Markdown $visibleMarkdown
    if ($visibleMarkdown -match '(?is)<\s*/?\s*(?:!doctype|html|head|body)\b') {
        throw 'Downloaded content looks like an HTML/error page, not Markdown.'
    }
    $frontMatterDate = Get-RequiredFrontMatterValue -Values $frontMatterValues -Key 'date'
    if ($frontMatterDate -cne $ExpectedDate) {
        throw "Briefing front matter does not contain the expected date $ExpectedDate."
    }
    $frontMatterLanguage = Get-RequiredFrontMatterValue -Values $frontMatterValues -Key 'lang'
    if ($frontMatterLanguage -cne 'zh') {
        throw 'Expected Chinese briefing front matter "lang: zh" is missing.'
    }
    $frontMatterTitle = Get-RequiredFrontMatterValue -Values $frontMatterValues -Key 'title'
    if ($frontMatterTitle -cne 'AI 前沿雷达') {
        throw 'Expected canonical briefing title "AI 前沿雷达" is missing.'
    }
    $generatedAt = Get-RequiredFrontMatterValue -Values $frontMatterValues -Key 'generated_at'
    $parsedTimestamp = [datetimeoffset]::MinValue
    if ($generatedAt -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$' -or -not [datetimeoffset]::TryParse(
        $generatedAt,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$parsedTimestamp
    )) {
        throw 'Expected a UTC ISO-8601 generated_at timestamp in briefing front matter.'
    }
    $sourceVersion = Get-RequiredFrontMatterValue -Values $frontMatterValues -Key 'source_version'
    if ($sourceVersion -cne 'local' -and $sourceVersion -cnotmatch '^[0-9A-Fa-f]{7,64}$') {
        throw 'Expected a safe source_version in briefing front matter.'
    }

    $topThreeHeadings = [regex]::Matches($visibleMarkdown, '(?m)^##\s+今日优先选题 Top 3[ \t]*\r?$')
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
try {
    $startedAt = [datetimeoffset](& $ClockAction)
    $deadline = $startedAt.AddSeconds($OverallDeadlineSeconds)
    $explicitDate = $PSBoundParameters.ContainsKey('Date')
    if (-not [string]::IsNullOrWhiteSpace($SourceFile) -and -not $explicitDate) {
        throw 'Date must be provided when SourceFile is used.'
    }
    if ($explicitDate) {
        $candidateDates = @(Get-IsoDate -Value $Date)
        $today = $null
        $isEvening = $false
        $latestFallbackDates = @()
    } else {
        Assert-SafeRepository -Value $Repository
        $today = Get-IsoDate -Value $Now.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $isEvening = $Now -ge $Now.Date.AddHours(19).AddMinutes(15)
        $latestFallbackDates = @()
        if ($isEvening) {
            $candidateDates = @($today)
        } else {
            Assert-TimeBudget -Deadline $deadline -RequiredSeconds $RequestTimeoutSeconds -Clock $ClockAction -Operation 'remote tree discovery'
            $candidateDates = @(@(Get-RemoteCandidateDates `
                -RequestedRepository $Repository `
                -Today $today `
                -TimeoutSeconds $RequestTimeoutSeconds `
                -TreeProvider $RemoteTreeProvider) | Select-Object -First $FallbackCandidateLimit)
        }
    }

    $vaultInput = [System.IO.Path]::GetFullPath($VaultPath)
    Assert-NoReparsePointsInExistingPath -Path $vaultInput -Description 'VaultPath'
    [System.IO.Directory]::CreateDirectory($vaultInput) | Out-Null
    Assert-NoReparsePointsInExistingPath -Path $vaultInput -Description 'VaultPath'
    $resolvedVault = (Resolve-Path -LiteralPath $vaultInput).ProviderPath
    $destinationInput = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($resolvedVault, 'AI情报日报'))
    Assert-ChildPath -Root $resolvedVault -Candidate $destinationInput -Description 'Destination directory'
    Assert-NoReparsePointsInExistingPath -Path $destinationInput -Description 'Destination directory'
    if (Test-ReparsePoint -Path $destinationInput) {
        throw 'Destination directory is a reparse point; refusing to write through it.'
    }
    [System.IO.Directory]::CreateDirectory($destinationInput) | Out-Null
    $destinationDirectory = (Resolve-Path -LiteralPath $destinationInput).ProviderPath
    Assert-ChildPath -Root $resolvedVault -Candidate $destinationDirectory -Description 'Destination directory'
    Assert-NoReparsePointsInExistingPath -Path $destinationDirectory -Description 'Destination directory'

    $candidateIndex = 0
    while ($candidateIndex -lt $candidateDates.Count) {
        $dateText = $candidateDates[$candidateIndex]
        $destination = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($destinationDirectory, "$dateText.md"))
        Assert-ChildPath -Root $destinationDirectory -Candidate $destination -Description 'Destination file'
        Assert-ChildPath -Root $resolvedVault -Candidate $destination -Description 'Destination file'
        if (Test-ReparsePoint -Path $destination) {
            throw 'Destination file is a reparse point; refusing to replace it.'
        }

        $candidateAttempts = if ($isEvening -and $dateText -ceq $today) { $TodayRetryAttempts } else { 1 }
        $candidateError = $null
        $candidateIsValid = $false
        for ($candidateAttempt = 1; $candidateAttempt -le $candidateAttempts; $candidateAttempt++) {
            if ($isEvening -and $dateText -ceq $today) {
                if (-not (Test-TimeBudget -Deadline $deadline -RequiredSeconds $RequestTimeoutSeconds -Clock $ClockAction)) {
                    $candidateError = [System.Management.Automation.ErrorRecord]::new(
                        [System.TimeoutException]::new('Overall deadline budget cannot accommodate remote tree discovery.'),
                        'OverallDeadline',
                        [System.Management.Automation.ErrorCategory]::OperationTimeout,
                        $null
                    )
                    break
                }
                try {
                    $discoveredDates = @(Get-RemoteCandidateDates `
                        -RequestedRepository $Repository `
                        -Today $today `
                        -TimeoutSeconds $RequestTimeoutSeconds `
                        -TreeProvider $RemoteTreeProvider)
                    $latestFallbackDates = @($discoveredDates | Where-Object { $_ -cne $today } | Select-Object -First $FallbackCandidateLimit)
                } catch {
                    Write-Warning "Remote tree discovery attempt $candidateAttempt failed; retaining the latest fallback list: $($_.Exception.Message)"
                }
            }

            # This protects static or accidental reparse escapes. It is not a defense against a malicious
            # concurrent process swapping filesystem objects between these checks and the final move.
            Assert-NoReparsePointsInExistingPath -Path $vaultInput -Description 'VaultPath'
            Assert-NoReparsePointsInExistingPath -Path $destinationDirectory -Description 'Destination directory'
            $temporaryPath = [System.IO.Path]::Combine($destinationDirectory, ".ai-frontier-radar-$([guid]::NewGuid()).tmp")
            Assert-ChildPath -Root $destinationDirectory -Candidate $temporaryPath -Description 'Temporary file'
            $stream = [System.IO.File]::Open($temporaryPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $stream.Dispose()

            try {
                if ([string]::IsNullOrWhiteSpace($SourceFile)) {
                    Assert-SafeRepository -Value $Repository
                    Assert-TimeBudget -Deadline $deadline -RequiredSeconds $RequestTimeoutSeconds -Clock $ClockAction -Operation "report request for $dateText"
                    & $RemoteContentProvider $Repository $dateText $temporaryPath $RequestTimeoutSeconds
                } else {
                    $resolvedSource = [System.IO.Path]::GetFullPath($SourceFile)
                    if (-not [System.IO.File]::Exists($resolvedSource)) {
                        throw "Local source file does not exist: $SourceFile"
                    }
                    [System.IO.File]::Copy($resolvedSource, $temporaryPath, $true)
                }
                Assert-Briefing -Path $temporaryPath -ExpectedDate $dateText
                $candidateIsValid = $true
                break
            } catch {
                $candidateError = $_
                Remove-TemporaryFile -Path $temporaryPath -Description 'temporary download file'
                $temporaryPath = $null
                if ($candidateAttempt -lt $candidateAttempts) {
                    if (-not (Test-TimeBudget -Deadline $deadline -RequiredSeconds $TodayRetryDelaySeconds -Clock $ClockAction)) {
                        break
                    }
                    & $SleepAction $TodayRetryDelaySeconds
                }
            }
        }
        if (-not $candidateIsValid) {
            if ($explicitDate) { throw $candidateError }
            Write-Warning "Skipping invalid or unavailable deployed report for ${dateText}: $($candidateError.Exception.Message)"
            if ($isEvening -and $dateText -ceq $today) {
                $candidateDates = @($today) + $latestFallbackDates
            }
            $candidateIndex++
            continue
        }

        Assert-NoReparsePointsInExistingPath -Path $vaultInput -Description 'VaultPath'
        Assert-NoReparsePointsInExistingPath -Path $destinationDirectory -Description 'Destination directory'
        if (Test-ReparsePoint -Path $destination) { throw 'Destination file is a reparse point; refusing to replace it.' }
        if ([System.IO.File]::Exists($destination)) {
            $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            $temporaryHash = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash
            if ($destinationHash -eq $temporaryHash) {
                Write-Output "Unchanged: $destination"
                return
            }
            Assert-NoReparsePointsInExistingPath -Path $vaultInput -Description 'VaultPath'
            Assert-NoReparsePointsInExistingPath -Path $destinationDirectory -Description 'Destination directory'
            if (Test-ReparsePoint -Path $destination) { throw 'Destination file is a reparse point; refusing to replace it.' }
            [System.IO.File]::Move($temporaryPath, $destination, $true)
        } else {
            Assert-NoReparsePointsInExistingPath -Path $vaultInput -Description 'VaultPath'
            Assert-NoReparsePointsInExistingPath -Path $destinationDirectory -Description 'Destination directory'
            [System.IO.File]::Move($temporaryPath, $destination)
        }
        Write-Output "Synced: $destination"
        return
    }
    throw 'No valid deployed Chinese report could be synchronized.'
} finally {
    Remove-TemporaryFile -Path $temporaryPath -Description 'temporary download file'
}
