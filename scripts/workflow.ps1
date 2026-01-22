# Full workflow module
# Handles complete pipeline: download -> translate -> mux

# Dot source dependencies if not already loaded
if (-not (Get-Command "Get-LanguageDisplayName" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\lang-config.ps1"
}
if (-not (Get-Command "Invoke-VideoDownload" -ErrorAction SilentlyContinue)) {
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

# Configuration (set by vts.ps1 from config.json)
$script:WorkflowOutputDir = "$PSScriptRoot\..\output"
$script:TargetLanguage = $script:DefaultTargetLanguage

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
    $skipTranslation = $false

    #region Step 1: Download
    if (-not $SkipDownload -and -not $ExistingProjectDir) {
        $Host.UI.RawUI.WindowTitle = "VTS: Step 1/3 - Downloading..."
        Write-Host "[Step 1/3] Downloading video and subtitles..." -ForegroundColor Yellow

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

        # Download subtitles using smart selection
        $subResult = Invoke-SubtitleDownload -Url $InputUrl -ProjectDir $projectDir -TargetLanguage $script:TargetLanguage

        if ($subResult.SkipTranslation) {
            if ($subResult.SubtitleType -eq "embedded") {
                Write-Host "  Subtitles: Target language already available (skipping translation)" -ForegroundColor Green
                $skipTranslation = $true
            } else {
                Write-Host "  Subtitles: None available" -ForegroundColor Yellow
                $skipTranslation = $true
            }
        } else {
            Write-Host "  Subtitles: $($subResult.SubtitleType) ($($subResult.VideoLanguage))" -ForegroundColor Green
            $subtitlePath = $subResult.SubtitleFile
        }
    }
    else {
        Write-Host "[Step 1/3] Skipping download (using existing files)" -ForegroundColor DarkGray

        if ($ExistingProjectDir) {
            $projectDir = $ExistingProjectDir
        }

        # Find existing video
        $videoFile = Get-ChildItem -LiteralPath $projectDir -Filter "video.*" -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '\.(mp4|mkv|webm|mov|avi)$' } |
            Select-Object -First 1
        if ($videoFile) {
            $videoPath = $videoFile.FullName
        }

        # Find existing subtitle (prefer manual over auto)
        $subtitleFiles = @(Get-ChildItem -LiteralPath $projectDir -Filter "*.vtt" -ErrorAction SilentlyContinue) +
                         @(Get-ChildItem -LiteralPath $projectDir -Filter "*.srt" -ErrorAction SilentlyContinue)

        if ($subtitleFiles.Count -gt 0) {
            $manualSub = $subtitleFiles | Where-Object { $_.Name -notmatch '\.auto\.' } | Select-Object -First 1
            $subtitlePath = if ($manualSub) { $manualSub.FullName } else { $subtitleFiles[0].FullName }
            Write-Host "  Using existing subtitle: $(Split-Path -Leaf $subtitlePath)" -ForegroundColor Gray
        }
    }

    #endregion

    #region Step 1.5: Generate Transcript (Optional)
    if ($GenerateTranscript -and $subtitlePath) {
        Write-Host ""
        Write-Host "[Step 1.5/3] Generating transcript..." -ForegroundColor Yellow

        $transcriptPath = Join-Path $projectDir "transcript.txt"
        Invoke-TranscriptGenerator -InputPath $subtitlePath -OutputPath $transcriptPath -Quiet | Out-Null
        Write-Host "  Transcript: transcript.txt" -ForegroundColor Green
    }
    #endregion

    #region Step 2: Translate
    $bilingualAssPath = ""

    if (-not $SkipTranslate -and -not $skipTranslation -and $subtitlePath) {
        $Host.UI.RawUI.WindowTitle = "VTS: Step 2/3 - Translating..."
        Write-Host ""
        Write-Host "[Step 2/3] Translating subtitles..." -ForegroundColor Yellow

        # Check language
        $subtitleData = Import-SubtitleFile -Path $subtitlePath
        $langCheck = Test-SubtitleLanguage -Entries $subtitleData.Entries
        Write-Host "  Source: $($langCheck.DetectedLanguage)" -ForegroundColor Gray

        $bilingualAssPath = Join-Path $projectDir "bilingual.ass"

        $translateResult = Invoke-SubtitleTranslator -InputPath $subtitlePath -OutputPath $bilingualAssPath -Quiet

        Write-Host "  Output: bilingual.ass" -ForegroundColor Green
        Write-Host "  Entries: $($translateResult.EntryCount)" -ForegroundColor Gray
    }
    elseif ($skipTranslation) {
        Write-Host ""
        Write-Host "[Step 2/3] Skipping translation (target language subtitle available)" -ForegroundColor DarkGray
    }
    else {
        Write-Host ""
        Write-Host "[Step 2/3] Skipping translation" -ForegroundColor DarkGray

        # Look for existing bilingual subtitle
        $existingAss = Join-Path $projectDir "bilingual.ass"
        if (Test-Path -LiteralPath $existingAss) {
            $bilingualAssPath = $existingAss
        }
    }

    #endregion

    #region Step 3: Mux
    if (-not $SkipMux -and $videoPath -and $bilingualAssPath) {
        $Host.UI.RawUI.WindowTitle = "VTS: Step 3/3 - Muxing..."
        Write-Host ""
        Write-Host "[Step 3/3] Muxing subtitle into video..." -ForegroundColor Yellow

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
    elseif ($skipTranslation -and $videoPath) {
        Write-Host ""
        Write-Host "[Step 3/3] Skipping mux (no translation needed)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "[SUCCESS] Workflow completed!" -ForegroundColor Green
        Write-Host "  Note: Video already has target language subtitles embedded" -ForegroundColor Gray
    }
    else {
        Write-Host ""
        Write-Host "[Step 3/3] Skipping mux" -ForegroundColor DarkGray
    }

    #endregion

    # Restore original window title
    $Host.UI.RawUI.WindowTitle = $originalTitle

    return @{
        ProjectDir = $projectDir
        VideoPath = $videoPath
        SubtitlePath = $subtitlePath
        BilingualAssPath = $bilingualAssPath
        SkippedTranslation = $skipTranslation
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
