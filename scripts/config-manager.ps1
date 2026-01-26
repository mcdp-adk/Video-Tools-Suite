# Configuration Manager - Central configuration read/write
# All scripts must use this module for configuration access

# Paths (use absolute paths based on script location)
$script:ProjectRoot = (Resolve-Path "$PSScriptRoot\..").Path
$script:ConfigFile = Join-Path $script:ProjectRoot "config.json"
$script:ConfigExampleFile = Join-Path $script:ProjectRoot "config.example.json"

# In-memory config (populated by Import-Config)
$script:Config = @{}

# Track if this is first run (for setup wizard)
$script:IsFirstRun = $false

# Check if config exists
function Test-ConfigExists {
    return (Test-Path $script:ConfigFile)
}

# Initialize config from example (load defaults into memory, don't create file yet)
function Initialize-Config {
    if (-not (Test-Path $script:ConfigExampleFile)) {
        throw "config.example.json not found"
    }
    # Only load defaults into memory, don't create config.json
    # Config file will be created when Export-Config is called
}

# Load config from file into $script:Config
function Import-Config {
    $sourceFile = if (Test-ConfigExists) { $script:ConfigFile } else { $script:ConfigExampleFile }

    if (-not (Test-Path $sourceFile)) {
        throw "No config source found"
    }

    $fileConfig = Get-Content $sourceFile -Raw | ConvertFrom-Json

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

# Get default config value from config.example.json
function Get-DefaultConfigValue {
    param([string]$Key)
    if (-not (Test-Path $script:ConfigExampleFile)) {
        return $null
    }
    $defaults = Get-Content $script:ConfigExampleFile -Raw | ConvertFrom-Json
    return $defaults.$Key
}

# Set config value (in memory, call Export-Config to persist)
function Set-ConfigValue {
    param([string]$Key, $Value)
    $script:Config[$Key] = $Value
}

# Apply config to all module variables
function Apply-ConfigToModules {
    # Resolve OutputDir relative to project root
    $outputDir = $script:Config.OutputDir
    if ($outputDir -match '^\.[\\/]') {
        # Relative path starting with ./ or .\
        $outputDir = Join-Path $script:ProjectRoot ($outputDir -replace '^\.[\\/]', '')
    } elseif (-not [System.IO.Path]::IsPathRooted($outputDir)) {
        # Relative path without ./
        $outputDir = Join-Path $script:ProjectRoot $outputDir
    }

    # Output directories
    $script:YtdlOutputDir = $outputDir
    $script:MuxerOutputDir = $outputDir
    $script:TranscriptOutputDir = $outputDir
    $script:TranslateOutputDir = $outputDir
    $script:WorkflowOutputDir = $outputDir
    $script:BatchOutputDir = $outputDir

    # Resolve CookieFile relative to project root (if relative)
    $cookieFile = $script:Config.CookieFile
    if ($cookieFile -and -not [System.IO.Path]::IsPathRooted($cookieFile)) {
        if ($cookieFile -match '^\.[\\/]') {
            $cookieFile = Join-Path $script:ProjectRoot ($cookieFile -replace '^\.[\\/]', '')
        } else {
            $cookieFile = Join-Path $script:ProjectRoot $cookieFile
        }
    }
    $script:YtdlCookieFile = $cookieFile
    $script:BatchCookieFile = $cookieFile

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
    if (-not (Test-ConfigExists)) {
        Initialize-Config
        $script:IsFirstRun = $true
    }

    Import-Config
    Apply-ConfigToModules

    return $script:IsFirstRun
}

# Auto-initialize config when this module is loaded (if not already initialized)
if (-not $script:Config.Count) {
    $null = Ensure-ConfigReady
}
