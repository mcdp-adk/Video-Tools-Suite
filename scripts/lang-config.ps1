# Language configuration module
# Central place for all language-related settings

# Supported languages: code => display name (for AI prompts)
$script:LanguageMap = [ordered]@{
    'zh-Hans' = 'Chinese (Simplified)'
    'zh-Hant' = 'Chinese (Traditional)'
    'ja'      = 'Japanese'
    'ko'      = 'Korean'
    'en'      = 'English'
    'es'      = 'Spanish'
    'fr'      = 'French'
    'de'      = 'German'
    'pt'      = 'Portuguese'
    'ru'      = 'Russian'
}

# Quick select languages for settings menu (ordered)
$script:QuickSelectLanguages = [ordered]@{
    'zh-Hans' = 'Chinese Simplified'
    'zh-Hant' = 'Chinese Traditional'
    'ja'      = 'Japanese'
    'ko'      = 'Korean'
    'en'      = 'English'
}

# Get display name for a language code (for AI prompts)
function Get-LanguageDisplayName {
    param([string]$LangCode)

    if ($script:LanguageMap.Contains($LangCode)) {
        return $script:LanguageMap[$LangCode]
    }
    return $LangCode
}
