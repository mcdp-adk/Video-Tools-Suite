#Requires -Version 5.1

# Set UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Dot source existing scripts
. "$PSScriptRoot\process.ps1"
. "$PSScriptRoot\mux.ps1"
. "$PSScriptRoot\download.ps1"

# Config file path (in project root)
$script:ConfigFile = "$PSScriptRoot\..\config.json"

# Load config from file
function Import-Config {
    if (Test-Path $script:ConfigFile) {
        try {
            $config = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
            if ($config.CookieFile) { $script:YtdlCookieFile = $config.CookieFile }
            if ($config.DownloadDir) { $script:YtdlOutputDir = $config.DownloadDir }
            if ($config.MuxDir) { $script:MuxerOutputDir = $config.MuxDir }
            if ($config.ProcessedDir) { $script:ProcessedOutputDir = $config.ProcessedDir }
        } catch {
            # Ignore errors, use defaults
        }
    }
}

# Save config to file
function Export-Config {
    $config = @{
        CookieFile = $script:YtdlCookieFile
        DownloadDir = $script:YtdlOutputDir
        MuxDir = $script:MuxerOutputDir
        ProcessedDir = $script:ProcessedOutputDir
    }
    $config | ConvertTo-Json | Set-Content $script:ConfigFile -Encoding UTF8
}

# Load config on startup
Import-Config

#region Helper Functions

function Remove-Quotes {
    param([string]$Text)
    return $Text.Trim('"').Trim("'").Trim()
}

function Format-DisplayPath {
    param([string]$Path)
    if (-not $Path) { return "(not set)" }
    try {
        # Resolve to full path for display
        $resolved = [System.IO.Path]::GetFullPath($Path)
        return $resolved
    } catch {
        return $Path
    }
}

function Read-UserInput {
    param(
        [string]$Prompt,
        [switch]$ValidateFileExists
    )

    $input = Read-Host $Prompt
    $input = Remove-Quotes $input

    if (-not $input) {
        return $null
    }

    if ($ValidateFileExists -and -not (Test-Path $input)) {
        return @{ Error = "File not found: $input" }
    }

    return $input
}

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "                     Video Tools Suite" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  Output: $(Format-DisplayPath $script:YtdlOutputDir)" -ForegroundColor DarkGray
    Write-Host ""

    $menuItems = @(
        @{ Key = "1"; Text = "Download Video" },
        @{ Key = "2"; Text = "Download Subtitles Only" },
        @{ Key = "3"; Text = "Process Subtitle Text" },
        @{ Key = "4"; Text = "Mux Subtitle into Video" },
        @{ Key = "5"; Text = "Process + Mux (Combined)" }
    )

    foreach ($item in $menuItems) {
        Write-Host "  [$($item.Key)]" -ForegroundColor Green -NoNewline
        Write-Host " $($item.Text)" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "  [S]" -ForegroundColor Magenta -NoNewline
    Write-Host " Settings" -ForegroundColor White
    Write-Host "  [Q]" -ForegroundColor Red -NoNewline
    Write-Host " Quit" -ForegroundColor White
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host ""
}

function Get-MenuChoice {
    param([string[]]$ValidChoices = @('1', '2', '3', '4', '5', 'S', 'Q'))

    do {
        $choice = (Read-Host "Enter your choice").Trim().ToUpper()

        if ($ValidChoices -contains $choice) {
            return $choice
        }

        Write-Host "Invalid choice! Please enter 1-5, S or Q" -ForegroundColor Red
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

        Write-Host "Downloading..." -ForegroundColor Yellow
        $result = Invoke-YouTubeDownloader -InputUrl $url
        Show-Success "Video downloaded to: $result"
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
        Show-UrlFormats
        $url = Read-UserInput -Prompt "Enter URL"
        if (-not $url) {
            Show-Error "No URL provided"
            Pause-Menu
            return
        }

        Write-Host "Downloading subtitles..." -ForegroundColor Yellow
        $result = Invoke-YouTubeSubtitleDownloader -InputUrl $url
        Show-Success "Subtitles downloaded to: $result"
    }
    catch {
        Show-Error $_.Exception.Message
    }

    Pause-Menu
}

function Invoke-TextProcessorMenu {
    Clear-Host
    Show-Header "Process Subtitle Text"

    try {
        Write-Host "This will process Chinese punctuation and spacing" -ForegroundColor Cyan
        $file = Read-UserInput -Prompt "Enter subtitle file path" -ValidateFileExists
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

        Write-Host "Processing..." -ForegroundColor Yellow
        $result = Invoke-TextProcessor -InputPath $file
        Show-Success "Output file: $result"
    }
    catch {
        Show-Error $_.Exception.Message
    }

    Pause-Menu
}

