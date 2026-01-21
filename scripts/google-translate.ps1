# Google Translate module using free translation API
# Provides batch translation capabilities for subtitles

#region Core Translation

# Translate text using Google Translate (free API)
function Invoke-GoogleTranslate {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,
        [string]$SourceLanguage = "en",
        [string]$TargetLanguage = "zh-CN"
    )

    if (-not $Text.Trim()) {
        return ""
    }

    # Use Google Translate free API
    $encodedText = [System.Web.HttpUtility]::UrlEncode($Text)
    $uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=$SourceLanguage&tl=$TargetLanguage&dt=t&q=$encodedText"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json; charset=utf-8"

        # Parse response - it's a nested array structure
        $translated = ""
        if ($response -and $response[0]) {
            foreach ($part in $response[0]) {
                if ($part -and $part[0]) {
                    $translated += $part[0]
                }
            }
        }

        return $translated
    }
    catch {
        throw "Google Translate API call failed: $($_.Exception.Message)"
    }
}

#endregion

#region Batch Translation

# Batch translate multiple texts
function Invoke-BatchGoogleTranslate {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Texts,
        [string]$SourceLanguage = "en",
        [string]$TargetLanguage = "zh-CN",
        [int]$DelayMs = 100
    )

    $results = @()

    for ($i = 0; $i -lt $Texts.Count; $i++) {
        $text = $Texts[$i]

        try {
            $translated = Invoke-GoogleTranslate -Text $text -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage
            $results += $translated
        }
        catch {
            Write-Warning "Failed to translate text $($i + 1): $_"
            $results += "[Translation failed]"
        }

        # Rate limiting
        if ($DelayMs -gt 0 -and $i -lt ($Texts.Count - 1)) {
            Start-Sleep -Milliseconds $DelayMs
        }

        # Progress indicator
        if (($i + 1) % 10 -eq 0) {
            Write-Host "  Translated $($i + 1)/$($Texts.Count)..." -ForegroundColor Gray
        }
    }

    return $results
}

# Translate subtitle entries using Google Translate
function Invoke-GoogleSubtitleTranslate {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries,
        [string]$SourceLanguage = "en",
        [string]$TargetLanguage = "zh-CN",
        [int]$BatchSize = 50,
        [int]$DelayMs = 100
    )

    $translatedEntries = @()
    $totalEntries = $Entries.Count
    $totalBatches = [math]::Ceiling($totalEntries / $BatchSize)

    Write-Host "Translating $totalEntries entries in $totalBatches batches..." -ForegroundColor Cyan

    for ($batchIndex = 0; $batchIndex -lt $totalBatches; $batchIndex++) {
        $startIdx = $batchIndex * $BatchSize
        $endIdx = [math]::Min($startIdx + $BatchSize - 1, $totalEntries - 1)

        Write-Host "  Batch $($batchIndex + 1)/$totalBatches..." -ForegroundColor Gray

        for ($i = $startIdx; $i -le $endIdx; $i++) {
            $entry = $Entries[$i]

            try {
                $translated = Invoke-GoogleTranslate -Text $entry.Text -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage

                $translatedEntries += @{
                    StartTime = $entry.StartTime
                    EndTime = $entry.EndTime
                    Original = $entry.Text
                    Translation = $translated
                }
            }
            catch {
                Write-Warning "Translation failed for entry $($i + 1): $_"
                $translatedEntries += @{
                    StartTime = $entry.StartTime
                    EndTime = $entry.EndTime
                    Original = $entry.Text
                    Translation = "[Translation failed]"
                }
            }

            # Rate limiting
            if ($DelayMs -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }
        }

        # Longer pause between batches
        if ($batchIndex -lt ($totalBatches - 1)) {
            Start-Sleep -Milliseconds 500
        }
    }

    return $translatedEntries
}

#endregion

#region Sentence-based Translation

