#Requires -Version 5.1

# Set UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Dot source all scripts
. "$PSScriptRoot\utils.ps1"
. "$PSScriptRoot\subtitle-utils.ps1"
. "$PSScriptRoot\ai-client.ps1"
. "$PSScriptRoot\glossary.ps1"
. "$PSScriptRoot\process.ps1"
. "$PSScriptRoot\mux.ps1"
. "$PSScriptRoot\download.ps1"
. "$PSScriptRoot\transcript.ps1"
. "$PSScriptRoot\translate.ps1"
. "$PSScriptRoot\workflow.ps1"
. "$PSScriptRoot\batch.ps1"
. "$PSScriptRoot\setup-wizard.ps1"

#region Configuration

# Config file path (in project root)
$script:ConfigFile = "$PSScriptRoot\..\config.json"

# Default configuration
$script:Config = @{
    FirstRun = $true
    OutputDir = "./output"
    CookieFile = ""
    AiProvider = "openai"
    AiBaseUrl = "https://api.openai.com/v1"
    AiApiKey = ""
    AiModel = "gpt-4o-mini"
    TargetLanguage = "zh-CN"
    GenerateTranscriptInWorkflow = $false
}

# Load config from file
function Import-Config {
    if (Test-Path $script:ConfigFile) {
        try {
            $fileConfig = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json

            # Update config with file values
            if ($null -ne $fileConfig.FirstRun) { $script:Config.FirstRun = $fileConfig.FirstRun }
            if ($fileConfig.OutputDir) { $script:Config.OutputDir = $fileConfig.OutputDir }
            if ($null -ne $fileConfig.CookieFile) { $script:Config.CookieFile = $fileConfig.CookieFile }
            if ($fileConfig.AiProvider) { $script:Config.AiProvider = $fileConfig.AiProvider }
            if ($fileConfig.AiBaseUrl) { $script:Config.AiBaseUrl = $fileConfig.AiBaseUrl }
            if ($null -ne $fileConfig.AiApiKey) { $script:Config.AiApiKey = $fileConfig.AiApiKey }
            if ($fileConfig.AiModel) { $script:Config.AiModel = $fileConfig.AiModel }
            if ($fileConfig.TargetLanguage) { $script:Config.TargetLanguage = $fileConfig.TargetLanguage }
            if ($null -ne $fileConfig.GenerateTranscriptInWorkflow) { $script:Config.GenerateTranscriptInWorkflow = $fileConfig.GenerateTranscriptInWorkflow }

            # Backward compatibility: map old config keys
            if ($fileConfig.DownloadDir) { $script:Config.OutputDir = $fileConfig.DownloadDir }
        } catch {
            # Ignore errors, use defaults
        }
    }

    # Apply config to module variables
    Apply-ConfigToModules
}

# Save config to file
function Export-Config {
    $script:Config | ConvertTo-Json | Set-Content $script:ConfigFile -Encoding UTF8
}

# Apply configuration to all module variables
# Apply configuration to all modules
# This ensures all $script:* variables in submodules are synchronized with central config
# Each module maintains its own $script:*OutputDir for independence when used standalone
function Apply-ConfigToModules {
    $outputDir = $script:Config.OutputDir

    # Sync output directories to all modules
    $script:YtdlOutputDir = $outputDir          # download.ps1
    $script:MuxerOutputDir = $outputDir         # mux.ps1
    $script:ProcessedOutputDir = $outputDir     # process.ps1
    $script:TranscriptOutputDir = $outputDir    # transcript.ps1
    $script:TranslateOutputDir = $outputDir     # translate.ps1
    $script:WorkflowOutputDir = $outputDir      # workflow.ps1

    # Sync cookie file
    $script:YtdlCookieFile = $script:Config.CookieFile  # download.ps1

    # Sync translate settings
    $script:TargetLanguage = $script:Config.TargetLanguage     # translate.ps1

    # Sync AI client settings
    $script:AiClient_BaseUrl = $script:Config.AiBaseUrl   # ai-client.ps1
    $script:AiClient_ApiKey = $script:Config.AiApiKey     # ai-client.ps1
    $script:AiClient_Model = $script:Config.AiModel       # ai-client.ps1
}

# Load config on startup
Import-Config

#endregion

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

        Write-Host "Invalid choice! Please enter A, B, 1-4, S or Q" -ForegroundColor Red
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

function Show-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Show-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Pause-Menu {
    Write-Host ""
    Write-Host ("-" * 60) -ForegroundColor DarkGray
    Read-Host "Press Enter to return to main menu" | Out-Null
}

function Show-UrlFormats {
    Write-Host "Supports 1800+ sites via yt-dlp" -ForegroundColor Cyan
    Write-Host "Examples:" -ForegroundColor Gray
    Write-Host "  - https://www.youtube.com/watch?v=XXXXXXXXXXX" -ForegroundColor Gray
    Write-Host "  - https://www.youtube.com/live/XXXXXXXXXXX" -ForegroundColor Gray
    Write-Host "  - https://www.bilibili.com/video/BVXXXXXXXXX" -ForegroundColor Gray
    Write-Host "  - XXXXXXXXXXX (YouTube video ID)" -ForegroundColor Gray
    Write-Host ""
}

