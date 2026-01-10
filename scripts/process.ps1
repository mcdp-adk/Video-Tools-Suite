# Command-line parameter (must be first for dot sourcing compatibility)
param([string]$InputPath)

# Configuration
$script:ProcessedOutputDir = "$PSScriptRoot\..\output"

# Configuration: Chinese punctuation marks to replace with space
$script:PunctuationToReplace = @(
    [char]0xFF0C,  # Fullwidth Comma (，)
    [char]0x3002,  # Ideographic Full Stop (。)
    [char]0x3001   # Ideographic Comma (、)
)

# Function interface for TUI integration
function Invoke-TextProcessor {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath
    )

    if (-not (Test-Path $InputPath)) {
        throw "File not found: $InputPath"
    }

    # Ensure output directory exists
    if (-not (Test-Path $script:ProcessedOutputDir)) {
        New-Item -ItemType Directory -Path $script:ProcessedOutputDir -Force | Out-Null
    }

    # Build output path
    $file = Get-Item $InputPath
    $outputPath = Join-Path $script:ProcessedOutputDir "$($file.BaseName)_processed$($file.Extension)"

    # Read file content
    $content = [System.IO.File]::ReadAllText($InputPath, [System.Text.Encoding]::UTF8)

    # Replace Chinese punctuation marks with space
    foreach ($punct in $script:PunctuationToReplace) {
        $content = $content.Replace($punct, ' ')
    }

    # Add spacing between Chinese characters and alphanumeric characters
    $content = $content -replace '([\u4E00-\u9FFF])([a-zA-Z0-9])', '$1 $2'
    $content = $content -replace '([a-zA-Z0-9])([\u4E00-\u9FFF])', '$1 $2'

    # Write output with UTF-8 BOM for player compatibility
    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($outputPath, $content, $utf8WithBom)

    return $outputPath
}

# Command-line interface (when script is called directly)
if ($InputPath) {
    try {
        Write-Host "Processing: $(Split-Path -Leaf $InputPath)" -ForegroundColor Cyan
        $result = Invoke-TextProcessor -InputPath $InputPath
        Write-Host "Success! Output:" -ForegroundColor Green
        Write-Host $result -ForegroundColor Gray
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        exit 1
    }
} elseif ($MyInvocation.InvocationName -ne '.') {
    Write-Host "Usage: process.bat <input_file>" -ForegroundColor Yellow
    exit 1
}
