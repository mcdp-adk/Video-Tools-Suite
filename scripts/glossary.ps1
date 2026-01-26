# Glossary management module for terminology control in translations
# Glossaries are stored as JSON files in the glossaries/ directory

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

    return Get-ChildItem -Path $script:GlossaryDir -Filter "*.json" | Sort-Object Name
}

# Load a single glossary
function Import-Glossary {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Glossary file not found: $Path"
    }

    try {
        $content = Get-Content $Path -Raw -Encoding UTF8
        $glossary = $content | ConvertFrom-Json

        return @{
            Name = $glossary.name
            Description = $glossary.description
            Terms = @{}
            Path = $Path
        } | ForEach-Object {
            # Convert PSObject to hashtable for terms
            $result = $_
            if ($glossary.terms) {
                $glossary.terms.PSObject.Properties | ForEach-Object {
                    $result.Terms[$_.Name] = $_.Value
                }
            }
            $result
        }
    }
    catch {
        throw "Failed to parse glossary file: $_"
    }
}

# Save a glossary to file
function Export-Glossary {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [string]$Description = "",
        [Parameter(Mandatory=$true)]
        [hashtable]$Terms
    )

    $glossary = @{
        name = $Name
        description = $Description
        terms = $Terms
    }

    $json = $glossary | ConvertTo-Json -Depth 5
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)

    return $Path
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
                Description = $glossary.Description
                TermCount = $glossary.Terms.Count
            }
        }
        catch {
            $glossaries += @{
                FileName = $file.Name
                Path = $file.FullName
                Name = "[Error loading]"
                Description = ""
                TermCount = 0
            }
        }
    }

    return $glossaries
}

#endregion

#region Edit Functions

# Add or update a term in a glossary
function Set-GlossaryTerm {
    param(
        [Parameter(Mandatory=$true)]
        [string]$GlossaryPath,
        [Parameter(Mandatory=$true)]
        [string]$SourceTerm,
        [Parameter(Mandatory=$true)]
        [string]$TargetTerm
    )

    $glossary = Import-Glossary -Path $GlossaryPath
    $glossary.Terms[$SourceTerm] = $TargetTerm

    Export-Glossary -Path $GlossaryPath -Name $glossary.Name -Description $glossary.Description -Terms $glossary.Terms

    return $glossary
}

# Remove a term from a glossary
function Remove-GlossaryTerm {
    param(
        [Parameter(Mandatory=$true)]
        [string]$GlossaryPath,
        [Parameter(Mandatory=$true)]
        [string]$SourceTerm
    )

    $glossary = Import-Glossary -Path $GlossaryPath

    if ($glossary.Terms.ContainsKey($SourceTerm)) {
        $glossary.Terms.Remove($SourceTerm)
        Export-Glossary -Path $GlossaryPath -Name $glossary.Name -Description $glossary.Description -Terms $glossary.Terms
        return $true
    }

    return $false
}

# Create a new glossary
function New-Glossary {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [string]$Description = "",
        [string]$FileName = ""
    )

    if (-not $FileName) {
        # Generate filename from name
        $FileName = ($Name -replace '[^a-zA-Z0-9]', '-').ToLower() + ".json"
    }

    if (-not (Test-Path $script:GlossaryDir)) {
        New-Item -ItemType Directory -Path $script:GlossaryDir -Force | Out-Null
    }

    $path = Join-Path $script:GlossaryDir $FileName

    if (Test-Path $path) {
        throw "Glossary file already exists: $FileName"
    }

    Export-Glossary -Path $path -Name $Name -Description $Description -Terms @{}

    return $path
}

# Delete a glossary file
function Remove-Glossary {
    param(
        [Parameter(Mandatory=$true)]
        [string]$GlossaryPath
    )

    if (Test-Path $GlossaryPath) {
        Remove-Item $GlossaryPath -Force
        return $true
    }

    return $false
}

#endregion

#region TUI Functions

