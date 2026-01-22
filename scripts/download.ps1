# Configuration
$script:YtdlCookieFile = ""
$script:YtdlOutputDir = "$PSScriptRoot\..\output"

# Import utilities if not already loaded
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}

#region Helper Functions

# Check yt-dlp availability
function Test-YtDlpAvailable {
    try {
        $null = Get-Command yt-dlp -ErrorAction Stop
        return $true
    } catch {
        throw "yt-dlp is not installed or not in PATH"
    }
}

# Normalize URL input
# Supports direct URLs (any yt-dlp supported site) or YouTube video IDs
function Get-NormalizedUrl {
    param([string]$Url)

    # If it looks like a URL, use it directly
    if ($Url -match '^https?://') {
        return $Url
    }
    # If it's an 11-character alphanumeric string, treat as YouTube video ID
    if ($Url -match '^[a-zA-Z0-9_-]{11}$') {
        return "https://www.youtube.com/watch?v=$Url"
    }
    # Otherwise, pass through and let yt-dlp handle it
    return $Url
}

# Extract video ID from various URL formats
function Get-VideoId {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url
    )

    # YouTube patterns
    if ($Url -match 'youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})') {
        return $Matches[1]
    }
    if ($Url -match 'youtube\.com/live/([a-zA-Z0-9_-]{11})') {
        return $Matches[1]
    }
    if ($Url -match 'youtu\.be/([a-zA-Z0-9_-]{11})') {
        return $Matches[1]
    }
    if ($Url -match 'youtube\.com/embed/([a-zA-Z0-9_-]{11})') {
        return $Matches[1]
    }

    # Bilibili patterns
    if ($Url -match 'bilibili\.com/video/(BV[a-zA-Z0-9]+)') {
        return $Matches[1]
    }
    if ($Url -match 'bilibili\.com/video/av(\d+)') {
        return "av$($Matches[1])"
    }
    if ($Url -match 'b23\.tv/([a-zA-Z0-9]+)') {
        return $Matches[1]
    }

    # Twitter/X patterns
    if ($Url -match 'twitter\.com/.+/status/(\d+)') {
        return "tw$($Matches[1])"
    }
    if ($Url -match 'x\.com/.+/status/(\d+)') {
        return "x$($Matches[1])"
    }

    # If it's already just an ID (11 chars for YouTube)
    if ($Url -match '^[a-zA-Z0-9_-]{11}$') {
        return $Url
    }

    # Generate hash for unknown URLs
    $hash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.MD5]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($Url)
        )
    ).Replace("-", "").Substring(0, 11)

    return $hash
}

# Get cookie arguments if cookie file exists
function Get-CookieArgs {
    if ($script:YtdlCookieFile -and (Test-Path $script:YtdlCookieFile)) {
        return @("--cookies", $script:YtdlCookieFile)
    }
    return @()
}

# Get video subtitle information using yt-dlp --dump-json
# Returns: VideoLanguage, ManualSubtitles, AutoSubtitles, HasTargetLanguageSub
function Get-VideoSubtitleInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [string]$TargetLanguage = ""
    )

    $cookieArgs = Get-CookieArgs
    $commonArgs = Get-CommonYtDlpArgs

    # Get video metadata as JSON
    $jsonArgs = $commonArgs + $cookieArgs + @("--dump-json", "--skip-download", $Url)
    $jsonOutput = & yt-dlp @jsonArgs 2>$null

    if ($LASTEXITCODE -ne 0 -or -not $jsonOutput) {
        return @{ Success = $false; Error = "Failed to get video metadata" }
    }

    try {
        $metadata = $jsonOutput | ConvertFrom-Json
    } catch {
        return @{ Success = $false; Error = "Failed to parse video metadata" }
    }

    # Extract subtitle language codes
    $manualSubs = @()
    $autoSubs = @()
    $videoLanguage = $null

    if ($metadata.subtitles) {
        $manualSubs = @($metadata.subtitles.PSObject.Properties.Name)
    }

    if ($metadata.automatic_captions) {
        $autoSubs = @($metadata.automatic_captions.PSObject.Properties.Name)
        # Detect video language from *-orig suffix
        $origLang = $autoSubs | Where-Object { $_ -match '-orig$' } | Select-Object -First 1
        if ($origLang) {
            $videoLanguage = $origLang -replace '-orig$', ''
        }
    }

    # Fallback: use metadata.language field if no *-orig found
    if (-not $videoLanguage -and $metadata.language) {
        $videoLanguage = $metadata.language
    }

    # Check if target language subtitle exists
    $hasTargetLanguageSub = $false
    if ($TargetLanguage) {
        $targetBase = $TargetLanguage -replace '-Hans$', '' -replace '-Hant$', ''
        $hasTargetLanguageSub = [bool]($manualSubs | Where-Object {
            $_ -eq $TargetLanguage -or $_ -eq $targetBase -or $_ -match "^$targetBase"
        })
    }

    return @{
        Success = $true
        VideoLanguage = $videoLanguage
        ManualSubtitles = $manualSubs
        AutoSubtitles = $autoSubs
        HasTargetLanguageSub = $hasTargetLanguageSub
        Title = $metadata.title
        Duration = $metadata.duration
    }
}

