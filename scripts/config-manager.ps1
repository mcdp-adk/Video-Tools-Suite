# Configuration Manager - Central configuration read/write
# All scripts must use this module for configuration access

# Paths
$script:ConfigFile = "$PSScriptRoot\..\config.json"
$script:ConfigExampleFile = "$PSScriptRoot\..\config.example.json"

# In-memory config (populated by Import-Config)
$script:Config = @{}

# Check if config exists
function Test-ConfigExists {
    return (Test-Path $script:ConfigFile)
}

# Initialize config from example (copy example to config.json)
function Initialize-Config {
    if (-not (Test-Path $script:ConfigExampleFile)) {
        throw "config.example.json not found"
    }
    Copy-Item -Path $script:ConfigExampleFile -Destination $script:ConfigFile -Force
}

# Load config from file into $script:Config
function Import-Config {
    if (-not (Test-ConfigExists)) {
        throw "config.json not found. Call Initialize-Config first."
    }

    $fileConfig = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json

    # Convert PSObject to hashtable
    $script:Config = @{}
    foreach ($prop in $fileConfig.PSObject.Properties) {
        $script:Config[$prop.Name] = $prop.Value
    }

    # Backward compatibility: map old language codes
    if ($script:Config.TargetLanguage -eq 'zh-CN') { $script:Config.TargetLanguage = 'zh-Hans' }
    if ($script:Config.TargetLanguage -eq 'zh-TW') { $script:Config.TargetLanguage = 'zh-Hant' }
}

# Save config to file
function Export-Config {
    $script:Config | ConvertTo-Json | Set-Content $script:ConfigFile -Encoding UTF8
}

# Reset config (delete config.json)
function Reset-Config {
    if (Test-Path $script:ConfigFile) {
        Remove-Item $script:ConfigFile -Force
    }
}

# Get config value
function Get-ConfigValue {
    param([string]$Key)
    return $script:Config[$Key]
}

# Set config value (in memory, call Export-Config to persist)
function Set-ConfigValue {
    param([string]$Key, $Value)
    $script:Config[$Key] = $Value
}

# Apply config to all module variables
function Apply-ConfigToModules {
    $outputDir = $script:Config.OutputDir

    # Output directories
    $script:YtdlOutputDir = $outputDir
    $script:MuxerOutputDir = $outputDir
    $script:TranscriptOutputDir = $outputDir
    $script:TranslateOutputDir = $outputDir
    $script:WorkflowOutputDir = $outputDir
    $script:BatchOutputDir = $outputDir

    # Cookie
    $script:YtdlCookieFile = $script:Config.CookieFile
    $script:BatchCookieFile = $script:Config.CookieFile

    # Translation
    $script:TargetLanguage = $script:Config.TargetLanguage
    $script:EmbedFontFile = $script:Config.EmbedFontFile

    # AI
    $script:AiClient_BaseUrl = $script:Config.AiBaseUrl
    $script:AiClient_ApiKey = $script:Config.AiApiKey
    $script:AiClient_Model = $script:Config.AiModel

    # Batch
    $script:BatchParallelDownloads = $script:Config.BatchParallelDownloads
    $script:GenerateTranscriptInWorkflow = $script:Config.GenerateTranscriptInWorkflow
}

# Ensure config is ready (init if needed, then load)
# Returns $true if setup wizard should be shown (first run)
function Ensure-ConfigReady {
    $needsSetup = $false

    if (-not (Test-ConfigExists)) {
        Initialize-Config
        $needsSetup = $true
    }

    Import-Config
    Apply-ConfigToModules

    return $needsSetup
}
