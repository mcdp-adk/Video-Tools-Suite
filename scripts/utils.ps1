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