# Format filename to match yt-dlp --restrict-filenames behavior
function Format-RestrictedFilename {
    param([string]$Text)

    # Simulate yt-dlp --restrict-filenames:
    # 1. Replace spaces with underscores
    # 2. Keep only ASCII letters, numbers, underscores, hyphens, dots
    # 3. Remove consecutive underscores
    $result = $Text -replace '\s+', '_'
    $result = $result -replace '[^\w\-.]', '_'
    $result = $result -replace '_+', '_'
    $result = $result.Trim('_')
    return $result
}

# Get video title using yt-dlp (with cookies support)
function Get-VideoTitle {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url
    )

    $cookieArgs = Get-CookieArgs
    $commonArgs = Get-CommonYtDlpArgs

    try {
        $ytdlpArgs = $commonArgs + $cookieArgs + @("--print", "%(title)s", $Url)
        $title = & yt-dlp @ytdlpArgs 2>$null
        if ($LASTEXITCODE -eq 0 -and $title) {
            return Format-RestrictedFilename -Text $title.Trim()
        }
    }
    catch {}

    # Fallback: use video ID instead of generic "video"
    Write-Warning "Could not get video title, using video ID as fallback"
    $videoId = Get-VideoId -Url $Url
    return $videoId
}

# Extract video URLs from a playlist using yt-dlp
function Get-PlaylistVideoUrls {
    param(
        [Parameter(Mandatory=$true)]
        [string]$PlaylistUrl
    )

    $cookieArgs = Get-CookieArgs
    $ytdlpArgs = $cookieArgs + @(
        "--flat-playlist",
        "--print", "url",
        $PlaylistUrl
    )

    $urls = & yt-dlp @ytdlpArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract playlist URLs"
    }

    return @($urls | Where-Object { $_ -match '^https?://' })
}

# Get common yt-dlp arguments
function Get-CommonYtDlpArgs {
    return @(
        "--no-warnings",
        "--no-progress",
        "--console-title",
        "--restrict-filenames",
        "--compat-options", "no-live-chat"
    )
}

# Create project directory for a video
function New-VideoProjectDir {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url
    )

    $videoId = Get-VideoId -Url $Url
    $videoTitle = Get-VideoTitle -Url $Url

    $projectName = "[$videoId]$videoTitle"
    $projectDir = Join-Path $script:YtdlOutputDir $projectName

    if (-not (Test-Path $projectDir)) {
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
    }

    return @{
        ProjectDir = $projectDir
        VideoId = $videoId
        VideoTitle = $videoTitle
        ProjectName = $projectName
    }
}

#endregion

#region Main Functions

# Download video to project folder (core function used by workflow and menus)
function Invoke-VideoDownload {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [Parameter(Mandatory=$true)]
        [string]$ProjectDir,
        [switch]$Quiet
    )

    Test-YtDlpAvailable | Out-Null

    $url = Get-NormalizedUrl -Url $Url
    $cookieArgs = Get-CookieArgs
    $commonArgs = Get-CommonYtDlpArgs

    if (-not $Quiet) {
        Show-Info "Downloading video..."
    }

    $videoArgs = $cookieArgs + $commonArgs + @(
        "--embed-thumbnail",
        "--embed-metadata",
        "--embed-subs",
        "--sub-langs", "all",
        "-o", "$ProjectDir\video.%(ext)s",
        $url
    )
    & yt-dlp $videoArgs 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Video download failed"
    }

    # Find downloaded video
    $videoFile = Get-ChildItem -LiteralPath $ProjectDir -Filter "video.*" |
        Where-Object { $_.Extension -match '\.(mp4|mkv|webm|mov|avi)$' } |
        Select-Object -First 1

    if ($videoFile) {
        return $videoFile.FullName
    }
    return $null
}

