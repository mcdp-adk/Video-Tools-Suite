# Full workflow module
# Handles complete pipeline: download -> translate -> mux

# Dot source dependencies if not already loaded
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}
if (-not (Get-Command "Set-VtsWindowTitle" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\tui-utils.ps1"
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

# Detect project completion status by checking artifact files
function Get-ProjectStatus {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectDir,
        [string]$OutputDir = $script:WorkflowOutputDir
    )

    $status = @{
        ProjectDir = $ProjectDir
        HasVideo = $false
        HasSubtitle = $false
        HasBilingual = $false
        HasFinalMkv = $false
        VideoPath = $null
        SubtitlePath = $null
        BilingualPath = $null
        FinalMkvPath = $null
        NextStage = "download"
    }

    if (-not (Test-Path -LiteralPath $ProjectDir)) {
        return $status
    }

    # Check for video file
    $videoFile = Get-ChildItem -LiteralPath $ProjectDir -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^video\.(mp4|mkv|webm|mov|avi)$' } |
        Select-Object -First 1
    if ($videoFile) {
        $status.HasVideo = $true
        $status.VideoPath = $videoFile.FullName
    }

    # Check for subtitle file (vtt or srt)
    $subtitleFile = Get-ChildItem -LiteralPath $ProjectDir -Filter "original.*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '\.(vtt|srt)$' } |
        Select-Object -First 1
    if ($subtitleFile) {
        $status.HasSubtitle = $true
        $status.SubtitlePath = $subtitleFile.FullName
    }

    # Check for bilingual.ass
    $bilingualPath = Join-Path $ProjectDir "bilingual.ass"
    if (Test-Path -LiteralPath $bilingualPath) {
        $status.HasBilingual = $true
        $status.BilingualPath = $bilingualPath
    }

    # Check for final MKV in output directory
    $projectName = Split-Path -Leaf $ProjectDir
    $finalMkvPath = Join-Path $OutputDir "$projectName.mkv"
    if (Test-Path -LiteralPath $finalMkvPath) {
        $status.HasFinalMkv = $true
        $status.FinalMkvPath = $finalMkvPath
    }

    # Determine next stage
    if (-not $status.HasVideo -or -not $status.HasSubtitle) {
        $status.NextStage = "download"
    }
    elseif (-not $status.HasBilingual) {
        $status.NextStage = "translate"
    }
    elseif (-not $status.HasFinalMkv) {
        $status.NextStage = "mux"
    }
    else {
        $status.NextStage = "complete"
    }

    return $status
}

# Resume workflow from last incomplete stage
function Resume-Workflow {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectDir,
        [string]$Url = "",
        [switch]$GenerateTranscript
    )

    $status = Get-ProjectStatus -ProjectDir $ProjectDir

    if ($status.NextStage -eq "complete") {
        Show-Success "Project already complete: $ProjectDir"
        return @{ Success = $true; Skipped = $true }
    }

    Show-Info "Resuming from stage: $($status.NextStage)"

    # Determine skip flags based on status
    $skipDownload = $status.HasVideo -and $status.HasSubtitle
    $skipTranslate = $status.HasBilingual
    $skipMux = $status.HasFinalMkv

    # If we need to download but have no URL, we can't proceed
    if (-not $skipDownload -and -not $Url) {
        Show-Error "Cannot resume download stage without URL"
        return @{ Success = $false; Error = "URL required for download" }
    }

    try {
        $result = Invoke-FullWorkflow `
            -InputUrl $Url `
            -ExistingProjectDir $ProjectDir `
            -SkipDownload:$skipDownload `
            -SkipTranslate:$skipTranslate `
            -SkipMux:$skipMux `
            -GenerateTranscript:$GenerateTranscript

        return @{ Success = $true; Result = $result }
    }
    catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

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
    $originalTitle = Save-WindowTitle

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
        Set-VtsWindowTitle -Phase Download -Status "Downloading..."
        Show-Step "[Step 1/3] Downloading video and subtitles..."

        # Create project directory using shared function from download.ps1
        $project = New-VideoProjectDir -Url $InputUrl
        $projectDir = $project.ProjectDir

        Show-Detail "Video ID: $($project.VideoId)"
        Show-Detail "Title: $($project.VideoTitle)"

        # Download video using shared function
        Show-Detail "Downloading video..."
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
        Write-Host ""
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
            Show-Detail "Using existing subtitle: $(Split-Path -Leaf $subtitlePath)"
        }
    }

    #endregion

    #region Step 1.5: Generate Transcript (Optional)
    if ($GenerateTranscript -and $subtitlePath) {
        Show-Step "[Step 1.5/3] Generating transcript..."

        $transcriptPath = Join-Path $projectDir "transcript.txt"
        Invoke-TranscriptGenerator -InputPath $subtitlePath -OutputPath $transcriptPath -Quiet | Out-Null
        Show-Success "  Transcript: transcript.txt"
    }
    #endregion

    #region Step 2: Translate
    $bilingualAssPath = ""

    if (-not $SkipTranslate -and -not $skipTranslation -and $subtitlePath) {
        Set-VtsWindowTitle -Phase Translate -Status "Translating..."
        Show-Step "[Step 2/3] Translating subtitles..."

        # Check language
        $subtitleData = Import-SubtitleFile -Path $subtitlePath
        $langCheck = Test-SubtitleLanguage -Entries $subtitleData.Entries
        Show-Detail "Source: $($langCheck.DetectedLanguage)"

        $bilingualAssPath = Join-Path $projectDir "bilingual.ass"

        $translateResult = Invoke-SubtitleTranslator -InputPath $subtitlePath -OutputPath $bilingualAssPath -Quiet

        Show-Success "  Output: bilingual.ass"
        Show-Detail "Entries: $($translateResult.EntryCount)"
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
        Set-VtsWindowTitle -Phase Mux -Status "Muxing..."
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
        Show-Detail "Project: $projectDir"
        Show-Detail "Output: $outputMkvPath"
    }
    elseif ($skipTranslation -and $videoPath) {
        Write-Host ""
        Show-Hint "[Step 3/3] Skipping mux (no translation needed)"
        Write-Host ""
        Show-Success "Workflow completed!"
        Show-Detail "Note: Video already has target language subtitles embedded"
    }
    else {
        Write-Host ""
        Show-Hint "[Step 3/3] Skipping mux"
    }

    #endregion

    # Restore original window title
    Restore-WindowTitle -Title $originalTitle

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
        Show-Hint "workflow.bat https://www.youtube.com/watch?v=dQw4w9WgXcQ" -Indent 1
        Show-Hint "workflow.bat https://www.bilibili.com/video/BV1xx411c7XW" -Indent 1
        exit 1
    }
}

#endregion
