# Video Tools Suite - Common Utilities
# Shared helper functions used across modules

#region String Utilities

# Remove surrounding quotes from a string
function Remove-Quotes {
    param([string]$Text)
    return $Text.Trim('"').Trim("'").Trim()
}

# Format a path for display (resolve to full path)
function Format-DisplayPath {
    param([string]$Path)
    if (-not $Path) { return "(not set)" }
    try {
        $resolved = [System.IO.Path]::GetFullPath($Path)
        return $resolved
    } catch {
        return $Path
    }
}

#endregion

#region Message Utilities

# Internal helper for colored messages
function Write-ColoredMessage {
    param(
        [string]$Message,
        [string]$Color
    )
    Write-Host $Message -ForegroundColor $Color
}

# Display success message (green)
function Show-Success {
    param([string]$Message)
    Write-ColoredMessage -Message $Message -Color Green
}

# Display error message (red)
function Show-Error {
    param([string]$Message)
    Write-ColoredMessage -Message $Message -Color Red
}

# Display warning message (yellow)
function Show-Warning {
    param([string]$Message)
    Write-ColoredMessage -Message $Message -Color Yellow
}

# Display info message (cyan) - progress, loading, processing
# Auto adds blank line before (use -NoBlankBefore to disable)
function Show-Info {
    param(
        [string]$Message,
        [switch]$NoBlankBefore
    )
    if (-not $NoBlankBefore) { Write-Host "" }
    Write-ColoredMessage -Message $Message -Color Cyan
}

# Display step indicator (magenta) - "[Step X/Y] ..." progress steps
# Auto adds blank line before (use -NoBlankBefore to disable)
function Show-Step {
    param(
        [string]$Message,
        [switch]$NoBlankBefore
    )
    if (-not $NoBlankBefore) { Write-Host "" }
    Write-ColoredMessage -Message $Message -Color Magenta
}

# Display detail message (gray) - secondary info, key-value pairs
# Auto indents with 2 spaces per indent level (default: 1)
function Show-Detail {
    param(
        [string]$Message,
        [int]$Indent = 1
    )
    $prefix = "  " * $Indent
    Write-ColoredMessage -Message "$prefix$Message" -Color Gray
}

# Display hint message (dark gray) - descriptions, help text, examples
# Auto indents with 2 spaces per indent level (default: 1)
function Show-Hint {
    param(
        [string]$Message,
        [int]$Indent = 1
    )
    $prefix = "  " * $Indent
    Write-ColoredMessage -Message "$prefix$Message" -Color DarkGray
}

# Display action key with consistent styling
# Types: navigation, confirm, danger, action, setting, warning
function Show-ActionKey {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key,
        [Parameter(Mandatory=$true)]
        [string]$Label,
        [ValidateSet("navigation", "confirm", "danger", "action", "setting", "warning")]
        [string]$Type = "navigation"
    )

    $colors = @{
        "navigation" = "DarkGray"
        "confirm"    = "Green"
        "danger"     = "Red"
        "action"     = "Magenta"
        "setting"    = "Cyan"
        "warning"    = "Yellow"
    }

    Write-Host "  [$Key]" -ForegroundColor $colors[$Type] -NoNewline
    Write-Host " $Label" -ForegroundColor White
}

# Display navigation hint line with common action keys
function Show-ActionHint {
    param(
        [switch]$Back,
        [switch]$Default,
        [switch]$Confirm,
        [switch]$Cancel
    )

    $hints = @()
    if ($Back) { $hints += "[B] Back" }
    if ($Default) { $hints += "[D] Default" }
    if ($Confirm) { $hints += "[C] Confirm" }
    if ($Cancel) { $hints += "[X] Cancel" }

    if ($hints.Count -gt 0) {
        Write-Host ""
        Show-Hint ($hints -join "  ")
    }
}

#endregion

#region Input Utilities

# Unified Y/N confirmation prompt
function Read-Confirmation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt
    )

    $response = Read-Host "  $Prompt (Y/N)"
    return $response -ieq 'Y'
}

# Wait with countdown, auto-start after timeout or immediate start on Enter
# Returns $true if started (timeout or Enter), $false if cancelled (Ctrl+C handled by caller)
function Wait-WithCountdown {
    param(
        [int]$Seconds = 20,
        [string]$Message = "Starting in {0} seconds... (Press Enter to start now, Ctrl+C to cancel)"
    )

    for ($i = $Seconds; $i -gt 0; $i--) {
        $displayMsg = $Message -f $i
        Write-Host "`r$displayMsg    " -NoNewline -ForegroundColor Yellow

        # Check for key press (non-blocking) - may fail in non-interactive mode
        $waited = 0
        while ($waited -lt 1000) {
            try {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -eq 'Enter') {
                        Write-Host "`r$(' ' * ($displayMsg.Length + 4))" -NoNewline
                        Write-Host "`rStarting now..." -ForegroundColor Green
                        return $true
                    }
                }
            } catch {
                # Non-interactive mode - just wait without key check
            }
            Start-Sleep -Milliseconds 100
            $waited += 100
        }
    }

    Write-Host "`r$(' ' * 80)" -NoNewline
    Write-Host "`rCountdown complete, starting..." -ForegroundColor Green
    return $true
}

# Read user input with optional file validation
function Read-UserInput {
    param(
        [string]$Prompt,
        [switch]$ValidateFileExists
    )

    $userInput = Read-Host $Prompt
    $userInput = Remove-Quotes $userInput

    if (-not $userInput) {
        return $null
    }

    if ($ValidateFileExists -and -not (Test-Path -LiteralPath $userInput)) {
        return @{ Error = "File not found: $userInput" }
    }

    return $userInput
}

#endregion
