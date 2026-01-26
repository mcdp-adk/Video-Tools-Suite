# Glossary management module for terminology control in translations
# Glossaries are stored as CSV files in the glossaries/ directory
# Format: source,target (no header row required, but supported)

# Import utilities
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}
if (-not (Get-Command "Invoke-AiCompletion" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\ai-client.ps1"
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

#region Glossary Matching Functions

# Get all glossary names (without extension)
function Get-GlossaryNames {
    $files = Get-GlossaryFiles
    return @($files | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
}

# Get content sample for analysis
function Get-ContentSample {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries,
        [int]$SampleSize = 50
    )

    $total = $Entries.Count

    if ($total -lt $SampleSize) {
        return @($Entries | ForEach-Object { $_.Text })
    }

    # Skip first/last 10%, sample from middle 80%
    $skipCount = [math]::Floor($total * 0.1)
    $middleEntries = @($Entries[$skipCount..($total - $skipCount - 1)])

    # Evenly sample
    $step = [math]::Max(1, [math]::Floor($middleEntries.Count / $SampleSize))
    $sampled = @()
    for ($i = 0; $i -lt $middleEntries.Count -and $sampled.Count -lt $SampleSize; $i += $step) {
        $sampled += $middleEntries[$i].Text
    }

    return $sampled
}

# Select relevant glossaries based on content analysis (by glossary name)
function Select-RelevantGlossaries {
    param(
        [Parameter(Mandatory=$false)]
        [array]$Entries = @(),
        [switch]$Quiet
    )

    # Guard against empty entries
    if (-not $Entries -or $Entries.Count -eq 0) {
        return @()
    }

    # Get glossary names
    $glossaryNames = Get-GlossaryNames
    if ($glossaryNames.Count -eq 0) {
        return @()
    }

    # Sample content: <50 use all, >=50 sample 50 from middle 80%
    $sampleTexts = Get-ContentSample -Entries $Entries -SampleSize 50

    $systemPrompt = @"
You are a content analyzer. Based on the subtitle content, select relevant glossaries by name.
Available glossaries: $($glossaryNames -join ', ')

Return ONLY a JSON array of glossary names, e.g. ["mufc", "sports"]
Select at most 3 most relevant glossaries.
If no glossary is relevant, return []
"@

    $userPrompt = "Subtitle sample:`n$($sampleTexts -join "`n")`n`nWhich glossaries are relevant?"

    try {
        $response = Invoke-AiCompletion -SystemPrompt $systemPrompt -UserPrompt $userPrompt -Temperature 0.1 -MaxTokens 256

        # Parse JSON response
        if ($response -match '\[.*\]') {
            $selected = $Matches[0] | ConvertFrom-Json
            # Filter to valid names only
            return @($selected | Where-Object { $glossaryNames -contains $_ })
        }
    } catch {
        if (-not $Quiet) { Write-Warning "Glossary matching failed: $_" }
    }

    return @()
}

# Get terms from selected glossaries
function Get-SelectedGlossaryTerms {
    param(
        [Parameter(Mandatory=$true)]
        [array]$GlossaryNames
    )

    $terms = @{}
    $files = Get-GlossaryFiles

    foreach ($file in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        if ($GlossaryNames -contains $name) {
            try {
                $glossary = Import-Glossary -Path $file.FullName
                foreach ($key in $glossary.Terms.Keys) {
                    if (-not $terms.ContainsKey($key)) {
                        $terms[$key] = $glossary.Terms[$key]
                    }
                }
            } catch {}
        }
    }

    return $terms
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
