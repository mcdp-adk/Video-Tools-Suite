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
        Write-Host "Downloading video..." -ForegroundColor Cyan
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

# Download subtitles to project folder (core function used by workflow and menus)
function Invoke-SubtitleDownload {
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
        Write-Host "Downloading subtitles..." -ForegroundColor Cyan
    }

    # Manual subtitles
    $manualSubArgs = $cookieArgs + $commonArgs + @(
        "--write-subs",
        "--sub-langs", "en,zh,ja",
        "--skip-download",
        "-o", "$ProjectDir\original.%(ext)s",
        $url
    )
    & yt-dlp $manualSubArgs 2>&1 | Out-Null

    # Auto-generated subtitles
    $autoSubArgs = $cookieArgs + $commonArgs + @(
        "--write-auto-subs",
        "--sub-langs", "en,zh,ja",
        "--skip-download",
        "-o", "$ProjectDir\original.auto.%(ext)s",
        $url
    )
    & yt-dlp $autoSubArgs 2>&1 | Out-Null

    # Count downloaded files
    $subFiles = @()
    $subFiles += Get-ChildItem -LiteralPath $ProjectDir -Filter "*.vtt" -ErrorAction SilentlyContinue
    $subFiles += Get-ChildItem -LiteralPath $ProjectDir -Filter "*.srt" -ErrorAction SilentlyContinue

    return $subFiles.Count
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
            Write-Host "Starting download..." -ForegroundColor Yellow

            # Create project folder
            $project = New-VideoProjectDir -Url $cliUrl
            Write-Host "Project: $($project.ProjectName)" -ForegroundColor Cyan

            # Download video
            $videoPath = Invoke-VideoDownload -Url $cliUrl -ProjectDir $project.ProjectDir
            if ($videoPath) {
                Write-Host "Video downloaded: $(Split-Path -Leaf $videoPath)" -ForegroundColor Green
            }

            # Download subtitles
            $subCount = Invoke-SubtitleDownload -Url $cliUrl -ProjectDir $project.ProjectDir
            if ($subCount -gt 0) {
                Write-Host "Subtitles downloaded: $subCount files" -ForegroundColor Green
            } else {
                Write-Host "No subtitles available" -ForegroundColor Yellow
            }

            Write-Host "Success! Video downloaded to: $($project.ProjectDir)" -ForegroundColor Green
        } catch {
            Write-Host "Error: $_" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Usage: download.bat <url>" -ForegroundColor Yellow
        Write-Host "Supports 1800+ sites via yt-dlp (YouTube, Bilibili, Twitter, etc.)" -ForegroundColor Cyan
        Write-Host "Examples:" -ForegroundColor Gray
        Write-Host "  download.bat https://www.youtube.com/watch?v=dQw4w9WgXcQ" -ForegroundColor Gray
        Write-Host "  download.bat https://www.youtube.com/live/XXXXXXXXXXX" -ForegroundColor Gray
        Write-Host "  download.bat https://www.bilibili.com/video/BVXXXXXXXXX" -ForegroundColor Gray
        Write-Host "  download.bat dQw4w9WgXcQ  (YouTube video ID)" -ForegroundColor Gray
        exit 1
    }
}

#endregion
