# Command-line parameter (must be first for dot sourcing compatibility)
param([string]$InputUrl)

# Full workflow module
# Handles complete pipeline: download -> select subtitle -> translate -> mux

# Dot source dependencies if not already loaded
if (-not (Get-Command "Invoke-YouTubeDownloader" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\download.ps1"
}
if (-not (Get-Command "Import-SubtitleFile" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\subtitle-utils.ps1"
}
if (-not (Get-Command "Invoke-SubtitleTranslator" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\translate.ps1"
}
if (-not (Get-Command "Invoke-SubtitleMuxer" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\mux.ps1"
}
if (-not (Get-Command "Invoke-TranscriptGenerator" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\transcript.ps1"
}

# Configuration
$script:WorkflowOutputDir = "$PSScriptRoot\..\output"

#region Subtitle Selection

# Find and select the best subtitle file from a project directory
function Select-BestSubtitle {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectDir,
        [string]$PreferredLanguage = "en"
    )

    # Get all subtitle files (use -LiteralPath to handle brackets in path)
    $subtitleFiles = @()
    $subtitleFiles += Get-ChildItem -LiteralPath $ProjectDir -Filter "*.vtt" -ErrorAction SilentlyContinue
    $subtitleFiles += Get-ChildItem -LiteralPath $ProjectDir -Filter "*.srt" -ErrorAction SilentlyContinue

    if ($subtitleFiles.Count -eq 0) {
        return $null
    }

    # Categorize subtitles
    $manualSubs = $subtitleFiles | Where-Object { $_.Name -notmatch '\.auto' -and $_.Name -notmatch 'auto-generated' }
    $autoSubs = $subtitleFiles | Where-Object { $_.Name -match '\.auto' -or $_.Name -match 'auto-generated' }

    # Prefer manual subtitles
    $candidates = if ($manualSubs.Count -gt 0) { $manualSubs } else { $autoSubs }

    # Try to find preferred language
    foreach ($sub in $candidates) {
        if ($sub.Name -match "\.$PreferredLanguage\." -or $sub.Name -match "\.($PreferredLanguage)-") {
            return $sub.FullName
        }
    }

    # Try common English patterns
    foreach ($sub in $candidates) {
        if ($sub.Name -match '\.en\.' -or $sub.Name -match '\.en-' -or $sub.Name -match '\.eng\.') {
            return $sub.FullName
        }
    }

    # Return first available
    return $candidates[0].FullName
}

#endregion

#region Full Workflow

# Main workflow function
function Invoke-FullWorkflow {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputUrl,
        [switch]$SkipDownload,
        [switch]$SkipTranslate,
        [switch]$SkipMux,
        [switch]$GenerateTranscript,
        [string]$ExistingProjectDir = "",
        [switch]$ShowHeader
    )

    if ($ShowHeader) {
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host "                  All-in-One Workflow" -ForegroundColor Yellow
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host ""
    }

    # Save original window title for progress display
    $originalTitle = $Host.UI.RawUI.WindowTitle

    # Ensure output directory exists
    if (-not (Test-Path $script:WorkflowOutputDir)) {
        New-Item -ItemType Directory -Path $script:WorkflowOutputDir -Force | Out-Null
    }

    $projectDir = $ExistingProjectDir
    $videoPath = ""
    $subtitlePath = ""

    #region Step 1: Download
    if (-not $SkipDownload -and -not $ExistingProjectDir) {
        $Host.UI.RawUI.WindowTitle = "VTS: Step 1/4 - Downloading..."
        Write-Host "[Step 1/4] Downloading video and subtitles..." -ForegroundColor Yellow

        # Get video ID and title
        $videoId = Get-VideoId -Url $InputUrl
        Write-Host "  Video ID: $videoId" -ForegroundColor Gray

        $videoTitle = Get-VideoTitle -Url $InputUrl
        Write-Host "  Title: $videoTitle" -ForegroundColor Gray

        # Create project directory
        $projectName = "[$videoId]$videoTitle"
        $projectDir = Join-Path $script:WorkflowOutputDir $projectName

        if (-not (Test-Path $projectDir)) {
            New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        }

        Write-Host "  Project: $projectDir" -ForegroundColor Gray

        # Download video
        $url = Get-NormalizedUrl -Url $InputUrl
        $cookieArgs = Get-CookieArgs
        $commonArgs = Get-CommonYtDlpArgs

        Write-Host "  Downloading video..." -ForegroundColor Cyan
        $videoArgs = $cookieArgs + $commonArgs + @(
            "--embed-thumbnail",
            "--embed-metadata",
            "-o", "$projectDir\video.%(ext)s",
            $url
        )
        & yt-dlp $videoArgs 2>&1 | Out-Host

        if ($LASTEXITCODE -ne 0) {
            throw "Video download failed"
        }

        # Find downloaded video
        $videoFile = Get-ChildItem -LiteralPath $projectDir -Filter "video.*" | Where-Object { $_.Extension -match '\.(mp4|mkv|webm|mov|avi)$' } | Select-Object -First 1
        if ($videoFile) {
            $videoPath = $videoFile.FullName
            Write-Host "  Video: $($videoFile.Name)" -ForegroundColor Green
        }

        # Download subtitles
        Write-Host "  Downloading subtitles..." -ForegroundColor Cyan

        # Manual subtitles
        $manualSubArgs = $cookieArgs + $commonArgs + @(
            "--write-subs",
            "--sub-langs", "en,zh,ja",
            "--skip-download",
            "-o", "$projectDir\original.%(ext)s",
            $url
        )
        & yt-dlp $manualSubArgs 2>&1 | Out-Null

        # Auto-generated subtitles
        $autoSubArgs = $cookieArgs + $commonArgs + @(
            "--write-auto-subs",
            "--sub-langs", "en,zh,ja",
            "--skip-download",
            "-o", "$projectDir\original.auto.%(ext)s",
            $url
        )
        & yt-dlp $autoSubArgs 2>&1 | Out-Null

        # Check subtitle count (use -LiteralPath to handle brackets in path)
        $subFiles = @()
        $subFiles += Get-ChildItem -LiteralPath $projectDir -Filter "*.vtt" -ErrorAction SilentlyContinue
        $subFiles += Get-ChildItem -LiteralPath $projectDir -Filter "*.srt" -ErrorAction SilentlyContinue
        $subCount = $subFiles.Count
        if ($subCount -gt 0) {
            Write-Host "  Subtitles downloaded ($subCount files)" -ForegroundColor Green
        } else {
            Write-Host "  No subtitles available for this video" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[Step 1/4] Skipping download (using existing files)" -ForegroundColor DarkGray

        if ($ExistingProjectDir) {
            $projectDir = $ExistingProjectDir
        }

        # Find existing video
        $videoFile = Get-ChildItem -Path $projectDir -Filter "video.*" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '\.(mp4|mkv|webm|mov|avi)$' } | Select-Object -First 1
        if ($videoFile) {
            $videoPath = $videoFile.FullName
        }
    }

    #endregion

    #region Step 2: Select Subtitle
    $Host.UI.RawUI.WindowTitle = "VTS: Step 2/4 - Selecting subtitle..."
    Write-Host ""
    Write-Host "[Step 2/4] Selecting best subtitle..." -ForegroundColor Yellow

    $subtitlePath = Select-BestSubtitle -ProjectDir $projectDir -PreferredLanguage "en"

    if (-not $subtitlePath) {
        Write-Host "  No subtitle files found" -ForegroundColor Red
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  1. This video may not have subtitles available" -ForegroundColor Gray
        Write-Host "  2. Place a .vtt or .srt file in: $projectDir" -ForegroundColor Gray
        Write-Host "  3. Re-run workflow after adding subtitles" -ForegroundColor Gray
        throw "No subtitle files found in project directory"
    }

    $subtitleFile = Get-Item -LiteralPath $subtitlePath
    Write-Host "  Selected: $($subtitleFile.Name)" -ForegroundColor Green

    # Check language
    $subtitleData = Import-SubtitleFile -Path $subtitlePath
    $langCheck = Test-SubtitleLanguage -Entries $subtitleData.Entries
    Write-Host "  Detected language: $($langCheck.DetectedLanguage)" -ForegroundColor Gray

    #endregion

    #region Step 3: Generate Transcript (Optional)
    if ($GenerateTranscript) {
        Write-Host ""
        Write-Host "[Step 2.5/4] Generating transcript..." -ForegroundColor Yellow

        $transcriptPath = Join-Path $projectDir "transcript.txt"
        Invoke-TranscriptGenerator -InputPath $subtitlePath -OutputPath $transcriptPath | Out-Null
        Write-Host "  Transcript: transcript.txt" -ForegroundColor Green
    }
    #endregion

    #region Step 3: Translate
    $bilingualAssPath = ""

    if (-not $SkipTranslate) {
        $Host.UI.RawUI.WindowTitle = "VTS: Step 3/4 - Translating..."
        Write-Host ""
        Write-Host "[Step 3/4] Translating subtitles..." -ForegroundColor Yellow

        $bilingualAssPath = Join-Path $projectDir "bilingual.ass"

        $translateResult = Invoke-SubtitleTranslator -InputPath $subtitlePath -OutputPath $bilingualAssPath -Quiet

        Write-Host "  Bilingual ASS: bilingual.ass" -ForegroundColor Green
        Write-Host "  Translated $($translateResult.EntryCount) entries" -ForegroundColor Gray
    }
    else {
        Write-Host ""
        Write-Host "[Step 3/4] Skipping translation" -ForegroundColor DarkGray

        # Look for existing bilingual subtitle
        $existingAss = Join-Path $projectDir "bilingual.ass"
        if (Test-Path -LiteralPath $existingAss) {
            $bilingualAssPath = $existingAss
        }
    }

    #endregion

    #region Step 4: Mux
    if (-not $SkipMux -and $videoPath -and $bilingualAssPath) {
        $Host.UI.RawUI.WindowTitle = "VTS: Step 4/4 - Muxing..."
        Write-Host ""
        Write-Host "[Step 4/4] Muxing subtitle into video..." -ForegroundColor Yellow

        # Output MKV to parent directory
        $videoId = Split-Path -Leaf $projectDir
        $outputMkvPath = Join-Path $script:WorkflowOutputDir "$videoId.mkv"

        # Temporarily override muxer output dir
        $originalMuxDir = $script:MuxerOutputDir
        $script:MuxerOutputDir = $script:WorkflowOutputDir

        try {
            # Custom mux to specific output path
            $muxResult = Invoke-SubtitleMuxer -VideoPath $videoPath -SubtitlePath $bilingualAssPath -Quiet

            # Rename if needed
            if ($muxResult -ne $outputMkvPath -and (Test-Path -LiteralPath $muxResult)) {
                if (Test-Path -LiteralPath $outputMkvPath) {
                    Remove-Item -LiteralPath $outputMkvPath -Force
                }
                Move-Item -LiteralPath $muxResult -Destination $outputMkvPath -Force
            }

            Write-Host "  Output: $outputMkvPath" -ForegroundColor Green
        }
        finally {
            $script:MuxerOutputDir = $originalMuxDir
        }
    }
    else {
        Write-Host ""
        Write-Host "[Step 4/4] Skipping mux" -ForegroundColor DarkGray
    }

    #endregion

    # Restore original window title
    $Host.UI.RawUI.WindowTitle = $originalTitle

    return @{
        ProjectDir = $projectDir
        VideoPath = $videoPath
        SubtitlePath = $subtitlePath
        BilingualAssPath = $bilingualAssPath
    }
}

#endregion

#region Command-line Interface

if ($InputUrl) {
    try {
        $result = Invoke-FullWorkflow -InputUrl $InputUrl -ShowHeader
    }
    catch {
        Write-Host ""
        Write-Host "Error: $_" -ForegroundColor Red
        exit 1
    }
}
elseif ($MyInvocation.InvocationName -ne '.') {
    Write-Host "Usage: workflow.bat <url>" -ForegroundColor Yellow
    Write-Host "Runs complete workflow: download -> translate -> mux" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Gray
    Write-Host "  workflow.bat https://www.youtube.com/watch?v=dQw4w9WgXcQ" -ForegroundColor Gray
    Write-Host "  workflow.bat https://www.bilibili.com/video/BV1xx411c7XW" -ForegroundColor Gray
    exit 1
}

#endregion
