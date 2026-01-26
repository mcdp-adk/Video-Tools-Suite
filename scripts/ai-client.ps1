# AI Client module for OpenAI-compatible API calls
# Supports subtitle segmentation, translation, and proofreading

# Load config (if not already loaded)
if (-not (Get-Command "Ensure-ConfigReady" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\config-manager.ps1"
}

# Dot source dependencies if not already loaded
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}
if (-not (Get-Command "Set-VtsWindowTitle" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\tui-utils.ps1"
}

# Configuration variables (set by config-manager.ps1 via Apply-ConfigToModules)
# $script:AiClient_BaseUrl
# $script:AiClient_ApiKey
# $script:AiClient_Model

# Sentence segmentation cache (avoid duplicate AI calls within same session)
$script:SentenceCache = @{}

#region Core API

# Invoke OpenAI-compatible chat completion API
function Invoke-AiCompletion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SystemPrompt,
        [Parameter(Mandatory=$true)]
        [string]$UserPrompt,
        [double]$Temperature = 0.3,
        [int]$MaxTokens = 4096,
        [switch]$ReturnFullResponse,
        [int]$MaxRetries = 5,
        [int]$BaseDelaySeconds = 5
    )

    if (-not $script:AiClient_ApiKey) {
        throw "AI API key not configured. Please set up in Settings."
    }

    $uri = "$($script:AiClient_BaseUrl)/chat/completions"

    $headers = @{
        "Authorization" = "Bearer $($script:AiClient_ApiKey)"
        "Content-Type" = "application/json"
    }

    $bodyJson = @{
        model = $script:AiClient_Model
        messages = @(
            @{ role = "system"; content = $SystemPrompt }
            @{ role = "user"; content = $UserPrompt }
        )
        temperature = $Temperature
        max_tokens = $MaxTokens
    } | ConvertTo-Json -Depth 10

    # Ensure proper UTF-8 encoding for the request body
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

    $lastError = $null

    for ($retry = 0; $retry -lt $MaxRetries; $retry++) {
        try {
            # Use Invoke-WebRequest + manual UTF-8 decoding to ensure proper Chinese character handling
            $webResponse = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $bodyBytes -ContentType "application/json; charset=utf-8" -UseBasicParsing

            # Manually decode response as UTF-8 to prevent encoding issues
            $responseBytes = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetBytes($webResponse.Content)
            $responseText = [System.Text.Encoding]::UTF8.GetString($responseBytes)
            $response = $responseText | ConvertFrom-Json

            if ($ReturnFullResponse) {
                return $response
            }

            return $response.choices[0].message.content
        }
        catch {
            $lastError = $_
            $statusCode = 0
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Retry on 429 (Rate Limit) and 5xx (Server Error)
            if ($statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -lt 600)) {
                $delay = $BaseDelaySeconds * [math]::Pow(2, $retry) + (Get-Random -Minimum 0 -Maximum 1000) / 1000
                $delay = [math]::Min($delay, 60)  # Max 60 seconds
                Write-Warning "API rate limit/error (HTTP $statusCode), retrying in $([math]::Round($delay))s ($($retry + 1)/$MaxRetries)..."
                Start-Sleep -Seconds $delay
                continue
            }

            # Other errors: throw immediately
            $errorMessage = $_.Exception.Message
            if ($_.ErrorDetails.Message) {
                try {
                    $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json
                    if ($errorJson.error.message) {
                        $errorMessage = $errorJson.error.message
                    }
                } catch {}
            }
            throw "AI API call failed: $errorMessage"
        }
    }

    throw "AI API call failed after $MaxRetries retries: $($lastError.Exception.Message)"
}

