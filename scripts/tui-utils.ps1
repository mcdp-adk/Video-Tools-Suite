# TUI utilities for progress display and window title management
# Provides emoji-based window titles and progress bar functions

#region Window Title

# Emoji constants for window titles (using Unicode escape)
$script:TitleEmoji = @{
    Download = [char]::ConvertFromUtf32(0x1F4E5)
    Transcript = [char]::ConvertFromUtf32(0x1F4DD)
    Translate = [char]::ConvertFromUtf32(0x1F310)
    Mux = [char]::ConvertFromUtf32(0x1F3AC)
}

# Set window title with emoji prefix
function Set-VtsWindowTitle {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Download', 'Transcript', 'Translate', 'Mux')]
        [string]$Phase,
        [Parameter(Mandatory=$true)]
        [string]$Status
    )
    $emoji = $script:TitleEmoji[$Phase]
    $Host.UI.RawUI.WindowTitle = "$emoji $Status"
}

# Save current window title
function Save-WindowTitle {
    return $Host.UI.RawUI.WindowTitle
}

# Restore saved window title
function Restore-WindowTitle {
    param([string]$Title)
    $Host.UI.RawUI.WindowTitle = $Title
}

#endregion

#region Status Icons

# Status icons for TUI display
$script:StatusIcon = @{
    Waiting = [char]::ConvertFromUtf32(0x23F8)
    InProgress = [char]::ConvertFromUtf32(0x23F3)
    Done = [char]::ConvertFromUtf32(0x2705)
    Failed = [char]::ConvertFromUtf32(0x274C)
    Skipped = [char]::ConvertFromUtf32(0x23ED)
}

# Get status icon by name
function Get-StatusIcon {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Waiting', 'InProgress', 'Done', 'Failed', 'Skipped')]
        [string]$Status
    )
    return $script:StatusIcon[$Status]
}

#endregion

#region Progress Display

# Create progress bar string
function New-ProgressBar {
    param(
        [Parameter(Mandatory=$true)]
        [int]$Current,
        [Parameter(Mandatory=$true)]
        [int]$Total,
        [int]$Width = 20
    )

    if ($Total -eq 0) {
        $emptyChar = [char]::ConvertFromUtf32(0x2591)
        return "[" + ($emptyChar * $Width) + "] 0/0"
    }

    $percent = $Current / $Total
    $filled = [math]::Floor($percent * $Width)
    $empty = $Width - $filled

    $filledChar = [char]::ConvertFromUtf32(0x2588)
    $emptyChar = [char]::ConvertFromUtf32(0x2591)

    $bar = ($filledChar * $filled) + ($emptyChar * $empty)
    return "[$bar] $Current/$Total"
}

# Write text at specific cursor position (for TUI refresh)
function Write-AtPosition {
    param(
        [Parameter(Mandatory=$true)]
        [int]$X,
        [Parameter(Mandatory=$true)]
        [int]$Y,
        [Parameter(Mandatory=$true)]
        [string]$Text,
        [string]$Color = "White",
        [int]$ClearWidth = 0
    )

    # Save current cursor position
    $savedPos = $Host.UI.RawUI.CursorPosition

    # Move to target position
    $Host.UI.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new($X, $Y)

    # Write text
    Write-Host $Text -ForegroundColor $Color -NoNewline

    # Clear remaining space if specified
    if ($ClearWidth -gt 0) {
        $remaining = $ClearWidth - $Text.Length
        if ($remaining -gt 0) {
            Write-Host (" " * $remaining) -NoNewline
        }
    }

    # Restore cursor position
    $Host.UI.RawUI.CursorPosition = $savedPos
}

# Clear a line at specific Y position
function Clear-Line {
    param(
        [Parameter(Mandatory=$true)]
        [int]$Y,
        [int]$Width = 80
    )

    $savedPos = $Host.UI.RawUI.CursorPosition
    $Host.UI.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, $Y)
    Write-Host (" " * $Width) -NoNewline
    $Host.UI.RawUI.CursorPosition = $savedPos
}

# Get current cursor Y position
function Get-CursorY {
    return $Host.UI.RawUI.CursorPosition.Y
}

#endregion

#region Slot Display

# Format a slot display line
function Format-SlotLine {
    param(
        [Parameter(Mandatory=$true)]
        [int]$SlotNumber,
        [string]$VideoId = "",
        [string]$Title = "",
        [string]$Status = "Waiting...",
        [string]$StatusType = "Waiting"
    )

    $icon = Get-StatusIcon -Status $StatusType

    # Truncate title if too long
    $maxTitleLen = 35
    if ($Title.Length -gt $maxTitleLen) {
        $Title = $Title.Substring(0, $maxTitleLen - 3) + "..."
    }

    $videoDisplay = if ($VideoId) { "[$VideoId]" } else { "" }

    $line1 = "  Slot ${SlotNumber}: $videoDisplay $Title"
    $line2 = "          $icon $Status"
    return "$line1`n$line2"
}

#endregion
