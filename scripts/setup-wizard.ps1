# First-run setup wizard
# Guides users through initial configuration

# Dot source dependencies if not already loaded
if (-not (Get-Command "Get-LanguageDisplayName" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\lang-config.ps1"
}
if (-not (Get-Command "Test-AiConnection" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\ai-client.ps1"
}

#region Wizard Functions

# Check if first run
function Test-FirstRun {
    param([hashtable]$Config)

    return ($null -eq $Config) -or
           ($Config.FirstRun -eq $true) -or
           (-not $Config.ContainsKey('FirstRun'))
}

# Main setup wizard
function Start-SetupWizard {
    Clear-Host
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "                Welcome to Video Tools Suite!" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Let's set up a few things before we start." -ForegroundColor Gray
    Write-Host ""
    Write-Host ("-" * 60) -ForegroundColor DarkGray
    Write-Host ""

    $config = @{
        FirstRun = $false
        OutputDir = "./output"
        CookieFile = ""
        AiProvider = "openai"
        AiBaseUrl = "https://api.openai.com/v1"
        AiApiKey = ""
        AiModel = "gpt-4o-mini"
        TargetLanguage = $script:DefaultTargetLanguage
    }

    #region Step 1: Output Directory
    Write-Host "Step 1/6: Output Directory" -ForegroundColor Yellow
    Write-Host "  Where should files be saved?" -ForegroundColor Gray
    Write-Host ""
    $outputDir = Read-Host "  [./output, press Enter for default]"
    if ($outputDir) {
        $config.OutputDir = $outputDir
    }
    Write-Host "  Output: $($config.OutputDir)" -ForegroundColor Green
    Write-Host ""
    #endregion

    #region Step 2: Cookie File (Required)
    Write-Host "Step 2/6: Cookie File" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  For downloading videos (especially age-restricted or member-only)," -ForegroundColor Gray
    Write-Host "  you need to provide a cookie file exported from your browser." -ForegroundColor Gray
    Write-Host ""

    do {
        $cookiePath = Read-Host "  Enter cookie file path"
        if (-not $cookiePath) {
            Write-Host "  Cookie file is required. Please enter a valid path." -ForegroundColor Red
        } elseif (-not (Test-Path $cookiePath)) {
            Write-Host "  File not found: $cookiePath" -ForegroundColor Red
            Write-Host "  Please check the path and try again." -ForegroundColor Yellow
            $cookiePath = ""
        }
    } while (-not $cookiePath)

    $config.CookieFile = $cookiePath
    Write-Host "  Cookie file set: $cookiePath" -ForegroundColor Green
    Write-Host ""
    #endregion

    #region Step 3: AI Provider
    Write-Host "Step 3/6: AI Provider" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] OpenAI (Recommended)" -ForegroundColor White
    Write-Host "      https://api.openai.com/v1" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [2] DeepSeek" -ForegroundColor White
    Write-Host "      https://api.deepseek.com" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [3] OpenRouter" -ForegroundColor White
    Write-Host "      https://openrouter.ai/api/v1" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [4] Custom" -ForegroundColor White
    Write-Host "      Enter your own API endpoint" -ForegroundColor DarkGray
    Write-Host ""

    do {
        $providerChoice = Read-Host "  Select [1-4, default=1]"
        if (-not $providerChoice) { $providerChoice = '1' }
    } while ($providerChoice -notmatch '^[1234]$')

    switch ($providerChoice) {
        '1' {
            $config.AiProvider = "openai"
            $config.AiBaseUrl = "https://api.openai.com/v1"
            Write-Host "  OpenAI selected" -ForegroundColor Green
        }
        '2' {
            $config.AiProvider = "deepseek"
            $config.AiBaseUrl = "https://api.deepseek.com"
            Write-Host "  DeepSeek selected" -ForegroundColor Green
        }
        '3' {
            $config.AiProvider = "openrouter"
            $config.AiBaseUrl = "https://openrouter.ai/api/v1"
            Write-Host "  OpenRouter selected" -ForegroundColor Green
        }
        '4' {
            $config.AiProvider = "custom"
            Write-Host ""
            $customUrl = Read-Host "  Enter API base URL"
            $config.AiBaseUrl = $customUrl
            Write-Host "  Custom provider selected" -ForegroundColor Green
        }
    }
    Write-Host ""
    #endregion

    #region Step 4: Model
    Write-Host "Step 4/6: Model" -ForegroundColor Yellow
    Write-Host ""

    # Define model options per provider
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

    if ($modelOptions.ContainsKey($config.AiProvider)) {
        $options = $modelOptions[$config.AiProvider]
        $maxChoice = $options.Count + 1  # +1 for Custom option

        for ($i = 0; $i -lt $options.Count; $i++) {
            $model = $options[$i]
            $label = if ($i -eq 0) { "$model (Recommended)" } else { $model }
            Write-Host "  [$($i + 1)] $label" -ForegroundColor White
            if ($modelDescriptions.ContainsKey($model)) {
                Write-Host "      $($modelDescriptions[$model])" -ForegroundColor DarkGray
            }
            Write-Host ""
        }
        Write-Host "  [$maxChoice] Custom" -ForegroundColor White
        if ($config.AiProvider -eq 'openrouter') {
            Write-Host "      Visit openrouter.ai/models for available models" -ForegroundColor DarkGray
        }
        Write-Host ""

        do {
            $modelChoice = Read-Host "  Select [1-$maxChoice, default=1]"
            if (-not $modelChoice) { $modelChoice = '1' }
        } while ($modelChoice -notmatch "^[1-$maxChoice]$")

        $choiceIndex = [int]$modelChoice - 1
        if ($choiceIndex -lt $options.Count) {
            $config.AiModel = $options[$choiceIndex]
        } else {
            $config.AiModel = Read-Host "  Enter model name"
        }
    } else {
        $config.AiModel = Read-Host "  Enter model name"
    }

    Write-Host "  Model: $($config.AiModel)" -ForegroundColor Green
    Write-Host ""
    #endregion

    #region Step 5: API Key (Required + Connection Test)
    Write-Host "Step 5/6: API Key" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Enter your API key (will be saved locally):" -ForegroundColor Gray
    Write-Host ""

    $connectionSuccess = $false
    while (-not $connectionSuccess) {
        do {
            $apiKey = Read-Host "  API Key"
            if (-not $apiKey) {
                Write-Host "  API key is required. Please enter a valid key." -ForegroundColor Red
            }
        } while (-not $apiKey)

        $config.AiApiKey = $apiKey
        $maskedKey = $apiKey.Substring(0, [Math]::Min(7, $apiKey.Length)) + "****"
        Write-Host "  Key entered: $maskedKey" -ForegroundColor Gray

        # Test connection
        Write-Host "  Testing connection..." -ForegroundColor Cyan

        # Temporarily set AI client variables for testing
        $script:AiClient_BaseUrl = $config.AiBaseUrl
        $script:AiClient_ApiKey = $config.AiApiKey
        $script:AiClient_Model = $config.AiModel

        $testResult = Test-AiConnection

        if ($testResult.Success) {
            Write-Host "  Connection successful!" -ForegroundColor Green
            $connectionSuccess = $true
        } else {
            Write-Host "  Connection failed: $($testResult.Message)" -ForegroundColor Red
            Write-Host "  Please check your API key and try again." -ForegroundColor Yellow
            Write-Host ""
        }
    }
    Write-Host ""
    #endregion

    #region Step 6: Target Language
    Write-Host "Step 6/6: Target Language" -ForegroundColor Yellow
    Write-Host ""

    # Use QuickSelectLanguages from lang-config.ps1
    $langOptions = @($script:QuickSelectLanguages.Keys)
    $maxLangChoice = $langOptions.Count + 1  # +1 for Custom

    for ($i = 0; $i -lt $langOptions.Count; $i++) {
        $code = $langOptions[$i]
        $name = $script:QuickSelectLanguages[$code]
        $label = if ($i -eq 0) { "$name ($code) (Recommended)" } else { "$name ($code)" }
        Write-Host "  [$($i + 1)] $label" -ForegroundColor White
    }
    Write-Host "  [$maxLangChoice] Custom" -ForegroundColor White
    Write-Host ""

    do {
        $langChoice = Read-Host "  Select [1-$maxLangChoice, default=1]"
        if (-not $langChoice) { $langChoice = '1' }
    } while ($langChoice -notmatch "^[1-$maxLangChoice]$")

    $langIndex = [int]$langChoice - 1
    if ($langIndex -lt $langOptions.Count) {
        $config.TargetLanguage = $langOptions[$langIndex]
    } else {
        $config.TargetLanguage = Read-Host "  Enter language code"
    }

    $langDisplay = Get-LanguageDisplayName -LangCode $config.TargetLanguage
    Write-Host "  Target: $langDisplay ($($config.TargetLanguage))" -ForegroundColor Green
    Write-Host ""
    #endregion

    #region Complete
    Write-Host ("-" * 60) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Setup complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can change these settings anytime in [S] Settings." -ForegroundColor Gray
    Write-Host ""
    Write-Host ("-" * 60) -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
    #endregion

    return $config
}

#endregion