# Invoke API with conversation history
function Invoke-AiCompletionWithHistory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SystemPrompt,
        [Parameter(Mandatory=$true)]
        [array]$Messages,
        [double]$Temperature = 0.3,
        [int]$MaxTokens = 4096,
        [int]$MaxRetries = 5,
        [int]$BaseDelaySeconds = 5
    )

    if (-not $script:AiClient_ApiKey) {
        throw "AI API key not configured. Please set up in Settings."
    }

    $uri = "$($script:AiClient_BaseUrl)/chat/completions"

    $headers = @{
        "Authorization" = "Bearer $($script:AiClient_ApiKey)"
        "Content-Type" = "application/json"
    }

    $allMessages = @(@{ role = "system"; content = $SystemPrompt }) + $Messages

    $bodyJson = @{
        model = $script:AiClient_Model
        messages = $allMessages
        temperature = $Temperature
        max_tokens = $MaxTokens
    } | ConvertTo-Json -Depth 10

    # Ensure proper UTF-8 encoding for the request body
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

    $lastError = $null

    for ($retry = 0; $retry -lt $MaxRetries; $retry++) {
        try {
            # Use Invoke-WebRequest + manual UTF-8 decoding to ensure proper Chinese character handling
            $webResponse = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $bodyBytes -ContentType "application/json; charset=utf-8" -UseBasicParsing

            # Manually decode response as UTF-8 to prevent encoding issues
            $responseBytes = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetBytes($webResponse.Content)
            $responseText = [System.Text.Encoding]::UTF8.GetString($responseBytes)
            $response = $responseText | ConvertFrom-Json

            return $response.choices[0].message.content
        }
        catch {
            $lastError = $_
            $statusCode = 0
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Retry on 429 (Rate Limit) and 5xx (Server Error)
            if ($statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -lt 600)) {
                $delay = $BaseDelaySeconds * [math]::Pow(2, $retry) + (Get-Random -Minimum 0 -Maximum 1000) / 1000
                $delay = [math]::Min($delay, 60)  # Max 60 seconds
                Write-Warning "API rate limit/error (HTTP $statusCode), retrying in $([math]::Round($delay))s ($($retry + 1)/$MaxRetries)..."
                Start-Sleep -Seconds $delay
                continue
            }

            # Other errors: throw immediately
            $errorMessage = $_.Exception.Message
            if ($_.ErrorDetails.Message) {
                try {
                    $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json
                    if ($errorJson.error.message) {
                        $errorMessage = $errorJson.error.message
                    }
                } catch {}
            }
            throw "AI API call failed: $errorMessage"
        }
    }

    throw "AI API call failed after $MaxRetries retries: $($lastError.Exception.Message)"
}

#endregion

#region Subtitle Segmentation

# Cue-based segmentation: process cues in batches, AI inserts <br> markers within each batch
# Returns array of objects: @{ StartIndex; EndIndex; Text } (word indices in flat Words array)
function Invoke-CueBasedSegmentation {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Cues,                    # Array of @{ StartTime; EndTime; Words }
        [Parameter(Mandatory=$true)]
        [array]$Words,                   # Flat array of @{ Word; StartTime; CueIndex }
        [int]$MaxWordsPerSegment = 18,
        [int]$MinWordsPerSegment = 5,
        [int]$CuesPerBatch = 25,         # Process ~25 cues at a time (~150-200 words)
        [int]$MaxAttempts = 3,
        [switch]$Quiet
    )

    $allSegments = @()
    $globalWordOffset = 0
    $totalBatches = [math]::Ceiling($Cues.Count / $CuesPerBatch)
    $batchIndex = 0

    # Process cues in batches
    for ($batchStart = 0; $batchStart -lt $Cues.Count; $batchStart += $CuesPerBatch) {
        $batchIndex++
        $batchEnd = [Math]::Min($batchStart + $CuesPerBatch - 1, $Cues.Count - 1)
        $batchCues = @($Cues[$batchStart..$batchEnd])

        # Update window title with progress
        Set-VtsWindowTitle -Phase Segment -Status "Segmenting $batchIndex/$totalBatches..."

        # Collect words for this batch
        $batchWords = @()
        foreach ($cue in $batchCues) {
            $batchWords += $cue.Words
        }

        if ($batchWords.Count -eq 0) { continue }

        if (-not $Quiet) {
            Show-Detail "Processing cues $($batchStart + 1)-$($batchEnd + 1) of $($Cues.Count) ($($batchWords.Count) words)..."
        }

        # Get segments for this batch using AI
        $batchSegments = Invoke-BatchSegmentation -Words $batchWords -MaxWordsPerSegment $MaxWordsPerSegment -MinWordsPerSegment $MinWordsPerSegment -MaxAttempts $MaxAttempts

        # Adjust indices to global offset
        foreach ($segment in $batchSegments) {
            $allSegments += @{
                StartIndex = $segment.StartIndex + $globalWordOffset
                EndIndex = $segment.EndIndex + $globalWordOffset
                Text = $segment.Text
            }
        }

        $globalWordOffset += $batchWords.Count
    }

    if (-not $Quiet) {
        Show-Success "  Total segments: $($allSegments.Count)"
    }
    return $allSegments
}