#endregion

#region Menu Option Functions

function Invoke-FullWorkflowMenu {
    Clear-Host
    Show-Header "All-in-One Workflow"

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
    }
    catch {
        Show-Error $_.Exception.Message
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

            Write-Host "Extracting video URLs from playlist..." -ForegroundColor Yellow
            try {
                $urls = Get-PlaylistVideoUrls -PlaylistUrl $playlistUrl
                Write-Host "Found $($urls.Count) videos" -ForegroundColor Green
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
    Write-Host ""
    Write-Host "Fetching video titles..." -ForegroundColor Yellow
    $previews = @()
    foreach ($url in $urls) {
        $title = Get-VideoTitle -Url $url
        $previews += @{ Url = $url; Title = $title }
        Write-Host "  $($previews.Count). $title" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "Ready to process $($urls.Count) videos" -ForegroundColor Yellow
    Write-Host "Press Enter to start or Ctrl+C to cancel..."
    Read-Host

    # Run batch workflow
    $result = Invoke-BatchWorkflow -Urls $urls

    # Offer retry if there are failures
    while ($result.Failed.Count -gt 0) {
        Write-Host ""
        $retry = Read-Host "Retry failed items? (y/n)"
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
        Write-Host "  Project: $($project.ProjectName)" -ForegroundColor Gray

        Write-Host ""
        $videoPath = Invoke-VideoDownload -Url $url -ProjectDir $project.ProjectDir
        $subCount = Invoke-SubtitleDownload -Url $url -ProjectDir $project.ProjectDir

        Write-Host ""
        Show-Success "Download complete!"
        Write-Host "  Project folder: $($project.ProjectDir)" -ForegroundColor Gray
        if ($videoPath) {
            Write-Host "  Video: $(Split-Path -Leaf $videoPath)" -ForegroundColor Gray
        }
        Write-Host "  Subtitles: $subCount files" -ForegroundColor Gray
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
        Write-Host "  Project: $($project.ProjectName)" -ForegroundColor Gray

        Write-Host ""
        $subCount = Invoke-SubtitleDownload -Url $url -ProjectDir $project.ProjectDir

        Write-Host ""
        if ($subCount -gt 0) {
            Show-Success "Subtitles downloaded!"
            Write-Host "  Project folder: $($project.ProjectDir)" -ForegroundColor Gray
            Write-Host "  Subtitle files: $subCount" -ForegroundColor Gray
        } else {
            Show-Error "No subtitles available for this video"
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

        Write-Host "Generating transcript..." -ForegroundColor Yellow
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

        Write-Host ""
        Write-Host "Translating..." -ForegroundColor Yellow
        $result = Invoke-SubtitleTranslator -InputPath $file -Quiet

        Write-Host ""
        Show-Success "Translation complete!"
        Write-Host "  Output: $($result.OutputPath)" -ForegroundColor Gray
        Write-Host "  Entries: $($result.EntryCount)" -ForegroundColor Gray
    }
    catch {
        Show-Error $_.Exception.Message
    }

    Pause-Menu
}

function Invoke-SettingsMenu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host "                          Settings" -ForegroundColor Yellow
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host ""

        Write-Host "  --- Output ---" -ForegroundColor DarkGray
        Write-Host "  [1] Output Directory:   " -NoNewline -ForegroundColor Gray
        Write-Host "$(Format-DisplayPath $script:Config.OutputDir)" -ForegroundColor White
        Write-Host ""

        Write-Host "  --- AI ---" -ForegroundColor DarkGray
        Write-Host "  [2] Provider:           " -NoNewline -ForegroundColor Gray
        Write-Host "$($script:Config.AiProvider) ($($script:Config.AiBaseUrl))" -ForegroundColor White
        Write-Host "  [3] API Key:            " -NoNewline -ForegroundColor Gray
        if ($script:Config.AiApiKey) {
            $maskedKey = $script:Config.AiApiKey.Substring(0, [Math]::Min(7, $script:Config.AiApiKey.Length)) + "****"
            Write-Host $maskedKey -ForegroundColor Green
        } else {
            Write-Host "(not set)" -ForegroundColor Yellow
        }
        Write-Host "  [4] Model:              " -NoNewline -ForegroundColor Gray
        Write-Host "$($script:Config.AiModel)" -ForegroundColor White
        Write-Host ""

        Write-Host "  --- Translation ---" -ForegroundColor DarkGray
        Write-Host "  [5] Target Language:    " -NoNewline -ForegroundColor Gray
        Write-Host "$($script:Config.TargetLanguage)" -ForegroundColor White
        Write-Host ""

        Write-Host "  --- Other ---" -ForegroundColor DarkGray
        Write-Host "  [6] Cookie File:        " -NoNewline -ForegroundColor Gray
        if ($script:Config.CookieFile -and (Test-Path $script:Config.CookieFile)) {
            Write-Host $script:Config.CookieFile -ForegroundColor Green
        } elseif ($script:Config.CookieFile) {
            Write-Host "$($script:Config.CookieFile) (not found)" -ForegroundColor Yellow
        } else {
            Write-Host "(not set)" -ForegroundColor DarkGray
        }
        Write-Host "  [7] Generate Transcript: " -NoNewline -ForegroundColor Gray
        Write-Host $(if ($script:Config.GenerateTranscriptInWorkflow) { "Enabled" } else { "Disabled" }) -ForegroundColor White
        Write-Host "  [8] Glossaries..." -ForegroundColor Gray
        Write-Host "  [R] Re-run Setup Wizard" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [B] Back" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor DarkGray
        Write-Host ""

        $choice = (Read-Host "Enter option").Trim().ToUpper()

        switch ($choice) {
            '1' {
                $newPath = Read-UserInput -Prompt "Enter new output directory"
                if ($newPath) {
                    $script:Config.OutputDir = $newPath
                    Apply-ConfigToModules
                    Export-Config
                    Write-Host "Output directory updated" -ForegroundColor Green
                    Start-Sleep -Seconds 1
                }
            }
            '2' {
                Write-Host ""
                Write-Host "  [1] OpenAI" -ForegroundColor White
                Write-Host "  [2] DeepSeek" -ForegroundColor White
                Write-Host "  [3] OpenRouter" -ForegroundColor White
                Write-Host "  [4] Custom" -ForegroundColor White
                $providerChoice = Read-Host "Select provider"
                switch ($providerChoice) {
                    '1' {
                        $script:Config.AiProvider = "openai"
                        $script:Config.AiBaseUrl = "https://api.openai.com/v1"
                    }
                    '2' {
                        $script:Config.AiProvider = "deepseek"
                        $script:Config.AiBaseUrl = "https://api.deepseek.com"
                    }
                    '3' {
                        $script:Config.AiProvider = "openrouter"
                        $script:Config.AiBaseUrl = "https://openrouter.ai/api/v1"
                    }
                    '4' {
                        $script:Config.AiProvider = "custom"
                        $customUrl = Read-Host "Enter API base URL"
                        if ($customUrl) {
                            $script:Config.AiBaseUrl = $customUrl
                        }
                    }
                }
                Apply-ConfigToModules
                Export-Config
                Write-Host "Provider updated" -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
            '3' {
                $newKey = Read-Host "Enter new API key"
                if ($newKey) {
                    $script:Config.AiApiKey = $newKey
                    Apply-ConfigToModules
                    Export-Config
                    Write-Host "API key updated" -ForegroundColor Green
                    Start-Sleep -Seconds 1
                }
            }
            '4' {
                $newModel = Read-Host "Enter model name"
                if ($newModel) {
                    $script:Config.AiModel = $newModel
                    Apply-ConfigToModules
                    Export-Config
                    Write-Host "Model updated" -ForegroundColor Green
                    Start-Sleep -Seconds 1
                }
            }
            '5' {
                Write-Host ""
                Write-Host "Common options: zh-CN, zh-TW, ja, ko, en" -ForegroundColor Gray
                $newLang = Read-Host "Enter target language code"
                if ($newLang) {
                    $script:Config.TargetLanguage = $newLang
                    Apply-ConfigToModules
                    Export-Config
                    Write-Host "Target language updated" -ForegroundColor Green
                    Start-Sleep -Seconds 1
                }
            }
            '6' {
                $newPath = Read-UserInput -Prompt "Enter cookie file path"
                if ($newPath) {
                    $script:Config.CookieFile = $newPath
                    Apply-ConfigToModules
                    Export-Config
                    if (Test-Path $newPath) {
                        Write-Host "Cookie file path updated" -ForegroundColor Green
                    } else {
                        Write-Host "Cookie file path saved (file not found yet)" -ForegroundColor Yellow
                    }
                    Start-Sleep -Seconds 1
                }
            }
            '7' {
                $script:Config.GenerateTranscriptInWorkflow = -not $script:Config.GenerateTranscriptInWorkflow
                $status = if ($script:Config.GenerateTranscriptInWorkflow) { "Enabled" } else { "Disabled" }
                Write-Host "Generate transcript in workflow: $status" -ForegroundColor Green
                Export-Config
                Start-Sleep -Seconds 1
            }
            '8' {
                Show-GlossaryMenu
            }
            'R' {
                $script:Config.FirstRun = $true
                $newConfig = Start-SetupWizard
                $script:Config = $newConfig
                Apply-ConfigToModules
                Export-Config
            }
            'B' {
                return
            }
        }
    }
}

#endregion

#region Main Menu Loop

function Start-MainMenu {
    # Check for first run
    if ($script:Config.FirstRun) {
        $newConfig = Start-SetupWizard
        $script:Config = $newConfig
        Apply-ConfigToModules
        Export-Config
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
            'S' { Invoke-SettingsMenu }
            'Q' {
                Clear-Host
                Write-Host ""
                Write-Host "Thank you for using Video Tools Suite!" -ForegroundColor Green
                Write-Host "Goodbye!" -ForegroundColor Gray
                Write-Host ""
                $running = $false
            }
        }
    }
}

#endregion

# Entry Point
Start-MainMenu
