# Import utilities
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}
if (-not (Get-Command "Set-VtsWindowTitle" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\tui-utils.ps1"
}

# Configuration
$script:MuxerOutputDir = "$PSScriptRoot\..\output"
$script:DefaultSubtitleLang = "chi"
$script:DefaultSubtitleTitle = "Bilingual Subtitles"

#region Helper Functions

# Check ffmpeg availability
function Test-FfmpegAvailable {
    try {
        $null = Get-Command ffmpeg -ErrorAction Stop
        return $true
    } catch {
        throw "ffmpeg is not installed or not in PATH"
    }
}

# Get existing subtitle streams from video
function Get-ExistingSubtitleStreams {
    param([string]$VideoPath)

    try {
        $streamInfo = & ffprobe -v quiet -print_format json -show_streams "$VideoPath" 2>&1
        $streams = $streamInfo | ConvertFrom-Json

        return $streams.streams | Where-Object { $_.codec_type -eq "subtitle" }
    } catch {
        return @()
    }
}

# Build ffmpeg arguments for muxing
function Build-FfmpegArgs {
    param(
        [string]$VideoPath,
        [string]$SubtitlePath,
        [string]$OutputPath,
        [array]$ExistingSubtitleStreams
    )

    # Base arguments: input files and stream mapping
    # Use -sub_charenc to ensure UTF-8 encoding for subtitle input
    $ffArgs = @(
        "-i", $VideoPath,
        "-sub_charenc", "UTF-8",
        "-i", $SubtitlePath,
        "-map", "0:v",
        "-map", "0:a?",
        "-map", "1:s"
    )

    # New subtitle settings (first subtitle track)
    $ffArgs += @(
        "-c:s:0", "ass",
        "-disposition:s:0", "default",
        "-metadata:s:s:0", "language=$script:DefaultSubtitleLang",
        "-metadata:s:s:0", "title=$script:DefaultSubtitleTitle"
    )

    # Map existing subtitles as secondary tracks
    $subtitleIndex = 1
    foreach ($stream in $ExistingSubtitleStreams) {
        $ffArgs += @(
            "-map", "0:$($stream.index)",
            "-c:s:$subtitleIndex", "copy",
            "-disposition:s:$subtitleIndex", "0"
        )

        # Copy existing metadata if available
        if ($stream.tags.language) {
            $ffArgs += @("-metadata:s:s:$subtitleIndex", "language=$($stream.tags.language)")
        }
        if ($stream.tags.title) {
            $ffArgs += @("-metadata:s:s:$subtitleIndex", "title=$($stream.tags.title)")
        }

        $subtitleIndex++
    }

    # Output settings
    $ffArgs += @(
        "-c:v", "copy",
        "-c:a", "copy",
        "-y",
        $OutputPath
    )

    return $ffArgs
}

#endregion

#region Main Functions

# Function interface for TUI integration
function Invoke-SubtitleMuxer {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VideoPath,
        [Parameter(Mandatory=$true)]
        [string]$SubtitlePath,
        [string]$OutputPath = "",
        [string]$OutputName = "",
        [switch]$Quiet
    )

    # Validate inputs
    if (-not (Test-Path -LiteralPath $VideoPath)) {
        throw "Video file not found: $VideoPath"
    }
    if (-not (Test-Path -LiteralPath $SubtitlePath)) {
        throw "Subtitle file not found: $SubtitlePath"
    }

    Test-FfmpegAvailable | Out-Null

    # Ensure output directory exists
    if (-not (Test-Path $script:MuxerOutputDir)) {
        New-Item -ItemType Directory -Path $script:MuxerOutputDir -Force | Out-Null
    }

    # Determine output path
    if (-not $OutputPath) {
        $videoFile = Get-Item -LiteralPath $VideoPath

        if ($OutputName) {
            # Use custom output name
            $outputFileName = if ($OutputName -match '\.mkv$') { $OutputName } else { "$OutputName.mkv" }
        }
        else {
            # Default: use video filename with .mkv extension
            $outputFileName = [System.IO.Path]::ChangeExtension($videoFile.Name, ".mkv")
        }

        $OutputPath = Join-Path $script:MuxerOutputDir $outputFileName
    }

    # Get existing subtitle streams
    $existingSubtitles = @(Get-ExistingSubtitleStreams -VideoPath $VideoPath)

    if ($existingSubtitles.Count -gt 0 -and -not $Quiet) {
        Show-Detail "Found $($existingSubtitles.Count) existing subtitle tracks, preserving them..."
    }

    # Build and execute ffmpeg command
    $ffmpegArgs = Build-FfmpegArgs -VideoPath $VideoPath -SubtitlePath $SubtitlePath `
                                   -OutputPath $OutputPath -ExistingSubtitleStreams $existingSubtitles

    if (-not $Quiet) {
        Show-Info "Muxing subtitle into video..."
    }

    # Update window title for progress display
    $originalTitle = Save-WindowTitle
    Set-VtsWindowTitle -Phase Mux -Status "Muxing..."

    try {
        $ffmpegOutput = & ffmpeg $ffmpegArgs 2>&1
    }
    finally {
        Restore-WindowTitle -Title $originalTitle
    }

    if ($LASTEXITCODE -ne 0) {
        # Show last few lines of ffmpeg output for debugging
        $errorLines = ($ffmpegOutput | Select-Object -Last 10) -join "`n"
        throw "ffmpeg failed with exit code $LASTEXITCODE`n$errorLines"
    }

    return $OutputPath
}

#endregion

#region Command-line Interface

if ($MyInvocation.InvocationName -ne '.') {
    # CLI mode - parse arguments
    $cliVideo = $null
    $cliSub = $null
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i] -match '^-?Video' -and $i + 1 -lt $args.Count) { $cliVideo = $args[$i + 1] }
        if ($args[$i] -match '^-?Sub' -and $i + 1 -lt $args.Count) { $cliSub = $args[$i + 1] }
    }
    # Also support positional: mux.ps1 video.mkv sub.ass
    if (-not $cliVideo -and $args.Count -ge 1) { $cliVideo = $args[0] }
    if (-not $cliSub -and $args.Count -ge 2) { $cliSub = $args[1] }

    if ($cliVideo -and $cliSub) {
        try {
            $videoFile = Get-Item $cliVideo
            Write-Host "================================================" -ForegroundColor Cyan
            Write-Host "Video:    $($videoFile.Name)" -ForegroundColor White
            Write-Host "Subtitle: $(Split-Path -Leaf $cliSub)" -ForegroundColor White
            Write-Host "================================================" -ForegroundColor Cyan
            Write-Host ""
            Show-Step "Processing..."
            $result = Invoke-SubtitleMuxer -VideoPath $cliVideo -SubtitlePath $cliSub
            Write-Host ""
            Show-Success "Success! Output: $result"
        } catch {
            Show-Error "Error: $_"
            exit 1
        }
    } else {
        Show-Warning "Usage: mux.ps1 <video_file> <subtitle_file>"
        exit 1
    }
}

#endregion
