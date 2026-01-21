# Command-line parameter (must be first for dot sourcing compatibility)
param([string]$InputUrl)

# Configuration
$script:YtdlCookieFile = ""
$script:YtdlOutputDir = "$PSScriptRoot\..\output"

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

# Function interface for TUI integration: Download video with subtitles
function Invoke-YouTubeDownloader {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputUrl,
        [switch]$UseProjectFolder
    )

    Test-YtDlpAvailable | Out-Null

    $url = Get-NormalizedUrl -Url $InputUrl

    # Ensure output directory exists
    if (-not (Test-Path $script:YtdlOutputDir)) {
        New-Item -ItemType Directory -Path $script:YtdlOutputDir -Force | Out-Null
    }

    $cookieArgs = Get-CookieArgs
    $commonArgs = Get-CommonYtDlpArgs

    # Determine output path based on mode
    if ($UseProjectFolder) {
        # New project folder structure
        $project = New-VideoProjectDir -Url $url
        $outputDir = $project.ProjectDir
        $videoOutputTemplate = "$outputDir\video.%(ext)s"
        $manualSubTemplate = "$outputDir\original.%(ext)s"
        $autoSubTemplate = "$outputDir\original.auto.%(ext)s"

        Write-Host "Project: $($project.ProjectName)" -ForegroundColor Cyan
    }
    else {
        # Legacy flat structure
        $outputDir = $script:YtdlOutputDir
        $videoOutputTemplate = "$outputDir\%(title)s.%(ext)s"
        $manualSubTemplate = "$outputDir\%(title)s.manual-sub.%(ext)s"
        $autoSubTemplate = "$outputDir\%(title)s.auto-generated-sub.%(ext)s"
    }

    # Download video with embedded subtitles
    $videoArgs = $cookieArgs + $commonArgs + @(
        "--embed-thumbnail",
        "--embed-metadata",
        "--embed-subs",
        "--sub-langs", "all",
        "--no-write-subs",
        "-o", $videoOutputTemplate,
        $url
    )
    & yt-dlp $videoArgs | Out-Host

    if ($LASTEXITCODE -ne 0) {
        throw "yt-dlp failed with exit code $LASTEXITCODE"
    }

    # Download manual subtitle files
    Write-Host "Downloading manual subtitle files..." -ForegroundColor Yellow
    $manualSubArgs = $cookieArgs + $commonArgs + @(
        "--write-subs",
        "--sub-langs", "en,zh,ja",
        "--skip-download",
        "-o", $manualSubTemplate,
        $url
    )
    & yt-dlp $manualSubArgs | Out-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Manual subtitle download failed" -ForegroundColor Yellow
    } else {
        Write-Host "Manual subtitles downloaded" -ForegroundColor Green
    }

    # Download auto-generated subtitle files
    Write-Host "Downloading auto-generated subtitle files..." -ForegroundColor Yellow
    $autoSubArgs = $cookieArgs + $commonArgs + @(
        "--write-auto-subs",
        "--sub-langs", "en,zh,ja",
        "--skip-download",
        "-o", $autoSubTemplate,
        $url
    )
    & yt-dlp $autoSubArgs | Out-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Auto-generated subtitle download failed" -ForegroundColor Yellow
    } else {
        Write-Host "Auto-generated subtitles downloaded" -ForegroundColor Green
    }

    return $outputDir
}

# Function interface for TUI integration: Download subtitles only
function Invoke-YouTubeSubtitleDownloader {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputUrl,
        [switch]$UseProjectFolder
    )

    Test-YtDlpAvailable | Out-Null

    $url = Get-NormalizedUrl -Url $InputUrl

    # Ensure output directory exists
    if (-not (Test-Path $script:YtdlOutputDir)) {
        New-Item -ItemType Directory -Path $script:YtdlOutputDir -Force | Out-Null
    }

    $cookieArgs = Get-CookieArgs
    $commonArgs = Get-CommonYtDlpArgs

    # Determine output path based on mode
    if ($UseProjectFolder) {
        $project = New-VideoProjectDir -Url $url
        $outputDir = $project.ProjectDir
        $manualSubTemplate = "$outputDir\original.%(ext)s"
        $autoSubTemplate = "$outputDir\original.auto.%(ext)s"

        Write-Host "Project: $($project.ProjectName)" -ForegroundColor Cyan
    }
    else {
        $outputDir = $script:YtdlOutputDir
        $manualSubTemplate = "$outputDir\%(title)s.%(ext)s"
        $autoSubTemplate = "$outputDir\%(title)s.auto.%(ext)s"
    }

    # Download manual subtitles
    Write-Host "Downloading manual subtitles..." -ForegroundColor Yellow
    $manualSubArgs = $cookieArgs + $commonArgs + @(
        "--write-subs",
        "--sub-langs", "en,zh,ja",
        "--skip-download",
        "-o", $manualSubTemplate,
        $url
    )
    & yt-dlp $manualSubArgs | Out-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Manual subtitle download failed" -ForegroundColor Yellow
    } else {
        Write-Host "Manual subtitles downloaded" -ForegroundColor Green
    }

    # Download auto-generated subtitles
    Write-Host "Downloading auto-generated subtitles..." -ForegroundColor Yellow
    $autoSubArgs = $cookieArgs + $commonArgs + @(
        "--write-auto-subs",
        "--sub-langs", "en,zh,ja",
        "--skip-download",
        "-o", $autoSubTemplate,
        $url
    )
    & yt-dlp $autoSubArgs | Out-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Auto-generated subtitle download failed" -ForegroundColor Yellow
    } else {
        Write-Host "Auto-generated subtitles downloaded" -ForegroundColor Green
    }

    return $outputDir
}

#endregion

#region Command-line Interface

if ($InputUrl) {
    try {
        $url = Get-NormalizedUrl -Url $InputUrl

        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host "URL: $url" -ForegroundColor White
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host "Starting download..." -ForegroundColor Yellow

        $result = Invoke-YouTubeDownloader -InputUrl $InputUrl

        Write-Host "Success! Video downloaded to: $result" -ForegroundColor Green
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        exit 1
    }
} elseif ($MyInvocation.InvocationName -ne '.') {
    Write-Host "Usage: download.bat <url>" -ForegroundColor Yellow
    Write-Host "Supports 1800+ sites via yt-dlp (YouTube, Bilibili, Twitter, etc.)" -ForegroundColor Cyan
    Write-Host "Examples:" -ForegroundColor Gray
    Write-Host "  download.bat https://www.youtube.com/watch?v=dQw4w9WgXcQ" -ForegroundColor Gray
    Write-Host "  download.bat https://www.youtube.com/live/XXXXXXXXXXX" -ForegroundColor Gray
    Write-Host "  download.bat https://www.bilibili.com/video/BVXXXXXXXXX" -ForegroundColor Gray
    Write-Host "  download.bat dQw4w9WgXcQ  (YouTube video ID)" -ForegroundColor Gray
    exit 1
}

#endregion
