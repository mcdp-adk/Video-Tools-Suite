# Glossary management module for terminology control in translations
# Glossaries are stored as CSV files in the glossaries/ directory
# Format: source,target (no header row required, but supported)

# Import utilities
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}

# Configuration
$script:GlossaryDir = "$PSScriptRoot\..\glossaries"

#region Core Functions

# Get all glossary files
function Get-GlossaryFiles {
    if (-not (Test-Path $script:GlossaryDir)) {
        return @()
    }

    return Get-ChildItem -Path $script:GlossaryDir -Filter "*.csv" | Sort-Object Name
}

# Load a single glossary from CSV
function Import-Glossary {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Glossary file not found: $Path"
    }

    try {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $terms = @{}

        $lines = Get-Content $Path -Encoding UTF8

        foreach ($line in $lines) {
            $line = $line.Trim()
            if (-not $line) { continue }

            # Skip header row if present
            if ($line -match '^source,target') { continue }

            # Parse CSV line (handle commas in values)
            $parts = $line -split ',', 2
            if ($parts.Count -ge 2) {
                $source = $parts[0].Trim()
                # Remove tgt_lng column if present (third column)
                $target = ($parts[1] -split ',')[0].Trim()

                if ($source -and $target) {
                    $terms[$source] = $target
                }
            }
        }

        return @{
            Name = $fileName
            Terms = $terms
            Path = $Path
        }
    }
    catch {
        throw "Failed to parse glossary file: $_"
    }
}

# Get all terms from all glossaries merged
function Get-AllGlossaryTerms {
    $allTerms = @{}

    $files = Get-GlossaryFiles

    foreach ($file in $files) {
        try {
            $glossary = Import-Glossary -Path $file.FullName

            foreach ($key in $glossary.Terms.Keys) {
                if (-not $allTerms.ContainsKey($key)) {
                    $allTerms[$key] = $glossary.Terms[$key]
                }
            }
        }
        catch {
            Write-Warning "Failed to load glossary $($file.Name): $_"
        }
    }

    return $allTerms
}

# Get list of all glossaries with metadata
function Get-GlossaryList {
    $glossaries = @()

    $files = Get-GlossaryFiles

    foreach ($file in $files) {
        try {
            $glossary = Import-Glossary -Path $file.FullName
            $glossaries += @{
                FileName = $file.Name
                Path = $file.FullName
                Name = $glossary.Name
                TermCount = $glossary.Terms.Count
            }
        }
        catch {
            $glossaries += @{
                FileName = $file.Name
                Path = $file.FullName
                Name = "[Error loading]"
                TermCount = 0
            }
        }
    }

    return $glossaries
}

#endregion

#region TUI Functions

# Show glossary viewer (read-only)
function Show-GlossaryMenu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host "                      Glossary Viewer" -ForegroundColor Yellow
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host ""

        $glossaries = Get-GlossaryList

        if ($glossaries.Count -eq 0) {
            Write-Host "  No glossaries found." -ForegroundColor DarkGray
            Write-Host "  Add CSV files to glossaries/ directory." -ForegroundColor DarkGray
        }
        else {
            $index = 1
            foreach ($g in $glossaries) {
                Write-Host "  [$index]" -ForegroundColor Green -NoNewline
                Write-Host " $($g.Name)" -ForegroundColor White -NoNewline
                Write-Host " ($($g.TermCount) terms)" -ForegroundColor DarkGray
                $index++
            }
        }

        Write-Host ""
        Show-ActionKey -Key "B" -Label "Back" -Type "navigation"
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor DarkGray
        Write-Host ""

        $choice = (Read-Host "Select").Trim().ToUpper()

        if ($choice -eq 'B') {
            return
        }
        elseif ($choice -match '^\d+$') {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $glossaries.Count) {
                Show-GlossaryTerms -GlossaryPath $glossaries[$idx].Path
            }
            else {
                Show-Error "Invalid selection"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Show terms in a glossary (read-only)
function Show-GlossaryTerms {
    param(
        [Parameter(Mandatory=$true)]
        [string]$GlossaryPath
    )

    Clear-Host

    try {
        $glossary = Import-Glossary -Path $GlossaryPath
    }
    catch {
        Show-Error "Error loading glossary: $_"
        Start-Sleep -Seconds 2
        return
    }

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    $title = $glossary.Name
    $padding = [Math]::Max(0, [Math]::Floor((60 - $title.Length) / 2))
    Write-Host (" " * $padding + $title) -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""

    $terms = $glossary.Terms.GetEnumerator() | Sort-Object Name
    $termCount = @($terms).Count

    if ($termCount -eq 0) {
        Write-Host "  No terms defined." -ForegroundColor DarkGray
    }
    else {
        Write-Host "  Terms ($termCount):" -ForegroundColor Cyan
        Write-Host ""
        foreach ($term in $terms) {
            Write-Host "    $($term.Key)" -ForegroundColor White -NoNewline
            Write-Host " -> " -ForegroundColor DarkGray -NoNewline
            Write-Host "$($term.Value)" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host ("-" * 60) -ForegroundColor DarkGray
    Write-Host "  Edit: $GlossaryPath" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "Press Enter to go back" | Out-Null
}

#endregion