# Extract and translate complete sentences for better quality
function Invoke-GoogleSentenceTranslate {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries,
        [string]$SourceLanguage = "en",
        [string]$TargetLanguage = "zh-CN",
        [int]$DelayMs = 200
    )

    # First, extract complete sentences from entries
    $sentences = @()
    $currentSentence = ""
    $sentenceEntries = @()

    foreach ($entry in $Entries) {
        $sentenceEntries += $entry
        $currentSentence += " " + $entry.Text

        # Check if sentence ends
        if ($entry.Text -match '[.!?]$') {
            $sentences += @{
                Text = $currentSentence.Trim()
                Entries = $sentenceEntries
            }
            $currentSentence = ""
            $sentenceEntries = @()
        }
    }

    # Add remaining text
    if ($currentSentence.Trim()) {
        $sentences += @{
            Text = $currentSentence.Trim()
            Entries = $sentenceEntries
        }
    }

    Write-Host "Extracted $($sentences.Count) sentences from $($Entries.Count) entries" -ForegroundColor Cyan

    # Translate sentences
    $translatedSentences = @()
    for ($i = 0; $i -lt $sentences.Count; $i++) {
        $sentence = $sentences[$i]

        try {
            $translated = Invoke-GoogleTranslate -Text $sentence.Text -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage
            $translatedSentences += @{
                Original = $sentence.Text
                Translation = $translated
                Entries = $sentence.Entries
            }
        }
        catch {
            Write-Warning "Sentence translation failed: $_"
            $translatedSentences += @{
                Original = $sentence.Text
                Translation = "[Translation failed]"
                Entries = $sentence.Entries
            }
        }

        if ($DelayMs -gt 0) {
            Start-Sleep -Milliseconds $DelayMs
        }

        # Progress
        if (($i + 1) % 10 -eq 0) {
            Write-Host "  Translated $($i + 1)/$($sentences.Count) sentences..." -ForegroundColor Gray
        }
    }

    # Distribute translations back to entries
    $result = @()

    foreach ($transSentence in $translatedSentences) {
        $entryCount = $transSentence.Entries.Count

        if ($entryCount -eq 1) {
            # Single entry - use full translation
            $result += @{
                StartTime = $transSentence.Entries[0].StartTime
                EndTime = $transSentence.Entries[0].EndTime
                Original = $transSentence.Entries[0].Text
                Translation = $transSentence.Translation
            }
        }
        else {
            # Multiple entries - try to split translation proportionally
            # For now, assign full translation to first entry, empty to others
            # This could be improved with more sophisticated splitting
            $words = $transSentence.Translation -split '\s+'
            $wordsPerEntry = [math]::Ceiling($words.Count / $entryCount)

            for ($i = 0; $i -lt $entryCount; $i++) {
                $entry = $transSentence.Entries[$i]
                $startWord = $i * $wordsPerEntry
                $endWord = [math]::Min($startWord + $wordsPerEntry - 1, $words.Count - 1)

                $translationPart = ""
                if ($startWord -le $endWord -and $startWord -lt $words.Count) {
                    $translationPart = ($words[$startWord..$endWord]) -join ' '
                }

                $result += @{
                    StartTime = $entry.StartTime
                    EndTime = $entry.EndTime
                    Original = $entry.Text
                    Translation = $translationPart
                }
            }
        }
    }

    return $result
}

#endregion

#region Test Connection

# Test Google Translate API connection
function Test-GoogleTranslateConnection {
    param()

    try {
        $result = Invoke-GoogleTranslate -Text "Hello" -SourceLanguage "en" -TargetLanguage "zh-CN"

        return @{
            Success = $true
            Message = "Google Translate is working"
            TestResult = "Hello -> $result"
        }
    }
    catch {
        return @{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

#endregion

#region Language Code Mapping

# Map language names to Google Translate language codes
function Get-GoogleLanguageCode {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LanguageName
    )

    $languageMap = @{
        "English" = "en"
        "Chinese (Simplified)" = "zh-CN"
        "Chinese (Traditional)" = "zh-TW"
        "Japanese" = "ja"
        "Korean" = "ko"
        "Spanish" = "es"
        "French" = "fr"
        "German" = "de"
        "Russian" = "ru"
        "Portuguese" = "pt"
        "Italian" = "it"
        "Arabic" = "ar"
        "Hindi" = "hi"
        "Thai" = "th"
        "Vietnamese" = "vi"
        "Indonesian" = "id"
        "Malay" = "ms"
        "Turkish" = "tr"
        "Dutch" = "nl"
        "Polish" = "pl"
    }

    # Check if it's already a code
    if ($LanguageName -match '^[a-z]{2}(-[A-Z]{2})?$') {
        return $LanguageName
    }

    if ($languageMap.ContainsKey($LanguageName)) {
        return $languageMap[$LanguageName]
    }

    # Default to the input
    return $LanguageName.ToLower()
}

#endregion
