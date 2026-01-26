#Requires -Version 5.1

# Set UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Dot source all scripts
. "$PSScriptRoot\utils.ps1"
. "$PSScriptRoot\config-manager.ps1"
. "$PSScriptRoot\lang-config.ps1"
. "$PSScriptRoot\subtitle-utils.ps1"
. "$PSScriptRoot\ai-client.ps1"
. "$PSScriptRoot\glossary.ps1"
. "$PSScriptRoot\mux.ps1"
. "$PSScriptRoot\download.ps1"
. "$PSScriptRoot\transcript.ps1"
. "$PSScriptRoot\translate.ps1"
. "$PSScriptRoot\workflow.ps1"
. "$PSScriptRoot\batch.ps1"
. "$PSScriptRoot\setup-wizard.ps1"
. "$PSScriptRoot\settings.ps1"

#region Helper Functions
# Note: Remove-Quotes, Format-DisplayPath, Read-UserInput are now in utils.ps1

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "                     Video Tools Suite" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  Output: $(Format-DisplayPath $script:Config.OutputDir)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  [A]" -ForegroundColor Magenta -NoNewline
    Write-Host " All-in-One Workflow" -ForegroundColor White
    Write-Host "  [B]" -ForegroundColor Magenta -NoNewline
    Write-Host " Batch Download (Playlist/Multi-URL)" -ForegroundColor White
    Write-Host ""

    Write-Host "  [1]" -ForegroundColor Green -NoNewline
    Write-Host " Download Video" -ForegroundColor White
    Write-Host "  [2]" -ForegroundColor Green -NoNewline
    Write-Host " Download Subtitles Only" -ForegroundColor White
    Write-Host "  [3]" -ForegroundColor Green -NoNewline
    Write-Host " Generate Transcript" -ForegroundColor White
    Write-Host "  [4]" -ForegroundColor Green -NoNewline
    Write-Host " Translate Subtitles" -ForegroundColor White
    Write-Host ""

    Write-Host "  [S]" -ForegroundColor Cyan -NoNewline
    Write-Host " Settings" -ForegroundColor White
    Write-Host "  [Q]" -ForegroundColor Red -NoNewline
    Write-Host " Quit" -ForegroundColor White
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host ""
}

function Get-MenuChoice {
    param([string[]]$ValidChoices = @('A', 'B', '1', '2', '3', '4', 'S', 'Q'))

    do {
        $choice = (Read-Host "Enter your choice").Trim().ToUpper()

        if ($ValidChoices -contains $choice) {
            return $choice
        }

        Show-Error "Invalid choice! Please enter A, B, 1-4, S or Q"
        Write-Host ""
    } while ($true)
}

function Show-Header {
    param([string]$Text)

    $padding = [math]::Max(0, [math]::Floor((60 - $Text.Length) / 2))
    $centeredText = (" " * $padding) + $Text

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host $centeredText -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
}

function Pause-Menu {
    Write-Host ""
    Write-Host ("-" * 60) -ForegroundColor DarkGray
    Read-Host "Press Enter to return to main menu" | Out-Null
}

function Show-UrlFormats {
    Write-Host "Supports 1800+ sites via yt-dlp" -ForegroundColor Cyan
    Show-Hint "Examples:"
    Show-Hint "  - https://www.youtube.com/watch?v=XXXXXXXXXXX"
    Show-Hint "  - https://www.youtube.com/live/XXXXXXXXXXX"
    Show-Hint "  - https://www.bilibili.com/video/BVXXXXXXXXX"
    Show-Hint "  - XXXXXXXXXXX (YouTube video ID)"
    Write-Host ""
}

#endregion

#region Menu Option Functions

