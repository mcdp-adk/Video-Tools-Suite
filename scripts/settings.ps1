# Settings Menu
# Provides configuration interface for Video Tools Suite

# Load dependencies
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}
if (-not (Get-Command "Import-Config" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\config-manager.ps1"
}
if (-not (Get-Command "Show-GlossaryMenu" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\glossary.ps1"
}

function Invoke-SettingsMenu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host "                          Settings" -ForegroundColor Yellow
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host ""

        Write-Host "  --- Output ---" -ForegroundColor DarkGray
        Write-Host "  [1] Output Directory:   " -NoNewline -ForegroundColor Gray
        Write-Host "$(Format-DisplayPath $script:Config.OutputDir)" -ForegroundColor White
        Write-Host ""

        Write-Host "  --- AI ---" -ForegroundColor DarkGray
        Write-Host "  [2] Provider:           " -NoNewline -ForegroundColor Gray
        Write-Host "$($script:Config.AiProvider) ($($script:Config.AiBaseUrl))" -ForegroundColor White
        Write-Host "  [3] API Key:            " -NoNewline -ForegroundColor Gray
        if ($script:Config.AiApiKey) {
            $maskedKey = $script:Config.AiApiKey.Substring(0, [Math]::Min(7, $script:Config.AiApiKey.Length)) + "****"
            Show-Success $maskedKey
        } else {
            Show-Warning "(not set)"
        }
        Write-Host "  [4] Model:              " -NoNewline -ForegroundColor Gray
        Write-Host "$($script:Config.AiModel)" -ForegroundColor White
        Write-Host ""

        Write-Host "  --- Translation ---" -ForegroundColor DarkGray
        Write-Host "  [5] Target Language:    " -NoNewline -ForegroundColor Gray
        Write-Host "$($script:Config.TargetLanguage)" -ForegroundColor White
        Write-Host "  [6] Embed Font:         " -NoNewline -ForegroundColor Gray
        Write-Host "$($script:Config.EmbedFontFile)" -ForegroundColor White
        Write-Host ""

        Write-Host "  --- Other ---" -ForegroundColor DarkGray
        Write-Host "  [7] Cookie File:        " -NoNewline -ForegroundColor Gray
        if ($script:Config.CookieFile -and (Test-Path $script:Config.CookieFile)) {
            Show-Success $script:Config.CookieFile
        } elseif ($script:Config.CookieFile) {
            Show-Warning "$($script:Config.CookieFile) (not found)"
        } else {
            Write-Host "(not set)" -ForegroundColor DarkGray
        }
        Write-Host "  [8] Generate Transcript: " -NoNewline -ForegroundColor Gray
        Write-Host $(if ($script:Config.GenerateTranscriptInWorkflow) { "Enabled" } else { "Disabled" }) -ForegroundColor White
        Write-Host "  [9] Parallel Downloads:  " -NoNewline -ForegroundColor Gray
        Write-Host "$($script:Config.BatchParallelDownloads)" -ForegroundColor White
        Write-Host "  [0] Glossaries..." -ForegroundColor DarkGray
        Write-Host "  [R] Reset to Default" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [B] Back" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor DarkGray
        Write-Host ""

        $choice = (Read-Host "Select").Trim().ToUpper()

        switch ($choice) {
            '1' {
                $newPath = Read-UserInput -Prompt "Enter new output directory"
                if ($newPath) {
                    Set-ConfigValue -Key "OutputDir" -Value $newPath
                    Apply-ConfigToModules
                    Export-Config
                    Show-Success "Output directory updated"
                    Start-Sleep -Seconds 1
                }
            }
            '2' {
                Write-Host ""
                Write-Host "  [1] OpenAI" -ForegroundColor White
                Write-Host "  [2] DeepSeek" -ForegroundColor White
                Write-Host "  [3] OpenRouter" -ForegroundColor White
                Write-Host "  [4] Custom" -ForegroundColor White
                Write-Host ""
                $providerChoice = Read-Host "  Select [1-4]"
                switch ($providerChoice) {
                    '1' {
                        Set-ConfigValue -Key "AiProvider" -Value "openai"
                        Set-ConfigValue -Key "AiBaseUrl" -Value "https://api.openai.com/v1"
                    }
                    '2' {
                        Set-ConfigValue -Key "AiProvider" -Value "deepseek"
                        Set-ConfigValue -Key "AiBaseUrl" -Value "https://api.deepseek.com"
                    }
                    '3' {
                        Set-ConfigValue -Key "AiProvider" -Value "openrouter"
                        Set-ConfigValue -Key "AiBaseUrl" -Value "https://openrouter.ai/api/v1"
                    }
                    '4' {
                        Set-ConfigValue -Key "AiProvider" -Value "custom"
                        $customUrl = Read-Host "  Enter API base URL"
                        if ($customUrl) {
                            Set-ConfigValue -Key "AiBaseUrl" -Value $customUrl
                        }
                    }
                }
                Apply-ConfigToModules
                Export-Config
                Show-Success "Provider updated"
                Start-Sleep -Seconds 1
            }
            '3' {
                Write-Host ""
                $newKey = Read-Host "  Enter new API key"
                if ($newKey) {
                    Set-ConfigValue -Key "AiApiKey" -Value $newKey
                    Apply-ConfigToModules
                    Export-Config
                    Show-Success "API key updated"
                    Start-Sleep -Seconds 1
                }
            }
            '4' {
                Write-Host ""
                $newModel = Read-Host "  Enter model name"
                if ($newModel) {
                    Set-ConfigValue -Key "AiModel" -Value $newModel
                    Apply-ConfigToModules
                    Export-Config
                    Show-Success "Model updated"
                    Start-Sleep -Seconds 1
                }
            }
            '5' {
                Write-Host ""
                Write-Host "  [1] Chinese Simplified (zh-Hans)" -ForegroundColor White
                Write-Host "  [2] Chinese Traditional (zh-Hant)" -ForegroundColor White
                Write-Host "  [3] Japanese (ja)" -ForegroundColor White
                Write-Host "  [4] Korean (ko)" -ForegroundColor White
                Write-Host "  [5] English (en)" -ForegroundColor White
                Write-Host "  [6] Custom" -ForegroundColor White
                Write-Host ""
                $langChoice = Read-Host "  Select [1-6]"
                switch ($langChoice) {
                    '1' { Set-ConfigValue -Key "TargetLanguage" -Value 'zh-Hans' }
                    '2' { Set-ConfigValue -Key "TargetLanguage" -Value 'zh-Hant' }
                    '3' { Set-ConfigValue -Key "TargetLanguage" -Value 'ja' }
                    '4' { Set-ConfigValue -Key "TargetLanguage" -Value 'ko' }
                    '5' { Set-ConfigValue -Key "TargetLanguage" -Value 'en' }
                    '6' {
                        $customLang = Read-Host "  Enter language code"
                        if ($customLang) {
                            Set-ConfigValue -Key "TargetLanguage" -Value $customLang
                        }
                    }
                }
                Apply-ConfigToModules
                Export-Config
                Show-Success "Target language updated"
                Start-Sleep -Seconds 1
            }
            '6' {
                # Font selection
                Write-Host ""
                $fontsDir = "$PSScriptRoot\..\fonts"
                $fontFiles = @()
                if (Test-Path $fontsDir) {
                    $fontFiles = @(Get-ChildItem -Path $fontsDir -Filter "*.ttf" | Select-Object -ExpandProperty Name)
                }

                if ($fontFiles.Count -eq 0) {
                    Show-Warning "No fonts found in fonts/ directory"
                    Start-Sleep -Seconds 1
                } else {
                    for ($i = 0; $i -lt $fontFiles.Count; $i++) {
                        $label = if ($fontFiles[$i] -eq $script:Config.EmbedFontFile) { "$($fontFiles[$i]) (current)" } else { $fontFiles[$i] }
                        Write-Host "  [$($i + 1)] $label" -ForegroundColor White
                    }
                    Write-Host ""
                    $fontChoice = Read-Host "  Select font [1-$($fontFiles.Count)]"
                    if ($fontChoice -match '^\d+$') {
                        $idx = [int]$fontChoice - 1
                        if ($idx -ge 0 -and $idx -lt $fontFiles.Count) {
                            Set-ConfigValue -Key "EmbedFontFile" -Value $fontFiles[$idx]
                            Apply-ConfigToModules
                            Export-Config
                            Show-Success "  Embed font set to $($fontFiles[$idx])"
                            Start-Sleep -Seconds 1
                        }
                    }
                }
            }
            '7' {
                $newPath = Read-UserInput -Prompt "Enter cookie file path"
                if ($newPath) {
                    Set-ConfigValue -Key "CookieFile" -Value $newPath
                    Apply-ConfigToModules
                    Export-Config
                    if (Test-Path $newPath) {
                        Show-Success "Cookie file path updated"
                    } else {
                        Show-Warning "Cookie file path saved (file not found yet)"
                    }
                    Start-Sleep -Seconds 1
                }
            }
            '8' {
                $current = Get-ConfigValue -Key "GenerateTranscriptInWorkflow"
                Set-ConfigValue -Key "GenerateTranscriptInWorkflow" -Value (-not $current)
                $status = if (-not $current) { "Enabled" } else { "Disabled" }
                Apply-ConfigToModules
                Export-Config
                Show-Success "Generate transcript in workflow: $status"
                Start-Sleep -Seconds 1
            }
            '9' {
                Write-Host ""
                Write-Host "  Enter parallel download count (1-10):" -ForegroundColor Gray
                $currentVal = Get-ConfigValue -Key "BatchParallelDownloads"
                $input = Read-Host "  [default: $currentVal]"
                if (-not $input) {
                    # Keep current value
                }
                elseif ($input -match '^\d+$' -and [int]$input -ge 1 -and [int]$input -le 10) {
                    Set-ConfigValue -Key "BatchParallelDownloads" -Value ([int]$input)
                    Apply-ConfigToModules
                    Export-Config
                    Show-Success "  Parallel downloads set to $input"
                    Start-Sleep -Seconds 1
                }
                else {
                    Show-Error "  Invalid input. Must be 1-10."
                    Start-Sleep -Seconds 1
                }
            }
            '0' {
                Show-GlossaryMenu
            }
            'R' {
                Write-Host ""
                Write-Host "  This will reset all settings to default." -ForegroundColor Yellow
                $confirm = Read-Host "  Continue? (Y/N)"
                if ($confirm -ieq 'Y') {
                    Reset-Config
                    Show-Success "  Settings reset. Returning to main menu..."
                    Start-Sleep -Seconds 1
                    return "reset"
                }
            }
            'B' {
                return
            }
        }
    }
}
