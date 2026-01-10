# Command-line parameters (must be first for dot sourcing compatibility)
param(
    [string]$VideoPath,
    [string]$SubtitlePath
)

# Configuration
$script:MuxerOutputDir = "$PSScriptRoot\..\output"
$script:DefaultSubtitleLang = "chi"
$script:DefaultSubtitleTitle = "Bilingual Subtitles"

# Helper function: Check ffmpeg availability
function Test-FfmpegAvailable {
    try {
        $null = Get-Command ffmpeg -ErrorAction Stop
        return $true
    } catch {
        throw "ffmpeg is not installed or not in PATH"
    }
}

# Helper function: Get existing subtitle streams from video
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

# Helper function: Build ffmpeg arguments for muxing
function Build-FfmpegArgs {
    param(
        [string]$VideoPath,
        [string]$SubtitlePath,
        [string]$OutputPath,
        [array]$ExistingSubtitleStreams
    )

    # Base arguments: input files and stream mapping
    $ffArgs = @(
        "-i", $VideoPath,
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

# Function interface for TUI integration
function Invoke-SubtitleMuxer {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VideoPath,
        [Parameter(Mandatory=$true)]
        [string]$SubtitlePath
    )

    # Validate inputs
    if (-not (Test-Path $VideoPath)) {
        throw "Video file not found: $VideoPath"
    }
    if (-not (Test-Path $SubtitlePath)) {
        throw "Subtitle file not found: $SubtitlePath"
    }

    Test-FfmpegAvailable | Out-Null

    # Ensure output directory exists
    if (-not (Test-Path $script:MuxerOutputDir)) {
        New-Item -ItemType Directory -Path $script:MuxerOutputDir -Force | Out-Null
    }

    # Build output path (always use MKV for better subtitle compatibility)
    $videoFile = Get-Item $VideoPath
    $outputName = [System.IO.Path]::ChangeExtension($videoFile.Name, ".mkv")
    $outputPath = Join-Path $script:MuxerOutputDir $outputName

    # Get existing subtitle streams
    $existingSubtitles = @(Get-ExistingSubtitleStreams -VideoPath $VideoPath)

    if ($existingSubtitles.Count -gt 0) {
        Write-Host "Found $($existingSubtitles.Count) existing subtitle tracks, preserving them..."
    }

    # Build and execute ffmpeg command
    $ffmpegArgs = Build-FfmpegArgs -VideoPath $VideoPath -SubtitlePath $SubtitlePath `
                                   -OutputPath $outputPath -ExistingSubtitleStreams $existingSubtitles

    $ffmpegOutput = & ffmpeg $ffmpegArgs 2>&1

    if ($LASTEXITCODE -ne 0) {
        # Show last few lines of ffmpeg output for debugging
        $errorLines = ($ffmpegOutput | Select-Object -Last 10) -join "`n"
        throw "ffmpeg failed with exit code $LASTEXITCODE`n$errorLines"
    }

    return $outputPath
}

# Command-line interface (when script is called directly)
if ($VideoPath -and $SubtitlePath) {
    try {
        $videoFile = Get-Item $VideoPath
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host "Video:    $($videoFile.Name)" -ForegroundColor White
        Write-Host "Subtitle: $(Split-Path -Leaf $SubtitlePath)" -ForegroundColor White
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Processing... (this may take a while)" -ForegroundColor Yellow

        $result = Invoke-SubtitleMuxer -VideoPath $VideoPath -SubtitlePath $SubtitlePath

        Write-Host ""
        Write-Host "Success! Video with subtitles saved to:" -ForegroundColor Green
        Write-Host $result -ForegroundColor Gray
    } catch {
        Write-Host ""
        Write-Host "Error: $_" -ForegroundColor Red
        exit 1
    }
} elseif ($MyInvocation.InvocationName -ne '.') {
    Write-Host "Usage: mux.bat <video_file> <subtitle_file>" -ForegroundColor Yellow
    Write-Host "Example: mux.bat video.mkv subtitle.ass" -ForegroundColor Gray
    exit 1
}