function Invoke-SubtitleMuxerMenu {
    Clear-Host
    Show-Header "Mux Subtitle into Video"

    try {
        Write-Host "This will mux subtitle file into video" -ForegroundColor Cyan
        $subtitleFile = Read-UserInput -Prompt "Enter subtitle file path" -ValidateFileExists
        if (-not $subtitleFile) {
            Show-Error "No subtitle file path provided"
            Pause-Menu
            return
        }
        if ($subtitleFile -is [hashtable] -and $subtitleFile.Error) {
            Show-Error $subtitleFile.Error
            Pause-Menu
            return
        }

        $videoFile = Read-UserInput -Prompt "Enter video file path" -ValidateFileExists
        if (-not $videoFile) {
            Show-Error "No video file path provided"
            Pause-Menu
            return
        }
        if ($videoFile -is [hashtable] -and $videoFile.Error) {
            Show-Error $videoFile.Error
            Pause-Menu
            return
        }

        Write-Host "Muxing..." -ForegroundColor Yellow
        $result = Invoke-SubtitleMuxer -VideoPath $videoFile -SubtitlePath $subtitleFile
        Show-Success "Output video: $result"
    }
    catch {
        Show-Error $_.Exception.Message
    }

    Pause-Menu
}

function Invoke-CombinedOperationMenu {
    Clear-Host
    Show-Header "Process and Mux Combined"

    try {
        Write-Host "This will process subtitle text and mux into video" -ForegroundColor Cyan
        $subtitleFile = Read-UserInput -Prompt "Enter raw subtitle file path" -ValidateFileExists
        if (-not $subtitleFile) {
            Show-Error "No subtitle file path provided"
            Pause-Menu
            return
        }
        if ($subtitleFile -is [hashtable] -and $subtitleFile.Error) {
            Show-Error $subtitleFile.Error
            Pause-Menu
            return
        }

        $videoFile = Read-UserInput -Prompt "Enter video file path" -ValidateFileExists
        if (-not $videoFile) {
            Show-Error "No video file path provided"
            Pause-Menu
            return
        }
        if ($videoFile -is [hashtable] -and $videoFile.Error) {
            Show-Error $videoFile.Error
            Pause-Menu
            return
        }

        Write-Host "Step 1/2: Processing subtitle..." -ForegroundColor Yellow
        $processedSubtitle = Invoke-TextProcessor -InputPath $subtitleFile
        Show-Success "Subtitle processed"

        Write-Host "Step 2/2: Muxing into video..." -ForegroundColor Yellow
        $finalVideo = Invoke-SubtitleMuxer -VideoPath $videoFile -SubtitlePath $processedSubtitle
        Show-Success "All operations completed!"
        Write-Host "Processed subtitle: $processedSubtitle" -ForegroundColor Gray
        Write-Host "Final video: $finalVideo" -ForegroundColor Gray
    }
    catch {
        Show-Error $_.Exception.Message
    }

    Pause-Menu
}

function Invoke-SettingsMenu {
    Clear-Host
    Show-Header "Settings"

    Write-Host "Current Settings:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Cookie File:      " -ForegroundColor Gray -NoNewline
    if ($script:YtdlCookieFile -and (Test-Path $script:YtdlCookieFile)) {
        Write-Host $script:YtdlCookieFile -ForegroundColor Green
    } elseif ($script:YtdlCookieFile) {
        Write-Host "$script:YtdlCookieFile (not found)" -ForegroundColor Yellow
    } else {
        Write-Host "(not set)" -ForegroundColor DarkGray
    }
    Write-Host "  [2] Download Output:  $(Format-DisplayPath $script:YtdlOutputDir)" -ForegroundColor Gray
    Write-Host "  [3] Mux Output:       $(Format-DisplayPath $script:MuxerOutputDir)" -ForegroundColor Gray
    Write-Host "  [4] Processed Output: $(Format-DisplayPath $script:ProcessedOutputDir)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [B] Back to main menu" -ForegroundColor DarkGray
    Write-Host ""

    $choice = (Read-Host "Enter option to change (or B to go back)").Trim().ToUpper()

    switch ($choice) {
        '1' {
            $newPath = Read-UserInput -Prompt "Enter new cookie file path"
            if ($newPath) {
                $script:YtdlCookieFile = $newPath
                Export-Config
                if (Test-Path $newPath) {
                    Show-Success "Cookie file path updated and saved"
                } else {
                    Write-Host "Warning: File does not exist yet (setting saved)" -ForegroundColor Yellow
                }
                Pause-Menu
            }
        }
        '2' {
            $newPath = Read-UserInput -Prompt "Enter new download output directory"
            if ($newPath) {
                $script:YtdlOutputDir = $newPath
                Export-Config
                Show-Success "Download output directory updated and saved"
                Pause-Menu
            }
        }
        '3' {
            $newPath = Read-UserInput -Prompt "Enter new mux output directory"
            if ($newPath) {
                $script:MuxerOutputDir = $newPath
                Export-Config
                Show-Success "Mux output directory updated and saved"
                Pause-Menu
            }
        }
        '4' {
            $newPath = Read-UserInput -Prompt "Enter new processed output directory"
            if ($newPath) {
                $script:ProcessedOutputDir = $newPath
                Export-Config
                Show-Success "Processed output directory updated and saved"
                Pause-Menu
            }
        }
    }
}

#endregion

#region Main Menu Loop

function Start-MainMenu {
    $running = $true

    while ($running) {
        Show-Menu

        switch (Get-MenuChoice) {
            '1' { Invoke-YouTubeDownloadMenu }
            '2' { Invoke-SubtitleOnlyDownloadMenu }
            '3' { Invoke-TextProcessorMenu }
            '4' { Invoke-SubtitleMuxerMenu }
            '5' { Invoke-CombinedOperationMenu }
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
