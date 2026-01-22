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

# Display info message (cyan)
function Show-Info {
    param([string]$Message)
    Write-ColoredMessage -Message $Message -Color Cyan
}

#endregion

#region Input Utilities

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
