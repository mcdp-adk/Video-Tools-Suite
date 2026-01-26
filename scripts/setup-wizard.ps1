# First-run setup wizard
# Guides users through initial configuration with back/forward navigation

# Dot source dependencies if not already loaded
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}
if (-not (Get-Command "Import-Config" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\config-manager.ps1"
}
if (-not (Get-Command "Get-LanguageDisplayName" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\lang-config.ps1"
}
if (-not (Get-Command "Test-AiConnection" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\ai-client.ps1"
}

#region Step Functions

function Show-WizardHeader {
    param([int]$Step, [int]$Total = 6, [string]$Title)
    Clear-Host
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "                Welcome to Video Tools Suite!" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
    Show-Step "Step $Step/$Total`: $Title"
    Write-Host ""
}

function Show-NavigationHint {
    param([bool]$CanGoBack = $true)
    Write-Host ""
    if ($CanGoBack) {
        Show-Hint "Type 'b' to go back to previous step"
    }
}

function Invoke-Step1-OutputDir {
    Show-WizardHeader -Step 1 -Title "Output Directory"
    Show-Detail "Where should files be saved?"
    Write-Host ""

    $currentValue = Get-ConfigValue -Key "OutputDir"
    $input = Read-Host "  [$currentValue]"

    if ($input -eq 'b') { return 'back' }
    if ($input) {
        Set-ConfigValue -Key "OutputDir" -Value $input
    }

    Show-Success "Output: $(Get-ConfigValue -Key 'OutputDir')"
    return 'next'
}

function Invoke-Step2-CookieFile {
    Show-WizardHeader -Step 2 -Title "Cookie File"
    Show-Detail "For downloading videos (especially age-restricted or member-only),"
    Show-Detail "you need to provide a cookie file exported from your browser."
    Show-NavigationHint
    Write-Host ""

    while ($true) {
        $cookiePath = Read-Host "  Enter cookie file path (or 'b' to go back)"

        if ($cookiePath -eq 'b') { return 'back' }

        if (-not $cookiePath) {
            Show-Error "Cookie file is required. Please enter a valid path."
            continue
        }

        if (-not (Test-Path $cookiePath)) {
            Show-Error "File not found: $cookiePath"
            Show-Warning "Please check the path and try again."
            continue
        }

        Set-ConfigValue -Key "CookieFile" -Value $cookiePath
        Show-Success "Cookie file set: $cookiePath"
        return 'next'
    }
}

function Invoke-Step3-AiProvider {
    Show-WizardHeader -Step 3 -Title "AI Provider"

    Write-Host "  [1] OpenAI (Recommended)" -ForegroundColor White
    Show-Hint "https://api.openai.com/v1" -Indent 2
    Write-Host ""
    Write-Host "  [2] DeepSeek" -ForegroundColor White
    Show-Hint "https://api.deepseek.com" -Indent 2
    Write-Host ""
    Write-Host "  [3] OpenRouter" -ForegroundColor White
    Show-Hint "https://openrouter.ai/api/v1" -Indent 2
    Write-Host ""
    Write-Host "  [4] Custom" -ForegroundColor White
    Show-Hint "Enter your own API endpoint" -Indent 2
    Show-NavigationHint
    Write-Host ""

    while ($true) {
        $choice = Read-Host "  Select [1-4, default=1, 'b' to go back]"

        if ($choice -eq 'b') { return 'back' }
        if (-not $choice) { $choice = '1' }

        if ($choice -notmatch '^[1234]$') {
            Show-Error "Invalid choice. Please enter 1-4."
            continue
        }

        switch ($choice) {
            '1' {
                Set-ConfigValue -Key "AiProvider" -Value "openai"
                Set-ConfigValue -Key "AiBaseUrl" -Value "https://api.openai.com/v1"
                Show-Success "OpenAI selected"
            }
            '2' {
                Set-ConfigValue -Key "AiProvider" -Value "deepseek"
                Set-ConfigValue -Key "AiBaseUrl" -Value "https://api.deepseek.com"
                Show-Success "DeepSeek selected"
            }
            '3' {
                Set-ConfigValue -Key "AiProvider" -Value "openrouter"
                Set-ConfigValue -Key "AiBaseUrl" -Value "https://openrouter.ai/api/v1"
                Show-Success "OpenRouter selected"
            }
            '4' {
                Set-ConfigValue -Key "AiProvider" -Value "custom"
                Write-Host ""
                $customUrl = Read-Host "  Enter API base URL"
                Set-ConfigValue -Key "AiBaseUrl" -Value $customUrl
                Show-Success "Custom provider selected"
            }
        }
        return 'next'
    }
}

function Invoke-Step4-Model {
    Show-WizardHeader -Step 4 -Title "Model"

    $modelOptions = @{
        'openai'     = @("gpt-4o-mini", "gpt-4o")
        'deepseek'   = @("deepseek-chat", "deepseek-reasoner")
        'openrouter' = @("openrouter/auto")
    }

    $modelDescriptions = @{
        'gpt-4o-mini'       = "Fast and cost-effective"
        'gpt-4o'            = "Higher quality, more expensive"
        'deepseek-chat'     = "General purpose chat model"
        'deepseek-reasoner' = "Advanced reasoning capabilities"
        'openrouter/auto'   = "Automatically selects best model"
    }

    $currentProvider = Get-ConfigValue -Key "AiProvider"

    if ($modelOptions.ContainsKey($currentProvider)) {
        $options = $modelOptions[$currentProvider]
        $maxChoice = $options.Count + 1

        for ($i = 0; $i -lt $options.Count; $i++) {
            $model = $options[$i]
            $label = if ($i -eq 0) { "$model (Recommended)" } else { $model }
            Write-Host "  [$($i + 1)] $label" -ForegroundColor White
            if ($modelDescriptions.ContainsKey($model)) {
                Show-Hint "$($modelDescriptions[$model])" -Indent 2
            }
            Write-Host ""
        }
        Write-Host "  [$maxChoice] Custom" -ForegroundColor White
        if ($currentProvider -eq 'openrouter') {
            Show-Hint "Visit openrouter.ai/models for available models" -Indent 2
        }
        Show-NavigationHint
        Write-Host ""

        while ($true) {
            $choice = Read-Host "  Select [1-$maxChoice, default=1, 'b' to go back]"

            if ($choice -eq 'b') { return 'back' }
            if (-not $choice) { $choice = '1' }

            if ($choice -notmatch "^[1-$maxChoice]$") {
                Show-Error "Invalid choice. Please enter 1-$maxChoice."
                continue
            }

            $choiceIndex = [int]$choice - 1
            if ($choiceIndex -lt $options.Count) {
                Set-ConfigValue -Key "AiModel" -Value $options[$choiceIndex]
            } else {
                $customModel = Read-Host "  Enter model name"
                Set-ConfigValue -Key "AiModel" -Value $customModel
            }

            Show-Success "Model: $(Get-ConfigValue -Key 'AiModel')"
            return 'next'
        }
    } else {
        Show-NavigationHint
        Write-Host ""
        $input = Read-Host "  Enter model name (or 'b' to go back)"
        if ($input -eq 'b') { return 'back' }
        Set-ConfigValue -Key "AiModel" -Value $input
        Show-Success "Model: $input"
        return 'next'
    }
}

function Invoke-Step5-ApiKey {
    Show-WizardHeader -Step 5 -Title "API Key"
    Show-Detail "Enter your API key (will be saved locally):"
    Show-NavigationHint
    Write-Host ""

    while ($true) {
        $apiKey = Read-Host "  API Key (or 'b' to go back)"

        if ($apiKey -eq 'b') { return 'back' }

        if (-not $apiKey) {
            Show-Error "API key is required. Please enter a valid key."
            continue
        }

        Set-ConfigValue -Key "AiApiKey" -Value $apiKey
        $maskedKey = $apiKey.Substring(0, [Math]::Min(7, $apiKey.Length)) + "****"
        Show-Detail "Key entered: $maskedKey"

        # Test connection
        Show-Info "Testing connection..."

        $script:AiClient_BaseUrl = Get-ConfigValue -Key "AiBaseUrl"
        $script:AiClient_ApiKey = Get-ConfigValue -Key "AiApiKey"
        $script:AiClient_Model = Get-ConfigValue -Key "AiModel"

        $testResult = Test-AiConnection

        if ($testResult.Success) {
            Show-Success "Connection successful!"
            return 'next'
        } else {
            Show-Error "Connection failed: $($testResult.Message)"
            Show-Warning "Please check your API key and try again."
            Write-Host ""
        }
    }
}

function Invoke-Step6-Language {
    Show-WizardHeader -Step 6 -Title "Target Language"

    $langOptions = @($script:QuickSelectLanguages.Keys)
    $maxLangChoice = $langOptions.Count + 1

    for ($i = 0; $i -lt $langOptions.Count; $i++) {
        $code = $langOptions[$i]
        $name = $script:QuickSelectLanguages[$code]
        $label = if ($i -eq 0) { "$name ($code) (Recommended)" } else { "$name ($code)" }
        Write-Host "  [$($i + 1)] $label" -ForegroundColor White
    }
    Write-Host "  [$maxLangChoice] Custom" -ForegroundColor White
    Show-NavigationHint
    Write-Host ""

    while ($true) {
        $choice = Read-Host "  Select [1-$maxLangChoice, default=1, 'b' to go back]"

        if ($choice -eq 'b') { return 'back' }
        if (-not $choice) { $choice = '1' }

        if ($choice -notmatch "^[1-$maxLangChoice]$") {
            Show-Error "Invalid choice. Please enter 1-$maxLangChoice."
            continue
        }

        $langIndex = [int]$choice - 1
        if ($langIndex -lt $langOptions.Count) {
            Set-ConfigValue -Key "TargetLanguage" -Value $langOptions[$langIndex]
        } else {
            $customLang = Read-Host "  Enter language code"
            Set-ConfigValue -Key "TargetLanguage" -Value $customLang
        }

        $langDisplay = Get-LanguageDisplayName -LangCode (Get-ConfigValue -Key "TargetLanguage")
        Show-Success "Target: $langDisplay ($(Get-ConfigValue -Key 'TargetLanguage'))"
        return 'next'
    }
}

function Show-ConfigSummary {
    Clear-Host
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "                    Configuration Summary" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""

    $cookieFile = Get-ConfigValue -Key "CookieFile"
    $apiKey = Get-ConfigValue -Key "AiApiKey"
    $maskedKey = if ($apiKey) { $apiKey.Substring(0, [Math]::Min(7, $apiKey.Length)) + "****" } else { "(not set)" }

    Write-Host "  [1] Output Directory: " -NoNewline -ForegroundColor Gray
    Write-Host "$(Get-ConfigValue -Key 'OutputDir')" -ForegroundColor White

    Write-Host "  [2] Cookie File:      " -NoNewline -ForegroundColor Gray
    Write-Host "$cookieFile" -ForegroundColor White

    Write-Host "  [3] AI Provider:      " -NoNewline -ForegroundColor Gray
    Write-Host "$(Get-ConfigValue -Key 'AiProvider') ($(Get-ConfigValue -Key 'AiBaseUrl'))" -ForegroundColor White

    Write-Host "  [4] Model:            " -NoNewline -ForegroundColor Gray
    Write-Host "$(Get-ConfigValue -Key 'AiModel')" -ForegroundColor White

    Write-Host "  [5] API Key:          " -NoNewline -ForegroundColor Gray
    Write-Host "$maskedKey" -ForegroundColor White

    Write-Host "  [6] Target Language:  " -NoNewline -ForegroundColor Gray
    $langDisplay = Get-LanguageDisplayName -LangCode (Get-ConfigValue -Key "TargetLanguage")
    Write-Host "$langDisplay ($(Get-ConfigValue -Key 'TargetLanguage'))" -ForegroundColor White

    Write-Host ""
    Write-Host ("-" * 60) -ForegroundColor DarkGray
    Write-Host ""
}

#endregion

#region Main Wizard

function Start-SetupWizard {
    $steps = @(
        { Invoke-Step1-OutputDir },
        { Invoke-Step2-CookieFile },
        { Invoke-Step3-AiProvider },
        { Invoke-Step4-Model },
        { Invoke-Step5-ApiKey },
        { Invoke-Step6-Language }
    )

    $currentStep = 0

    while ($currentStep -lt $steps.Count) {
        $result = & $steps[$currentStep]

        switch ($result) {
            'next' { $currentStep++ }
            'back' {
                if ($currentStep -gt 0) {
                    $currentStep--
                }
            }
        }
    }

    # Show summary and confirm
    while ($true) {
        Show-ConfigSummary

        Write-Host "  [C] Confirm and save" -ForegroundColor Green
        Write-Host "  [1-6] Edit specific setting" -ForegroundColor White
        Write-Host ""

        $choice = Read-Host "  Select option"

        if ($choice -eq 'c' -or $choice -eq 'C') {
            Export-Config
            Write-Host ""
            Show-Success "Setup complete! Configuration saved."
            Write-Host ""
            Show-Detail "You can change these settings anytime in [S] Settings."
            Write-Host ""
            Read-Host "Press Enter to continue" | Out-Null
            return
        }

        if ($choice -match '^[1-6]$') {
            $stepIndex = [int]$choice - 1
            $null = & $steps[$stepIndex]
        }
    }
}

#endregion
