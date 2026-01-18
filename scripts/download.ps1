# Command-line parameter (must be first for dot sourcing compatibility)
param([string]$InputUrl)

# Configuration
$script:YtdlCookieFile = ""
$script:YtdlOutputDir = "$PSScriptRoot\..\output"

# Helper function: Check yt-dlp availability
function Test-YtDlpAvailable {
    try {
        $null = Get-Command yt-dlp -ErrorAction Stop
        return $true
    } catch {
        throw "yt-dlp is not installed or not in PATH"
    }
}

# Helper function: Normalize URL input
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

# Helper function: Get cookie arguments if cookie file exists
function Get-CookieArgs {
    if ($script:YtdlCookieFile -and (Test-Path $script:YtdlCookieFile)) {
        return @("--cookies", $script:YtdlCookieFile)
    }
    return @()
}

# Helper function: Get common yt-dlp arguments
function Get-CommonYtDlpArgs {
    return @(
        "--no-warnings",
        "--no-progress",
        "--console-title",
        "--restrict-filenames",
        "--compat-options", "no-live-chat"
    )
}

# Function interface for TUI integration: Download video with subtitles
function Invoke-YouTubeDownloader {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputUrl
    )

    Test-YtDlpAvailable | Out-Null

    $url = Get-NormalizedUrl -Url $InputUrl

    # Ensure output directory exists
    if (-not (Test-Path $script:YtdlOutputDir)) {
        New-Item -ItemType Directory -Path $script:YtdlOutputDir -Force | Out-Null
    }

    $cookieArgs = Get-CookieArgs
    $commonArgs = Get-CommonYtDlpArgs

    # Download video with embedded subtitles
    $videoArgs = $cookieArgs + $commonArgs + @(
        "--embed-thumbnail",
        "--embed-metadata",
        "--embed-subs",
        "--sub-langs", "all",
        "--no-write-subs",
        "-o", "$script:YtdlOutputDir\%(title)s.%(ext)s",
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
        "--skip-download",
        "-o", "$script:YtdlOutputDir\%(title)s.manual-sub.%(ext)s",
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
        "--skip-download",
        "-o", "$script:YtdlOutputDir\%(title)s.auto-generated-sub.%(ext)s",
        $url
    )
    & yt-dlp $autoSubArgs | Out-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Auto-generated subtitle download failed" -ForegroundColor Yellow
    } else {
        Write-Host "Auto-generated subtitles downloaded" -ForegroundColor Green
    }

    return $script:YtdlOutputDir
}

# Function interface for TUI integration: Download subtitles only
function Invoke-YouTubeSubtitleDownloader {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputUrl
    )

    Test-YtDlpAvailable | Out-Null

    $url = Get-NormalizedUrl -Url $InputUrl

    # Ensure output directory exists
    if (-not (Test-Path $script:YtdlOutputDir)) {
        New-Item -ItemType Directory -Path $script:YtdlOutputDir -Force | Out-Null
    }

    $cookieArgs = Get-CookieArgs
    $commonArgs = Get-CommonYtDlpArgs

    # Download manual subtitles
    Write-Host "Downloading manual subtitles..." -ForegroundColor Yellow
    $manualSubArgs = $cookieArgs + $commonArgs + @(
        "--write-subs",
        "--skip-download",
        "-o", "$script:YtdlOutputDir\%(title)s.%(ext)s",
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
        "--skip-download",
        "-o", "$script:YtdlOutputDir\%(title)s.auto.%(ext)s",
        $url
    )
    & yt-dlp $autoSubArgs | Out-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Auto-generated subtitle download failed" -ForegroundColor Yellow
    } else {
        Write-Host "Auto-generated subtitles downloaded" -ForegroundColor Green
    }

    return $script:YtdlOutputDir
}

# Command-line interface (when script is called directly)
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
