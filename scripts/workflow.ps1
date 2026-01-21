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

        # Create project directory using shared function from download.ps1
        $project = New-VideoProjectDir -Url $InputUrl
        $projectDir = $project.ProjectDir

        Write-Host "  Video ID: $($project.VideoId)" -ForegroundColor Gray
        Write-Host "  Title: $($project.VideoTitle)" -ForegroundColor Gray

        # Download video using shared function
        Write-Host "  Downloading video..." -ForegroundColor Gray
        $videoPath = Invoke-VideoDownload -Url $InputUrl -ProjectDir $projectDir -Quiet
        if ($videoPath) {
            Write-Host "  Video: $(Split-Path -Leaf $videoPath)" -ForegroundColor Green
        }

        # Download subtitles using shared function
        Write-Host "  Downloading subtitles..." -ForegroundColor Gray
        $subCount = Invoke-SubtitleDownload -Url $InputUrl -ProjectDir $projectDir -Quiet
        if ($subCount -gt 0) {
            Write-Host "  Subtitles: $subCount files" -ForegroundColor Green
        } else {
            Write-Host "  No subtitles available" -ForegroundColor Yellow
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
    Write-Host "[Step 2/4] Selecting subtitle..." -ForegroundColor Yellow

    $subtitlePath = Select-BestSubtitle -ProjectDir $projectDir -PreferredLanguage "en"

    if (-not $subtitlePath) {
        Write-Host "  No subtitle files found" -ForegroundColor Red
        throw "No subtitle files found in project directory"
    }

    $subtitleFile = Get-Item -LiteralPath $subtitlePath
    Write-Host "  Selected: $($subtitleFile.Name)" -ForegroundColor Green

    # Check language
    $subtitleData = Import-SubtitleFile -Path $subtitlePath
    $langCheck = Test-SubtitleLanguage -Entries $subtitleData.Entries
    Write-Host "  Language: $($langCheck.DetectedLanguage)" -ForegroundColor Gray

    #endregion

    #region Step 2.5: Generate Transcript (Optional)
    if ($GenerateTranscript) {
        Write-Host ""
        Write-Host "[Step 2.5/4] Generating transcript..." -ForegroundColor Yellow

        $transcriptPath = Join-Path $projectDir "transcript.txt"
        Invoke-TranscriptGenerator -InputPath $subtitlePath -OutputPath $transcriptPath -Quiet | Out-Null
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

        Write-Host "  Output: bilingual.ass" -ForegroundColor Green
        Write-Host "  Entries: $($translateResult.EntryCount)" -ForegroundColor Gray
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

            Write-Host "  Output: $(Split-Path -Leaf $outputMkvPath)" -ForegroundColor Green
        }
        finally {
            $script:MuxerOutputDir = $originalMuxDir
        }

        Write-Host ""
        Write-Host "[SUCCESS] Workflow completed!" -ForegroundColor Green
        Write-Host "  Project: $projectDir" -ForegroundColor Gray
        Write-Host "  Output: $outputMkvPath" -ForegroundColor Gray
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

if ($MyInvocation.InvocationName -ne '.') {
    $cliUrl = if ($args.Count -ge 1) { $args[0] } else { $null }
    if ($cliUrl) {
        try {
            $result = Invoke-FullWorkflow -InputUrl $cliUrl -ShowHeader
        }
        catch {
            Write-Host ""
            Write-Host "Error: $_" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Usage: workflow.bat <url>" -ForegroundColor Yellow
        Write-Host "Runs complete workflow: download -> translate -> mux" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Gray
        Write-Host "  workflow.bat https://www.youtube.com/watch?v=dQw4w9WgXcQ" -ForegroundColor Gray
        Write-Host "  workflow.bat https://www.bilibili.com/video/BV1xx411c7XW" -ForegroundColor Gray
        exit 1
    }
}

#endregion