function Invoke-FullWorkflowMenu {
    Clear-Host
    Show-Header "All-in-One Workflow"

    $projectDir = $null
    $url = $null

    try {
        Write-Host "This will download video, translate subtitles, and mux them together." -ForegroundColor Cyan
        Write-Host ""
        Show-UrlFormats

        $url = Read-UserInput -Prompt "Enter URL"
        if (-not $url) {
            Show-Error "No URL provided"
            Pause-Menu
            return
        }

        $result = Invoke-FullWorkflow -InputUrl $url -GenerateTranscript:$script:Config.GenerateTranscriptInWorkflow

        # Store project dir for potential retry
        if ($result -and $result.ProjectDir) {
            $projectDir = $result.ProjectDir
        }
    }
    catch {
        Show-Error $_.Exception.Message

        # Offer retry if we have project info
        if ($projectDir -or $url) {
            Write-Host ""
            $retry = Read-Host "Retry? (Y/N)"
            if ($retry -eq 'y') {
                if ($projectDir) {
                    # Smart retry from last stage
                    $retryResult = Resume-Workflow -ProjectDir $projectDir -Url $url -GenerateTranscript:$script:Config.GenerateTranscriptInWorkflow
                    if (-not $retryResult.Success) {
                        Show-Error $retryResult.Error
                    }
                }
                else {
                    # Retry from scratch
                    Invoke-FullWorkflowMenu
                    return
                }
            }
        }
    }

    Pause-Menu
}

function Invoke-BatchDownloadMenu {
    Clear-Host
    Show-Header "Batch Download"

    Write-Host "  [1] YouTube Playlist URL" -ForegroundColor White
    Write-Host "  [2] Enter Multiple URLs" -ForegroundColor White
    Write-Host "  [B] Back" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Read-Host "Select input method"

    $urls = @()

    switch ($choice.ToUpper()) {
        '1' {
            # Playlist mode
            Write-Host ""
            $playlistUrl = Read-Host "Enter playlist URL"
            if (-not $playlistUrl) {
                Show-Error "No URL provided"
                Pause-Menu
                return
            }

            Show-Step "Extracting video URLs from playlist..."
            try {
                $urls = Get-PlaylistVideoUrls -PlaylistUrl $playlistUrl
                Show-Success "Found $($urls.Count) videos"
                Write-Host ""
            }
            catch {
                Show-Error "Failed to extract playlist: $_"
                Pause-Menu
                return
            }
        }
        '2' {
            # Multi-URL mode
            Write-Host ""
            Write-Host "Enter URLs (one per line, empty line to finish):" -ForegroundColor Cyan
            do {
                $url = Read-Host
                if ($url) { $urls += $url }
            } while ($url)
        }
        'B' { return }
        default {
            Show-Error "Invalid choice"
            Pause-Menu
            return
        }
    }

    if ($urls.Count -eq 0) {
        Show-Error "No URLs provided"
        Pause-Menu
        return
    }

    # Preview video titles
    Show-Step -NoBlankBefore "Fetching video titles..."
    $previews = @()
    foreach ($url in $urls) {
        $title = Get-VideoTitle -Url $url
        $previews += @{ Url = $url; Title = $title }
        Write-Host "  $($previews.Count). $title" -ForegroundColor White
    }

    Show-Info "Ready to process $($urls.Count) videos"
    Wait-WithCountdown -Seconds 20 | Out-Null

    # Run batch workflow
    $result = Invoke-BatchWorkflow -Urls $urls

    # Offer retry if there are failures
    while ($result.Failed.Count -gt 0) {
        Write-Host ""
        $retry = Read-Host "Retry failed items? (Y/N)"
        if ($retry -eq 'y') {
            $result = Invoke-BatchRetry -FailedItems $result.Failed
        }
        else {
            break
        }
    }

    Pause-Menu
}

function Invoke-YouTubeDownloadMenu {
    Clear-Host
    Show-Header "Download Video"

    try {
        Show-UrlFormats
        $url = Read-UserInput -Prompt "Enter URL"
        if (-not $url) {
            Show-Error "No URL provided"
            Pause-Menu
            return
        }

        Write-Host ""
        Write-Host "Creating project..." -ForegroundColor Cyan
        $project = New-VideoProjectDir -Url $url
        Show-Detail "Project: $($project.ProjectName)"

        Write-Host ""
        $videoPath = Invoke-VideoDownload -Url $url -ProjectDir $project.ProjectDir
        $subCount = Invoke-SubtitleDownload -Url $url -ProjectDir $project.ProjectDir

        Write-Host ""
        Show-Success "Download complete!"
        Show-Detail "Project folder: $($project.ProjectDir)"
        if ($videoPath) {
            Show-Detail "Video: $(Split-Path -Leaf $videoPath)"
        }
        Show-Detail "Subtitles: $subCount files"
    }
    catch {
        Show-Error $_.Exception.Message
    }

    Pause-Menu
}

