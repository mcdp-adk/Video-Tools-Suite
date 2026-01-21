# First-run setup wizard
# Guides users through initial configuration

#region Wizard Functions

# Check if first run
function Test-FirstRun {
    param([hashtable]$Config)

    if ($null -eq $Config) { return $true }
    if ($Config.FirstRun -eq $true) { return $true }
    if (-not $Config.ContainsKey('FirstRun')) { return $true }

    return $false
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
        TranslateMethod = "ai"
        TargetLanguage = "zh-CN"
    }

    #region Step 1: Output Directory
    Write-Host "Step 1/5: Output Directory" -ForegroundColor Yellow
    Write-Host "  Where should files be saved?" -ForegroundColor Gray
    Write-Host ""
    $outputDir = Read-Host "  [./output]"
    if ($outputDir) {
        $config.OutputDir = $outputDir
    }
    Write-Host ""
    #endregion

    #region Step 2: Translation Method
    Write-Host "Step 2/5: Translation Method" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] AI Translation (Recommended)" -ForegroundColor White
    Write-Host "      Higher quality, supports glossaries, requires API key" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [2] Google Translate" -ForegroundColor White
    Write-Host "      Free, no setup required, basic quality" -ForegroundColor DarkGray
    Write-Host ""

    do {
        $methodChoice = Read-Host "  Select [1-2]"
    } while ($methodChoice -notmatch '^[12]$')

    if ($methodChoice -eq '2') {
        $config.TranslateMethod = "google"
        Write-Host ""
        Write-Host "  Google Translate selected" -ForegroundColor Green
        Write-Host ""

        # Skip AI setup steps
        Write-Host "Step 3-5: Skipped (not needed for Google Translate)" -ForegroundColor DarkGray
        Write-Host ""
    }
    else {
        $config.TranslateMethod = "ai"
        Write-Host ""
        Write-Host "  AI Translation selected" -ForegroundColor Green
        Write-Host ""

        #region Step 3: AI Provider
        Write-Host "Step 3/5: AI Provider" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  [1] OpenAI" -ForegroundColor White
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
            $providerChoice = Read-Host "  Select [1-4]"
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
        Write-Host "Step 4/5: Model" -ForegroundColor Yellow
        Write-Host ""

        switch ($config.AiProvider) {
            'openai' {
                Write-Host "  [1] gpt-4o-mini (Recommended)" -ForegroundColor White
                Write-Host "      Fast and cost-effective" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "  [2] gpt-4o" -ForegroundColor White
                Write-Host "      Higher quality, more expensive" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "  [3] Custom" -ForegroundColor White
                Write-Host ""

                $modelChoice = Read-Host "  Select [1-3]"
                switch ($modelChoice) {
                    '1' { $config.AiModel = "gpt-4o-mini" }
                    '2' { $config.AiModel = "gpt-4o" }
                    '3' {
                        $customModel = Read-Host "  Enter model name"
                        $config.AiModel = $customModel
                    }
                    default { $config.AiModel = "gpt-4o-mini" }
                }
            }
            'deepseek' {
                Write-Host "  [1] deepseek-chat (Recommended)" -ForegroundColor White
                Write-Host "      General purpose chat model" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "  [2] deepseek-reasoner" -ForegroundColor White
                Write-Host "      Advanced reasoning capabilities" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "  [3] Custom" -ForegroundColor White
                Write-Host ""

                $modelChoice = Read-Host "  Select [1-3]"
                switch ($modelChoice) {
                    '1' { $config.AiModel = "deepseek-chat" }
                    '2' { $config.AiModel = "deepseek-reasoner" }
                    '3' {
                        $customModel = Read-Host "  Enter model name"
                        $config.AiModel = $customModel
                    }
                    default { $config.AiModel = "deepseek-chat" }
                }
            }
            'openrouter' {
                Write-Host "  [1] openrouter/auto (Recommended)" -ForegroundColor White
                Write-Host "      Automatically selects best model" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "  [2] Custom" -ForegroundColor White
                Write-Host "      Visit openrouter.ai/models for available models" -ForegroundColor DarkGray
                Write-Host ""

                $modelChoice = Read-Host "  Select [1-2]"
                switch ($modelChoice) {
                    '1' { $config.AiModel = "openrouter/auto" }
                    '2' {
                        $customModel = Read-Host "  Enter model name"
                        $config.AiModel = $customModel
                    }
                    default { $config.AiModel = "openrouter/auto" }
                }
            }
            default {
                $customModel = Read-Host "  Enter model name"
                $config.AiModel = $customModel
            }
        }

        Write-Host "  Model: $($config.AiModel)" -ForegroundColor Green
        Write-Host ""
        #endregion

        #region Step 5: API Key
        Write-Host "Step 5/5: API Key" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Enter your API key (will be saved locally):" -ForegroundColor Gray
        Write-Host ""

        $apiKey = Read-Host "  API Key"
        $config.AiApiKey = $apiKey

        if ($apiKey) {
            $maskedKey = $apiKey.Substring(0, [Math]::Min(7, $apiKey.Length)) + "****"
            Write-Host "  Key saved: $maskedKey" -ForegroundColor Green
        }
        else {
            Write-Host "  No key provided (you can set this later in Settings)" -ForegroundColor Yellow
        }
        Write-Host ""
        #endregion
    }
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