# Internal: segment a batch of words using AI
function Invoke-BatchSegmentation {
    param(
        [array]$Words,
        [int]$MaxWordsPerSegment,
        [int]$MinWordsPerSegment,
        [int]$MaxAttempts
    )

    $wordTexts = @($Words | ForEach-Object { $_.Word })
    $fullText = $wordTexts -join ' '

    # If batch is small enough, just return as single segment
    if ($wordTexts.Count -le $MaxWordsPerSegment) {
        return @(@{
            StartIndex = 0
            EndIndex = $wordTexts.Count - 1
            Text = $fullText
        })
    }

    $systemPrompt = @"
You are a subtitle segmentation expert. Insert <br> markers to split text into subtitle segments.

RULES:
1. Each segment should be $MinWordsPerSegment-$MaxWordsPerSegment words
2. Insert <br> at natural breaks: after sentences, at commas, conjunctions (and, but, because, so)
3. DO NOT modify any words - only insert <br> markers between words
4. DO NOT create segments shorter than $MinWordsPerSegment words unless it's the last segment
5. Return ONLY the text with <br> markers, no explanations

Example input: "well I think the biggest problem with this club is that we keep making the same mistakes"
Example output: "well I think the biggest problem with this club<br>is that we keep making the same mistakes"
"@

    $userPrompt = "Insert <br> markers to segment this text:`n$fullText"

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $response = Invoke-AiCompletion -SystemPrompt $systemPrompt -UserPrompt $userPrompt -Temperature 0.1 -MaxTokens 4096

        # Clean response
        $segmentedText = ($response -replace "`r?`n", " ").Trim()

        # Validate: check word count matches
        $responseWords = @(($segmentedText -replace '<br>', ' ') -split '\s+' | Where-Object { $_ })
        if ($responseWords.Count -ne $wordTexts.Count) {
            if ($attempt -lt $MaxAttempts) {
                $userPrompt = "Error: Word count mismatch (expected $($wordTexts.Count), got $($responseWords.Count)). Return EXACT original text with only <br> inserted:`n$fullText"
                continue
            }
            # Final attempt failed, use rule-based fallback
            return Split-TextByRules -Words $Words -MaxWordsPerSegment $MaxWordsPerSegment
        }

        # Parse segments by <br> positions
        $segments = @()
        $currentWordIndex = 0
        $parts = $segmentedText -split '<br>'

        foreach ($part in $parts) {
            $partWords = @($part.Trim() -split '\s+' | Where-Object { $_ })
            if ($partWords.Count -eq 0) { continue }

            $startIndex = $currentWordIndex
            $endIndex = $currentWordIndex + $partWords.Count - 1

            if ($endIndex -ge $Words.Count) { break }

            $segments += @{
                StartIndex = $startIndex
                EndIndex = $endIndex
                Text = $partWords -join ' '
            }

            $currentWordIndex = $endIndex + 1
        }

        if ($segments.Count -gt 0) {
            return $segments
        }
    }

    # Fallback: rule-based splitting
    return Split-TextByRules -Words $Words -MaxWordsPerSegment $MaxWordsPerSegment
}

# Rule-based fallback: split by word count
function Split-TextByRules {
    param(
        [array]$Words,
        [int]$MaxWordsPerSegment
    )

    $segments = @()
    $wordTexts = @($Words | ForEach-Object { $_.Word })

    for ($i = 0; $i -lt $wordTexts.Count; $i += $MaxWordsPerSegment) {
        $endIdx = [Math]::Min($i + $MaxWordsPerSegment - 1, $wordTexts.Count - 1)
        $segmentWords = $wordTexts[$i..$endIdx]

        $segments += @{
            StartIndex = $i
            EndIndex = $endIdx
            Text = $segmentWords -join ' '
        }
    }

    return $segments
}

#endregion

#region Subtitle Translation