# Download subtitles to project folder with smart selection
# Priority: 1. Target lang manual sub (skip) → 2. Video lang manual sub → 3. Video lang auto sub (*-orig)
# Returns: @{ SubtitleFile, VideoLanguage, SubtitleType, SkipTranslation }
function Invoke-SubtitleDownload {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [Parameter(Mandatory=$true)]
        [string]$ProjectDir,
        [string]$TargetLanguage = "",
        [switch]$Quiet
    )

    Test-YtDlpAvailable | Out-Null

    $url = Get-NormalizedUrl -Url $Url
    $cookieArgs = Get-CookieArgs
    $commonArgs = Get-CommonYtDlpArgs

    # Get subtitle info
    if (-not $Quiet) {
        Show-Info "  Analyzing subtitles..."
    }

    $subInfo = Get-VideoSubtitleInfo -Url $Url -TargetLanguage $TargetLanguage
    if (-not $subInfo.Success) {
        if (-not $Quiet) {
            Show-Warning "    Warning: $($subInfo.Error)"
        }
        return @{
            SubtitleFile = $null
            VideoLanguage = $null
            SubtitleType = "none"
            SkipTranslation = $true
        }
    }

    $videoLang = $subInfo.VideoLanguage

    if (-not $Quiet) {
        Show-Detail "    Video language: $(if ($videoLang) { $videoLang } else { 'unknown' })"
    }

    # Priority 1: Check if target language manual subtitle exists
    if ($TargetLanguage -and $subInfo.HasTargetLanguageSub) {
        if (-not $Quiet) {
            Show-Success "    Found target language ($TargetLanguage) manual subtitle - already embedded in video"
        }
        return @{
            SubtitleFile = $null
            VideoLanguage = $videoLang
            SubtitleType = "embedded"
            SkipTranslation = $true
        }
    }

    # Priority 2: Video language manual subtitle
    if ($videoLang -and ($subInfo.ManualSubtitles -contains $videoLang)) {
        if (-not $Quiet) {
            Show-Info "    Downloading manual subtitle ($videoLang)..."
        }

        $subArgs = $cookieArgs + $commonArgs + @(
            "--write-subs",
            "--sub-langs", $videoLang,
            "--skip-download",
            "-o", "$ProjectDir\original.%(ext)s",
            $url
        )
        & yt-dlp @subArgs 2>&1 | Out-Null

        $subFile = Get-ChildItem -LiteralPath $ProjectDir -Filter "original.$videoLang.*" |
            Where-Object { $_.Extension -match '\.(vtt|srt)$' } |
            Select-Object -First 1

        if ($subFile) {
            return @{
                SubtitleFile = $subFile.FullName
                VideoLanguage = $videoLang
                SubtitleType = "manual"
                SkipTranslation = $false
            }
        }
    }

    # Priority 3: Video language auto subtitle (*-orig)
    $origKey = "$videoLang-orig"
    if ($videoLang -and ($subInfo.AutoSubtitles -contains $origKey)) {
        if (-not $Quiet) {
            Show-Info "    Downloading auto-generated subtitle ($origKey)..."
        }

        $subArgs = $cookieArgs + $commonArgs + @(
            "--write-auto-subs",
            "--sub-langs", $origKey,
            "--skip-download",
            "-o", "$ProjectDir\original.auto.%(ext)s",
            $url
        )
        & yt-dlp @subArgs 2>&1 | Out-Null

        $subFile = Get-ChildItem -LiteralPath $ProjectDir -Filter "original.auto.$origKey.*" |
            Where-Object { $_.Extension -match '\.(vtt|srt)$' } |
            Select-Object -First 1

        if ($subFile) {
            return @{
                SubtitleFile = $subFile.FullName
                VideoLanguage = $videoLang
                SubtitleType = "auto"
                SkipTranslation = $false
            }
        }
    }

    # No suitable subtitle found
    if (-not $Quiet) {
        Show-Warning "    Warning: No suitable subtitle found for this video"
    }

    return @{
        SubtitleFile = $null
        VideoLanguage = $videoLang
        SubtitleType = "none"
        SkipTranslation = $true
    }
}

#endregion

#region Command-line Interface

if ($MyInvocation.InvocationName -ne '.') {
    $cliUrl = if ($args.Count -ge 1) { $args[0] } else { $null }
    if ($cliUrl) {
        try {
            $url = Get-NormalizedUrl -Url $cliUrl

            Write-Host "================================================" -ForegroundColor Cyan
            Write-Host "URL: $url" -ForegroundColor White
            Write-Host "================================================" -ForegroundColor Cyan
            Show-Step "Starting download..."

            # Create project folder
            $project = New-VideoProjectDir -Url $cliUrl
            Show-Info "Project: $($project.ProjectName)"

            # Download video
            $videoPath = Invoke-VideoDownload -Url $cliUrl -ProjectDir $project.ProjectDir
            if ($videoPath) {
                Show-Success "Video downloaded: $(Split-Path -Leaf $videoPath)"
            }

            # Download subtitles (smart selection)
            $subResult = Invoke-SubtitleDownload -Url $cliUrl -ProjectDir $project.ProjectDir
            if ($subResult.SubtitleFile) {
                Show-Success "Subtitle downloaded: $(Split-Path -Leaf $subResult.SubtitleFile) ($($subResult.SubtitleType))"
            } elseif ($subResult.SubtitleType -eq "embedded") {
                Show-Success "Subtitles: Target language already embedded in video"
            } else {
                Show-Warning "No subtitles available"
            }

            Show-Success "Success! Video downloaded to: $($project.ProjectDir)"
        } catch {
            Show-Error "Error: $_"
            exit 1
        }
    } else {
        Show-Warning "Usage: download.bat <url>"
        Show-Info "Supports 1800+ sites via yt-dlp (YouTube, Bilibili, Twitter, etc.)"
        Show-Hint "Examples:"
        Show-Hint "  download.bat https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        Show-Hint "  download.bat https://www.youtube.com/live/XXXXXXXXXXX"
        Show-Hint "  download.bat https://www.bilibili.com/video/BVXXXXXXXXX"
        Show-Hint "  download.bat dQw4w9WgXcQ  (YouTube video ID)"
        exit 1
    }
}

#endregion
