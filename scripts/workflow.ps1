# Full workflow module
# Handles complete pipeline: download -> translate -> mux

# Dot source dependencies if not already loaded
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}
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
        Show-Step "[Step 1/3] Downloading video and subtitles..."

        # Create project directory using shared function from download.ps1
        $project = New-VideoProjectDir -Url $InputUrl
        $projectDir = $project.ProjectDir

        Show-Detail "  Video ID: $($project.VideoId)"
        Show-Detail "  Title: $($project.VideoTitle)"

        # Download video using shared function
        Show-Detail "  Downloading video..."
        $videoPath = Invoke-VideoDownload -Url $InputUrl -ProjectDir $projectDir -Quiet
        if ($videoPath) {
            Show-Success "  Video: $(Split-Path -Leaf $videoPath)"
        }

        # Download subtitles using smart selection
        $subResult = Invoke-SubtitleDownload -Url $InputUrl -ProjectDir $projectDir -TargetLanguage $script:TargetLanguage

        if ($subResult.SkipTranslation) {
            if ($subResult.SubtitleType -eq "embedded") {
                Show-Success "  Subtitles: Target language already available (skipping translation)"
                $skipTranslation = $true
            } else {
                Show-Warning "  Subtitles: None available"
                $skipTranslation = $true
            }
        } else {
            Show-Success "  Subtitles: $($subResult.SubtitleType) ($($subResult.VideoLanguage))"
            $subtitlePath = $subResult.SubtitleFile
        }
    }
    else {
        Show-Hint "[Step 1/3] Skipping download (using existing files)"

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
            Show-Detail "  Using existing subtitle: $(Split-Path -Leaf $subtitlePath)"
        }
    }

    #endregion

    #region Step 1.5: Generate Transcript (Optional)
    if ($GenerateTranscript -and $subtitlePath) {
        Write-Host ""
        Show-Step "[Step 1.5/3] Generating transcript..."

        $transcriptPath = Join-Path $projectDir "transcript.txt"
        Invoke-TranscriptGenerator -InputPath $subtitlePath -OutputPath $transcriptPath -Quiet | Out-Null
        Show-Success "  Transcript: transcript.txt"
    }
    #endregion

    #region Step 2: Translate
    $bilingualAssPath = ""

    if (-not $SkipTranslate -and -not $skipTranslation -and $subtitlePath) {
        $Host.UI.RawUI.WindowTitle = "VTS: Step 2/3 - Translating..."
        Write-Host ""
        Show-Step "[Step 2/3] Translating subtitles..."

        # Check language
        $subtitleData = Import-SubtitleFile -Path $subtitlePath
        $langCheck = Test-SubtitleLanguage -Entries $subtitleData.Entries
        Show-Detail "  Source: $($langCheck.DetectedLanguage)"

        $bilingualAssPath = Join-Path $projectDir "bilingual.ass"

        $translateResult = Invoke-SubtitleTranslator -InputPath $subtitlePath -OutputPath $bilingualAssPath -Quiet

        Show-Success "  Output: bilingual.ass"
        Show-Detail "  Entries: $($translateResult.EntryCount)"
    }
    elseif ($skipTranslation) {
        Write-Host ""
        Show-Hint "[Step 2/3] Skipping translation (target language subtitle available)"
    }
    else {
        Write-Host ""
        Show-Hint "[Step 2/3] Skipping translation"

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
        Show-Step "[Step 3/3] Muxing subtitle into video..."

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

            Show-Success "  Output: $(Split-Path -Leaf $outputMkvPath)"
        }
        finally {
            $script:MuxerOutputDir = $originalMuxDir
        }

        Write-Host ""
        Show-Success "Workflow completed!"
        Show-Detail "  Project: $projectDir"
        Show-Detail "  Output: $outputMkvPath"
    }
    elseif ($skipTranslation -and $videoPath) {
        Write-Host ""
        Show-Hint "[Step 3/3] Skipping mux (no translation needed)"
        Write-Host ""
        Show-Success "Workflow completed!"
        Show-Detail "  Note: Video already has target language subtitles embedded"
    }
    else {
        Write-Host ""
        Show-Hint "[Step 3/3] Skipping mux"
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
            Show-Error $_
            exit 1
        }
    } else {
        Show-Warning "Usage: workflow.bat <url>"
        Show-Hint "Runs complete workflow: download -> translate -> mux"
        Write-Host ""
        Show-Hint "Examples:"
        Show-Hint "  workflow.bat https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        Show-Hint "  workflow.bat https://www.bilibili.com/video/BV1xx411c7XW"
        exit 1
    }
}

#endregion