# Show glossary management menu
function Show-GlossaryMenu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host "                      Glossary Manager" -ForegroundColor Yellow
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host ""

        $glossaries = Get-GlossaryList

        if ($glossaries.Count -eq 0) {
            Write-Host "  No glossaries found." -ForegroundColor DarkGray
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
        Write-Host "  [N]" -ForegroundColor Magenta -NoNewline
        Write-Host " Create New Glossary" -ForegroundColor White
        Write-Host "  [B]" -ForegroundColor DarkGray -NoNewline
        Write-Host " Back" -ForegroundColor White
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor DarkGray
        Write-Host ""

        $choice = (Read-Host "Select").Trim().ToUpper()

        if ($choice -eq 'B') {
            return
        }
        elseif ($choice -eq 'N') {
            Invoke-NewGlossaryPrompt
        }
        elseif ($choice -match '^\d+$') {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $glossaries.Count) {
                Edit-GlossaryInteractive -GlossaryPath $glossaries[$idx].Path
            }
            else {
                Show-Error "Invalid selection"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Create new glossary interactively
function Invoke-NewGlossaryPrompt {
    Write-Host ""
    $name = Read-Host "Enter glossary name"
    if (-not $name) {
        Show-Warning "Cancelled"
        Start-Sleep -Seconds 1
        return
    }

    $description = Read-Host "Enter description (optional)"

    try {
        $path = New-Glossary -Name $name -Description $description
        Show-Success "Created: $path"
        Start-Sleep -Seconds 1
    }
    catch {
        Show-Error "Error: $_"
        Start-Sleep -Seconds 2
    }
}

# Edit a glossary interactively
function Edit-GlossaryInteractive {
    param(
        [Parameter(Mandatory=$true)]
        [string]$GlossaryPath
    )

    while ($true) {
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
        $title = "Editing: $($glossary.Name)"
        $padding = [Math]::Max(0, [Math]::Floor((60 - $title.Length) / 2))
        Write-Host (" " * $padding + $title) -ForegroundColor Yellow
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host ""

        if ($glossary.Description) {
            Write-Host "  $($glossary.Description)" -ForegroundColor DarkGray
            Write-Host ""
        }

        $terms = $glossary.Terms.GetEnumerator() | Sort-Object Name
        $termCount = @($terms).Count

        if ($termCount -eq 0) {
            Write-Host "  No terms defined." -ForegroundColor DarkGray
        }
        else {
            Write-Host "  Terms ($termCount):" -ForegroundColor Cyan
            foreach ($term in $terms) {
                Write-Host "    $($term.Key)" -ForegroundColor White -NoNewline
                Write-Host " -> " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($term.Value)" -ForegroundColor Green
            }
        }

        Write-Host ""
        Write-Host "  [A]" -ForegroundColor Green -NoNewline
        Write-Host " Add/Update Term" -ForegroundColor White
        Write-Host "  [R]" -ForegroundColor Yellow -NoNewline
        Write-Host " Remove Term" -ForegroundColor White
        Write-Host "  [D]" -ForegroundColor Red -NoNewline
        Write-Host " Delete Glossary" -ForegroundColor White
        Write-Host "  [B]" -ForegroundColor DarkGray -NoNewline
        Write-Host " Back" -ForegroundColor White
        Write-Host ""

        $choice = (Read-Host "Select").Trim().ToUpper()

        switch ($choice) {
            'A' {
                Write-Host ""
                $source = Read-Host "Enter source term"
                if ($source) {
                    $target = Read-Host "Enter translation"
                    if ($target) {
                        Set-GlossaryTerm -GlossaryPath $GlossaryPath -SourceTerm $source -TargetTerm $target
                        Show-Success "Term added/updated"
                        Start-Sleep -Seconds 1
                    }
                }
            }
            'R' {
                Write-Host ""
                $source = Read-Host "Enter term to remove"
                if ($source) {
                    if (Remove-GlossaryTerm -GlossaryPath $GlossaryPath -SourceTerm $source) {
                        Show-Success "Term removed"
                    }
                    else {
                        Show-Warning "Term not found"
                    }
                    Start-Sleep -Seconds 1
                }
            }
            'D' {
                Write-Host ""
                $confirm = Read-Host "Delete this glossary? (Y/N)"
                if ($confirm -ieq 'Y') {
                    Remove-Glossary -GlossaryPath $GlossaryPath
                    Show-Success "Glossary deleted"
                    Start-Sleep -Seconds 1
                    return
                }
            }
            'B' {
                return
            }
        }
    }
}

#endregion
