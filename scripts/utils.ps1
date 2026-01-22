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