# Translate subtitles using AI with context awareness and glossary support
function Invoke-SubtitleTranslate {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries,
        [string]$SourceLanguage = "English",
        [string]$TargetLanguage = "Chinese (Simplified)",
        [hashtable]$Glossary = @{},
        [int]$BatchSize = 20,
        [int]$ContextSize = 3,
        [switch]$Quiet
    )

    # Build glossary instruction
    $glossaryInstruction = ""
    if ($Glossary.Count -gt 0) {
        $glossaryTerms = $Glossary.GetEnumerator() | ForEach-Object { "  - `"$($_.Key)`" -> `"$($_.Value)`"" }
        $glossaryInstruction = @"

GLOSSARY (use these exact translations):
$($glossaryTerms -join "`n")
"@
    }

    $systemPrompt = @"
You are a professional subtitle translator. Translate from $SourceLanguage to $TargetLanguage.

Rules:
1. Maintain the original meaning and tone
2. Use natural, conversational language appropriate for subtitles
3. Keep translations concise (subtitles should be readable quickly)
4. Preserve proper nouns unless they have established translations
5. Output format: JSON array with objects containing "index", "translation"
$glossaryInstruction
Respond ONLY with the JSON array, no explanations.
"@

    $translatedEntries = @()

    # Save original window title for progress display
    $originalTitle = Save-WindowTitle

    # Process in batches
    $totalBatches = [math]::Ceiling($Entries.Count / $BatchSize)

    try {
        for ($batchIndex = 0; $batchIndex -lt $totalBatches; $batchIndex++) {
            # Update window title with progress
            Set-VtsWindowTitle -Phase Translate -Status "Translating batch $($batchIndex + 1)/$totalBatches..."

            $startIdx = $batchIndex * $BatchSize
            $endIdx = [math]::Min($startIdx + $BatchSize - 1, $Entries.Count - 1)

            # Get context from previous batch
            $contextStart = [math]::Max(0, $startIdx - $ContextSize)
            $contextEntries = @()
            if ($contextStart -lt $startIdx -and $translatedEntries.Count -gt 0) {
                $contextEntries = $translatedEntries[($translatedEntries.Count - $ContextSize)..($translatedEntries.Count - 1)]
            }

            # Prepare batch
            $batchEntries = @()
            for ($i = $startIdx; $i -le $endIdx; $i++) {
                $batchEntries += @{
                    index = $i
                    text = $Entries[$i].Text
                }
            }

            # Build user prompt
            $contextSection = ""
            if ($contextEntries.Count -gt 0) {
                $contextText = $contextEntries | ForEach-Object {
                    "- Original: $($_.Original)`n  Translation: $($_.Translation)"
                }
                $contextSection = "Previous context for reference:`n$($contextText -join "`n")`n`n"
            }

            $userPrompt = "${contextSection}Translate these subtitles:`n" + ($batchEntries | ConvertTo-Json -Depth 5)

            try {
                if (-not $Quiet) { Show-Detail "Translating batch $($batchIndex + 1)/$totalBatches..." }

                $response = Invoke-AiCompletion -SystemPrompt $systemPrompt -UserPrompt $userPrompt -Temperature 0.3

                # Extract JSON with enhanced parsing
                $jsonContent = $response
                # 1. Try Markdown code block
                if ($response -match '```(?:json)?\s*([\s\S]*?)\s*```') {
                    $jsonContent = $Matches[1]
                }
                # 2. Try JSON array [...]
                elseif ($response -match '\[[\s\S]*\]') {
                    $jsonContent = $Matches[0]
                }
                # 3. Try JSON object {...}
                elseif ($response -match '\{[\s\S]*\}') {
                    $jsonContent = $Matches[0]
                }
                $jsonContent = $jsonContent.Trim()
                # Remove trailing punctuation after JSON (like "}." or "},")
                $jsonContent = $jsonContent -replace '\}[\s]*[.,;:!?]+\s*$', '}'
                $jsonContent = $jsonContent -replace '\][\s]*[.,;:!?]+\s*$', ']'

                $translations = $jsonContent | ConvertFrom-Json

                # Map translations back to entries
                foreach ($trans in $translations) {
                    $idx = $trans.index
                    if ($idx -ge 0 -and $idx -lt $Entries.Count) {
                        $translatedEntries += @{
                            StartTime = $Entries[$idx].StartTime
                            EndTime = $Entries[$idx].EndTime
                            Original = $Entries[$idx].Text
                            Translation = $trans.translation
                        }
                    }
                }
            }
            catch {
                Write-Warning "Batch $($batchIndex + 1) translation failed: $_"
                # Add untranslated entries
                for ($i = $startIdx; $i -le $endIdx; $i++) {
                    $translatedEntries += @{
                        StartTime = $Entries[$i].StartTime
                        EndTime = $Entries[$i].EndTime
                        Original = $Entries[$i].Text
                        Translation = "[Translation failed]"
                    }
                }
            }
        }
    }
    finally {
        # Restore original window title
        Restore-WindowTitle -Title $originalTitle
    }

    return $translatedEntries
}

#endregion

#region Proofreading

# Global proofreading of translated subtitles with batch processing
function Invoke-GlobalProofread {
    param(
        [Parameter(Mandatory=$true)]
        [array]$BilingualEntries,
        [string]$TargetLanguage = "Chinese (Simplified)",
        [int]$BatchSize = 50,
        [switch]$Quiet
    )

    if ($BilingualEntries.Count -eq 0) {
        return $BilingualEntries
    }

    $systemPrompt = @"
You are a subtitle proofreader for $TargetLanguage translations.

Review and improve the translations:
1. Fix any awkward phrasing or unnatural expressions
2. Ensure consistency in terminology throughout
3. For Chinese: Add proper spacing between Chinese and English/numbers
4. For Chinese: Replace Chinese punctuation (comma, period) with spaces for subtitle readability
5. Keep the meaning faithful to the original
6. Output format: JSON array with objects containing "index", "translation"

Only include entries that need changes. Respond ONLY with the JSON array.
"@

    # Clone the entries to avoid modifying the original
    $result = @()
    foreach ($entry in $BilingualEntries) {
        $result += @{
            StartTime = $entry.StartTime
            EndTime = $entry.EndTime
            Original = $entry.Original
            Translation = $entry.Translation
        }
    }

    $totalBatches = [math]::Ceiling($BilingualEntries.Count / $BatchSize)
    $originalTitle = Save-WindowTitle

    try {
        for ($batchIndex = 0; $batchIndex -lt $totalBatches; $batchIndex++) {
            Set-VtsWindowTitle -Phase Translate -Status "Proofreading batch $($batchIndex + 1)/$totalBatches..."

            $startIdx = $batchIndex * $BatchSize
            $endIdx = [math]::Min($startIdx + $BatchSize - 1, $BilingualEntries.Count - 1)

            # Prepare batch input with original indices
            $batchInput = @()
            for ($i = $startIdx; $i -le $endIdx; $i++) {
                $batchInput += @{
                    index = $i
                    original = $BilingualEntries[$i].Original
                    translation = $BilingualEntries[$i].Translation
                }
            }

            $userPrompt = "Proofread these translations (batch $($batchIndex + 1)/$totalBatches):`n" + ($batchInput | ConvertTo-Json -Depth 5)

            try {
                if (-not $Quiet) { Show-Detail "Proofreading batch $($batchIndex + 1)/$totalBatches..." }

                $response = Invoke-AiCompletion -SystemPrompt $systemPrompt -UserPrompt $userPrompt -Temperature 0.2 -MaxTokens 4096

                # Extract JSON with enhanced parsing
                $jsonContent = $response

                # 1. Try Markdown code block
                if ($response -match '```(?:json)?\s*([\s\S]*?)\s*```') {
                    $jsonContent = $Matches[1]
                }
                # 2. Try JSON array [...]
                elseif ($response -match '\[[\s\S]*\]') {
                    $jsonContent = $Matches[0]
                }
                # 3. Handle multiple JSON objects (not in array)
                # AI sometimes returns: {obj1}, {obj2}, ... instead of [{obj1}, {obj2}]
                elseif ($response -match '\{[^{}]*"index"') {
                    # Extract all JSON objects and wrap in array
                    $objects = [regex]::Matches($response, '\{[^{}]*"index"[^{}]*"translation"[^{}]*\}')
                    if ($objects.Count -gt 0) {
                        $jsonContent = '[' + (($objects | ForEach-Object { $_.Value }) -join ',') + ']'
                    }
                }
                # 4. Single JSON object {...}
                elseif ($response -match '\{[\s\S]*\}') {
                    $jsonContent = $Matches[0]
                }

                # Clean up common issues
                $jsonContent = $jsonContent.Trim()
                # Remove trailing punctuation after JSON (like "}." or "},")
                $jsonContent = $jsonContent -replace '\}[\s]*[.,;:!?]+\s*$', '}'
                $jsonContent = $jsonContent -replace '\][\s]*[.,;:!?]+\s*$', ']'

                # Skip if empty response (no changes needed for this batch)
                if (-not $jsonContent -or $jsonContent -eq '[]') {
                    continue
                }

                $corrections = $jsonContent | ConvertFrom-Json

                # Apply corrections to result
                foreach ($correction in $corrections) {
                    $idx = $correction.index
                    if ($idx -ge 0 -and $idx -lt $result.Count) {
                        $result[$idx].Translation = $correction.translation
                    }
                }
            }
            catch {
                Write-Warning "Batch $($batchIndex + 1) proofreading failed: $_"
                # Continue with other batches
            }
        }
    }
    finally {
        Restore-WindowTitle -Title $originalTitle
    }

    return $result
}

#endregion

#region Source Proofreading

# Proofread source text (for auto-generated subtitles)
function Invoke-SourceProofread {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries,
        [hashtable]$Glossary = @{},
        [int]$BatchSize = 30,
        [switch]$Quiet
    )

    if ($Entries.Count -eq 0) {
        return $Entries
    }

    # Build glossary terms list for prompt
    $glossaryInstruction = ""
    if ($Glossary.Count -gt 0) {
        $termsList = @($Glossary.Keys | Select-Object -First 50) -join ", "
        $glossaryInstruction = "`nTerminology to normalize (use exact spelling): $termsList"
    }

    $systemPrompt = @"
You are a subtitle proofreader for auto-generated subtitles.

Fix these issues:
1. Speech recognition errors (e.g., "their" vs "there", misheared words)
2. Missing punctuation (add periods, commas, question marks where appropriate)
3. Normalize terminology spelling based on the glossary$glossaryInstruction

Output format: JSON array with objects containing "index", "text"
Only include entries that need changes. Respond ONLY with the JSON array.
"@

    # Clone entries
    $result = @()
    foreach ($entry in $Entries) {
        $result += @{
            StartTime = $entry.StartTime
            EndTime = $entry.EndTime
            Text = $entry.Text
        }
    }

    $totalBatches = [math]::Ceiling($Entries.Count / $BatchSize)
    $originalTitle = Save-WindowTitle
    $corrections = 0

    try {
        for ($batchIndex = 0; $batchIndex -lt $totalBatches; $batchIndex++) {
            Set-VtsWindowTitle -Phase SourceProofread -Status "Source proofreading $($batchIndex + 1)/$totalBatches..."

            $startIdx = $batchIndex * $BatchSize
            $endIdx = [math]::Min($startIdx + $BatchSize - 1, $Entries.Count - 1)

            $batchInput = @()
            for ($i = $startIdx; $i -le $endIdx; $i++) {
                $batchInput += @{ index = $i; text = $Entries[$i].Text }
            }

            $userPrompt = "Proofread these auto-generated subtitles:`n" + ($batchInput | ConvertTo-Json -Depth 5)

            try {
                if (-not $Quiet) { Show-Detail "Source proofreading batch $($batchIndex + 1)/$totalBatches..." }

                $response = Invoke-AiCompletion -SystemPrompt $systemPrompt -UserPrompt $userPrompt -Temperature 0.2 -MaxTokens 4096

                # Parse JSON
                $jsonContent = $response
                if ($response -match '\[[\s\S]*\]') {
                    $jsonContent = $Matches[0]
                }
                $jsonContent = $jsonContent.Trim() -replace '\][\s]*[.,;:!?]+\s*$', ']'

                if ($jsonContent -and $jsonContent -ne '[]') {
                    $edits = $jsonContent | ConvertFrom-Json
                    foreach ($edit in $edits) {
                        $idx = $edit.index
                        if ($idx -ge 0 -and $idx -lt $result.Count) {
                            $result[$idx].Text = $edit.text
                            $corrections++
                        }
                    }
                }
            } catch {
                Write-Warning "Batch $($batchIndex + 1) source proofreading failed: $_"
            }
        }
    } finally {
        Restore-WindowTitle -Title $originalTitle
    }

    if (-not $Quiet) { Show-Detail "Corrections: $corrections entries modified" }

    return $result
}

#endregion

#region Test Connection

# Test AI API connection
function Test-AiConnection {
    param()

    if (-not $script:AiClient_ApiKey) {
        return @{
            Success = $false
            Message = "API key not configured"
        }
    }

    try {
        $response = Invoke-AiCompletion -SystemPrompt "You are a test assistant." -UserPrompt "Say 'OK' if you can hear me." -MaxTokens 10

        return @{
            Success = $true
            Message = "Connection successful"
            Model = $script:AiClient_Model
            Response = $response
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