function Invoke-SubtitleOnlyDownloadMenu {
    Clear-Host
    Show-Header "Download Subtitles Only"

    try {
        Write-Host "This will download only subtitles (manual + auto-generated)" -ForegroundColor Cyan
        Write-Host ""
        Show-UrlFormats
        $url = Read-UserInput -Prompt "Enter URL"
        if (-not $url) {
            Show-Error "No URL provided"
            Pause-Menu
            return
        }

        Write-Host ""
        Write-Host "Creating project..." -ForegroundColor Cyan
        $project = New-VideoProjectDir -Url $url
        Show-Detail "Project: $($project.ProjectName)"

        Write-Host ""
        $subResult = Invoke-SubtitleDownload -Url $url -ProjectDir $project.ProjectDir

        Write-Host ""
        if ($subResult.SubtitleFile) {
            Show-Success "Subtitle downloaded!"
            Show-Detail "File: $(Split-Path -Leaf $subResult.SubtitleFile)"
            Show-Detail "Type: $($subResult.SubtitleType)"
            Show-Detail "Language: $($subResult.VideoLanguage)"
        } elseif ($subResult.SubtitleType -eq "embedded") {
            Show-Success "Target language subtitle already embedded in video"
        } else {
            Show-Warning "No subtitles available for this video"
        }
    }
    catch {
        Show-Error $_.Exception.Message
    }

    Pause-Menu
}

function Invoke-TranscriptMenu {
    Clear-Host
    Show-Header "Generate Transcript"

    try {
        Write-Host "This will generate a plain text transcript from subtitle file" -ForegroundColor Cyan
        Write-Host ""
        $file = Read-UserInput -Prompt "Enter subtitle file path (.vtt or .srt)" -ValidateFileExists
        if (-not $file) {
            Show-Error "No file path provided"
            Pause-Menu
            return
        }
        if ($file -is [hashtable] -and $file.Error) {
            Show-Error $file.Error
            Pause-Menu
            return
        }

        Show-Step "Generating transcript..."
        $result = Invoke-TranscriptGenerator -InputPath $file -Quiet
        Show-Success "Transcript saved to: $result"
    }
    catch {
        Show-Error $_.Exception.Message
    }

    Pause-Menu
}

function Invoke-TranslateMenu {
    Clear-Host
    Show-Header "Translate Subtitles"

    try {
        Write-Host "AI Model: $($script:Config.AiModel)" -ForegroundColor Cyan
        Write-Host "Target: $($script:Config.TargetLanguage)" -ForegroundColor Cyan
        Write-Host ""

        $file = Read-UserInput -Prompt "Enter subtitle file path (.vtt or .srt)" -ValidateFileExists
        if (-not $file) {
            Show-Error "No file path provided"
            Pause-Menu
            return
        }
        if ($file -is [hashtable] -and $file.Error) {
            Show-Error $file.Error
            Pause-Menu
            return
        }

        Show-Step "Translating..."
        $result = Invoke-SubtitleTranslator -InputPath $file -Quiet

        Write-Host ""
        Show-Success "Translation complete!"
        Show-Detail "Output: $($result.OutputPath)"
        Show-Detail "Entries: $($result.EntryCount)"
    }
    catch {
        Show-Error $_.Exception.Message
    }

    Pause-Menu
}

#endregion

#region Main Menu Loop

function Start-MainMenu {
    # Check config and run setup wizard if needed
    $needsSetup = Ensure-ConfigReady
    if ($needsSetup) {
        Start-SetupWizard
        Complete-Setup
        Apply-ConfigToModules
    }

    $running = $true

    while ($running) {
        Show-Menu

        switch (Get-MenuChoice) {
            'A' { Invoke-FullWorkflowMenu }
            'B' { Invoke-BatchDownloadMenu }
            '1' { Invoke-YouTubeDownloadMenu }
            '2' { Invoke-SubtitleOnlyDownloadMenu }
            '3' { Invoke-TranscriptMenu }
            '4' { Invoke-TranslateMenu }
            'S' {
                $result = Invoke-SettingsMenu
                if ($result -eq "reset") {
                    # Config was reset, run setup wizard
                    $null = Ensure-ConfigReady
                    Start-SetupWizard
                    Complete-Setup
                    Apply-ConfigToModules
                }
            }
            'Q' {
                Clear-Host
                Write-Host ""
                Show-Success "Thank you for using Video Tools Suite!"
                Show-Hint "Goodbye!"
                Write-Host ""
                $running = $false
            }
        }
    }
}

#endregion

# Entry Point
Start-MainMenu
