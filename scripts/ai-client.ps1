# AI Client module for OpenAI-compatible API calls
# Supports subtitle segmentation, translation, and proofreading

# Dot source dependencies if not already loaded
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}
if (-not (Get-Command "Set-VtsWindowTitle" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\tui-utils.ps1"
}

# Configuration (set by vts.ps1 from config.json)
$script:AiClient_BaseUrl = "https://api.openai.com/v1"
$script:AiClient_ApiKey = ""
$script:AiClient_Model = "gpt-4o-mini"

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

# AI-powered subtitle segmentation for better sentence boundaries
function Invoke-SubtitleSegmentation {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries
    )

    $systemPrompt = @"
You are a subtitle segmentation expert. Your task is to optimize subtitle timing and text boundaries for better readability.

Rules:
1. Keep each subtitle segment between 1-7 seconds
2. End segments at natural sentence boundaries when possible
3. Split long sentences at commas, conjunctions, or natural pauses
4. Preserve the original meaning exactly
5. Output format: JSON array with objects containing "start_ms", "end_ms", "text"

Respond ONLY with the JSON array, no explanations.
"@

    # Prepare input data
    $inputData = $Entries | ForEach-Object {
        @{
            start_ms = [int]$_.StartTime.TotalMilliseconds
            end_ms = [int]$_.EndTime.TotalMilliseconds
            text = $_.Text
        }
    }

    $userPrompt = "Optimize these subtitle segments:`n" + ($inputData | ConvertTo-Json -Depth 5)

    try {
        $response = Invoke-AiCompletion -SystemPrompt $systemPrompt -UserPrompt $userPrompt -Temperature 0.1

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

        $segmented = $jsonContent | ConvertFrom-Json

        # Convert back to our entry format
        $result = $segmented | ForEach-Object {
            @{
                StartTime = [TimeSpan]::FromMilliseconds($_.start_ms)
                EndTime = [TimeSpan]::FromMilliseconds($_.end_ms)
                Text = $_.text
            }
        }

        return $result
    }
    catch {
        Write-Warning "AI segmentation failed, using original entries: $_"
        return $Entries
    }
}

# Merge sentences that are too short (< MinWords)
function Merge-ShortSentences {
    param(
        [array]$Sentences,
        [int]$MinWords = 5
    )

    if ($Sentences.Count -le 1) { return $Sentences }

    $merged = @()
    $buffer = ""

    foreach ($sentence in $Sentences) {
        $wordCount = ($sentence -split '\s+').Count

        if ($buffer) {
            # Add to buffer
            $buffer = "$buffer $sentence"
            $bufferWordCount = ($buffer -split '\s+').Count

            # If buffer is now long enough, flush it
            if ($bufferWordCount -ge $MinWords) {
                $merged += $buffer.Trim()
                $buffer = ""
            }
        }
        elseif ($wordCount -lt $MinWords) {
            # Start buffering
            $buffer = $sentence
        }
        else {
            # Sentence is long enough
            $merged += $sentence
        }
    }

    # Flush remaining buffer
    if ($buffer) {
        if ($merged.Count -gt 0) {
            # Append to last sentence
            $merged[-1] = "$($merged[-1]) $buffer".Trim()
        }
        else {
            $merged += $buffer.Trim()
        }
    }

    return $merged
}

# Split sentences that are too long (> MaxWords)
function Split-LongSentences {
    param(
        [array]$Sentences,
        [int]$MaxWords = 18
    )

    $result = @()

    foreach ($sentence in $Sentences) {
        $wordCount = ($sentence -split '\s+').Count

        if ($wordCount -le $MaxWords) {
            $result += $sentence
        }
        else {
            # Try to split at natural breaks
            $parts = $sentence -split '(?<=[,;])\s+|(?<=\band\b)\s+|(?<=\bbut\b)\s+|(?<=\bthat\b)\s+'

            if ($parts.Count -gt 1) {
                # Recombine parts to stay under limit
                $current = ""
                foreach ($part in $parts) {
                    $testMerge = if ($current) { "$current $part" } else { $part }
                    $testCount = ($testMerge -split '\s+').Count

                    if ($testCount -le $MaxWords) {
                        $current = $testMerge
                    }
                    else {
                        if ($current) { $result += $current.Trim() }
                        $current = $part
                    }
                }
                if ($current) { $result += $current.Trim() }
            }
            else {
                # No natural breaks, just add as-is
                $result += $sentence
            }
        }
    }

    return $result
}

# AI-powered sentence segmentation for auto-generated subtitles
# Uses <br> markers for splitting, with validation and retry loop
function Invoke-SentenceSegmentation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FullText,
        [int]$MaxWordsCjk = 20,
        [int]$MaxWordsEnglish = 18,
        [int]$MaxSteps = 3
    )

    # Cache key based on text hash (avoid duplicate AI calls for same text)
    $textHash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($FullText)
        )
    ).Replace("-", "").Substring(0, 16)

    # Check cache
    if ($script:SentenceCache -and $script:SentenceCache.ContainsKey($textHash)) {
        Show-Detail "Using cached segmentation result"
        return $script:SentenceCache[$textHash]
    }

    $systemPrompt = @"
You are a subtitle segmentation expert. Your task is to insert <br> markers to split text into readable subtitle segments.

RULES:
1. Each segment should be 5-$MaxWordsEnglish words for English, 8-$MaxWordsCjk characters for Chinese
2. If a sentence is shorter than the minimum, combine it with the next sentence
3. Insert <br> at natural breaks: after sentences (. ! ?), at commas, "and", "but", "because"
4. DO NOT create segments with only 1-4 words - combine short phrases
5. DO NOT modify the original words - only insert <br> markers
6. Return ONLY the segmented text, no explanations

BAD (too short): "Oh yeah.<br>Because that's worked."
GOOD (combined): "Oh yeah, because that's worked for the last 10 years.<br>We need to stop spending money."

BAD: "I've given up on<br>women."
GOOD: "I've given up on women.<br>I'm going to start dating men."
"@

    $messages = @(
        @{ role = "user"; content = "Insert <br> markers to segment this text:`n$FullText" }
    )

    $lastResult = $null

    for ($step = 0; $step -lt $MaxSteps; $step++) {
        Show-Detail "Segmenting text with AI (attempt $($step + 1)/$MaxSteps)..."

        $response = Invoke-AiCompletionWithHistory -SystemPrompt $systemPrompt -Messages $messages -Temperature 0.1 -MaxTokens 8192

        # Parse result: remove extra newlines, split by <br>
        $resultText = $response -replace "`r?`n", " "
        $sentences = ($resultText -split '<br>' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $lastResult = $sentences

        # Validate result
        $validation = Test-SentenceSegmentationResult -Original $FullText -Sentences $sentences -MaxWordsCjk $MaxWordsCjk -MaxWordsEnglish $MaxWordsEnglish

        if ($validation.IsValid) {
            # Merge short sentences (< 5 words)
            $sentences = Merge-ShortSentences -Sentences $sentences -MinWords 5
            # Split long sentences (> MaxWords)
            $sentences = Split-LongSentences -Sentences $sentences -MaxWords $MaxWordsEnglish
            Show-Success "  Split into $($sentences.Count) sentences"

            # Store in cache for reuse
            if (-not $script:SentenceCache) { $script:SentenceCache = @{} }
            $script:SentenceCache[$textHash] = $sentences

            return $sentences
        }

        # Add feedback for retry
        Write-Warning "Segmentation validation failed (attempt $($step + 1)): $($validation.Error)"
        $messages += @{ role = "assistant"; content = $response }
        $messages += @{ role = "user"; content = "Error: $($validation.Error)`nYou MUST insert more <br> markers to make segments shorter. Output the COMPLETE original text with additional <br> markers inserted. Do not repeat or modify words." }
    }

    # Return last result or fallback
    if ($lastResult -and $lastResult.Count -gt 0) {
        Write-Warning "Using last segmentation result after $MaxSteps attempts"
        # Still apply post-processing to fallback result
        $lastResult = Merge-ShortSentences -Sentences $lastResult -MinWords 5
        $lastResult = Split-LongSentences -Sentences $lastResult -MaxWords $MaxWordsEnglish

        # Store in cache even for fallback
        if (-not $script:SentenceCache) { $script:SentenceCache = @{} }
        $script:SentenceCache[$textHash] = $lastResult

        return $lastResult
    }

    # Fallback: simple split by punctuation
    Write-Warning "AI segmentation failed, using fallback"
    $fallback = @($FullText -split '[.!?]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    # Store fallback in cache
    if (-not $script:SentenceCache) { $script:SentenceCache = @{} }
    $script:SentenceCache[$textHash] = $fallback

    return $fallback
}

# Split segments that exceed MaxWords*2 at natural break points
# Only splits very long segments; tolerates moderately long ones for better readability
function Split-LongSegments {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Segments,
        [int]$MaxWords = 18
    )

    $result = @()
    $threshold = $MaxWords * 2  # Only split if exceeds this

    # Split point candidates by priority (split BEFORE these words)
    $conjunctions = @('and', 'but', 'so', 'because', 'or', 'yet', 'then', 'although', 'however', 'therefore', 'while', 'when')
    $discourse = @('well', 'now', 'actually', 'basically', 'honestly', 'anyway', 'meanwhile', 'also', 'plus', 'I')

    foreach ($segment in $Segments) {
        $words = @($segment.Text -split '\s+' | Where-Object { $_ })

        if ($words.Count -le $threshold) {
            $result += $segment
            continue
        }

        # Segment is very long, need to split
        Show-Warning "    Splitting very long segment ($($words.Count) words)..."

        $currentStart = 0
        $segmentStartIndex = $segment.StartIndex

        while ($currentStart -lt $words.Count) {
            $remaining = $words.Count - $currentStart

            if ($remaining -le $threshold) {
                # Take all remaining
                $result += @{
                    StartIndex = $segmentStartIndex + $currentStart
                    EndIndex = $segment.EndIndex
                    Text = ($words[$currentStart..($words.Count - 1)] -join ' ')
                }
                break
            }

            # Search for split point in range [MaxWords, MaxWords*2]
            $searchMin = $MaxWords
            $searchMax = [Math]::Min($remaining - 5, $threshold)

            $bestSplit = -1

            # Priority 1: Conjunctions
            for ($i = $searchMax; $i -ge $searchMin; $i--) {
                $wordIdx = $currentStart + $i
                if ($wordIdx -lt $words.Count -and $conjunctions -contains $words[$wordIdx].ToLower()) {
                    $bestSplit = $i
                    break
                }
            }

            # Priority 2: Comma
            if ($bestSplit -lt 0) {
                for ($i = $searchMax; $i -ge $searchMin; $i--) {
                    $wordIdx = $currentStart + $i - 1
                    if ($wordIdx -ge 0 -and $wordIdx -lt $words.Count -and $words[$wordIdx] -match ',$') {
                        $bestSplit = $i
                        break
                    }
                }
            }

            # Priority 3: Discourse markers
            if ($bestSplit -lt 0) {
                for ($i = $searchMax; $i -ge $searchMin; $i--) {
                    $wordIdx = $currentStart + $i
                    if ($wordIdx -lt $words.Count -and $discourse -contains $words[$wordIdx].ToLower()) {
                        $bestSplit = $i
                        break
                    }
                }
            }

            # Last resort: split at threshold (MaxWords*2)
            if ($bestSplit -lt 0) {
                $bestSplit = $threshold
            }

            $endIdx = $currentStart + $bestSplit - 1
            $result += @{
                StartIndex = $segmentStartIndex + $currentStart
                EndIndex = $segmentStartIndex + $endIdx
                Text = ($words[$currentStart..$endIdx] -join ' ')
            }

            $currentStart = $currentStart + $bestSplit
        }
    }

    return $result
}

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

    # Process cues in batches
    for ($batchStart = 0; $batchStart -lt $Cues.Count; $batchStart += $CuesPerBatch) {
        $batchEnd = [Math]::Min($batchStart + $CuesPerBatch - 1, $Cues.Count - 1)
        $batchCues = @($Cues[$batchStart..$batchEnd])

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

# Word-based segmentation: AI inserts <br> markers, we split by word index
# Returns array of objects: @{ StartIndex; EndIndex; Text }
function Invoke-WordBasedSegmentation {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Words,  # Array of @{ Word; StartTime }
        [int]$MaxWordsPerSegment = 18,
        [int]$MinWordsPerSegment = 5,
        [int]$MaxAttempts = 3
    )

    # Build word text for AI
    $wordTexts = @($Words | ForEach-Object { $_.Word })
    $fullText = $wordTexts -join ' '

    # Cache key
    $textHash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($fullText)
        )
    ).Replace("-", "").Substring(0, 16)

    if ($script:SentenceCache -and $script:SentenceCache.ContainsKey($textHash)) {
        Show-Detail "Using cached segmentation result"
        return $script:SentenceCache[$textHash]
    }

    $systemPrompt = @"
You are a subtitle segmentation expert. Insert <br> markers to split text into subtitle segments.

RULES:
1. Each segment should be $MinWordsPerSegment-$MaxWordsPerSegment words
2. Insert <br> at natural breaks: after sentences, at commas, conjunctions (and, but, because, so)
3. DO NOT modify any words - only insert <br> markers between words
4. DO NOT create segments shorter than $MinWordsPerSegment words unless it's the last segment
5. Return ONLY the text with <br> markers, no explanations

Example input: "well I think the biggest problem with this club is that we keep making the same mistakes over and over again and nobody seems to learn from them so we end up in the same position every single year and the fans are just tired of watching this happen"
Example output: "well I think the biggest problem with this club<br>is that we keep making the same mistakes over and over again<br>and nobody seems to learn from them<br>so we end up in the same position every single year<br>and the fans are just tired of watching this happen"
"@

    $userPrompt = "Insert <br> markers to segment this text:`n$fullText"

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Show-Detail "Segmenting with word-based method (attempt $attempt/$MaxAttempts)..."

        $response = Invoke-AiCompletion -SystemPrompt $systemPrompt -UserPrompt $userPrompt -Temperature 0.1 -MaxTokens 8192

        # Clean response
        $segmentedText = ($response -replace "`r?`n", " ").Trim()

        # Validate: check word count matches
        $responseWords = @(($segmentedText -replace '<br>', ' ') -split '\s+' | Where-Object { $_ })
        if ($responseWords.Count -ne $wordTexts.Count) {
            Show-Warning "    Word count mismatch: expected $($wordTexts.Count), got $($responseWords.Count)"
            $userPrompt = "Error: You modified the text. Original has $($wordTexts.Count) words, your response has $($responseWords.Count). Return the EXACT original text with only <br> markers inserted:`n$fullText"
            continue
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

            if ($endIndex -ge $Words.Count) {
                Show-Warning "    Index out of range: endIndex=$endIndex, Words.Count=$($Words.Count)"
                break
            }

            $segments += @{
                StartIndex = $startIndex
                EndIndex = $endIndex
                Text = $partWords -join ' '
            }

            $currentWordIndex = $endIndex + 1
        }

        if ($segments.Count -gt 0) {
            # Post-process: split any segments that exceed MaxWordsPerSegment
            $segments = Split-LongSegments -Segments $segments -MaxWords $MaxWordsPerSegment

            Show-Success "  Split into $($segments.Count) segments"

            # Cache result
            if (-not $script:SentenceCache) { $script:SentenceCache = @{} }
            $script:SentenceCache[$textHash] = $segments

            return $segments
        }
    }

    # Fallback: single segment
    Show-Warning "  Word-based segmentation failed, using single segment"
    return @(@{
        StartIndex = 0
        EndIndex = $Words.Count - 1
        Text = $fullText
    })
}

# Validate sentence segmentation result
function Test-SentenceSegmentationResult {
    param(
        [string]$Original,
        [array]$Sentences,
        [int]$MaxWordsCjk,
        [int]$MaxWordsEnglish
    )

    if (-not $Sentences -or $Sentences.Count -eq 0) {
        return @{ IsValid = $false; Error = "No segmentation result" }
    }

    # Check content integrity (similarity >= 96%)
    $originalClean = ($Original -replace '\s+', ' ').Trim()
    $isCjk = (($originalClean -replace '[^\u4e00-\u9fff]', '').Length) -gt ($originalClean.Length * 0.3)
    $joinChar = if ($isCjk) { "" } else { " " }
    $merged = ($Sentences -join $joinChar)
    $mergedClean = ($merged -replace '\s+', ' ').Trim()

    $similarity = Get-TextSimilarity -Text1 $originalClean -Text2 $mergedClean
    if ($similarity -lt 0.96) {
        return @{ IsValid = $false; Error = "Content modified (similarity: $([math]::Round($similarity * 100))%)" }
    }

    # Check segment length limits
    $maxAllowed = if ($isCjk) { $MaxWordsCjk } else { $MaxWordsEnglish }
    foreach ($sentence in $Sentences) {
        $wordCount = if ($isCjk) {
            ($sentence -replace '[^\u4e00-\u9fff]', '').Length
        } else {
            ($sentence -split '\s+').Count
        }

        $tolerance = $maxAllowed * 3  # 3x tolerance: 18 * 3 = 54
        if ($wordCount -gt $tolerance) {
            $preview = if ($sentence.Length -gt 30) { $sentence.Substring(0, 30) + "..." } else { $sentence }
            return @{ IsValid = $false; Error = "Segment too long: '$preview' ($wordCount > $tolerance)" }
        }
    }

    return @{ IsValid = $true; Error = $null }
}

# Calculate text similarity using character-level Jaccard coefficient
function Get-TextSimilarity {
    param(
        [string]$Text1,
        [string]$Text2
    )

    # Normalize: lowercase, remove extra spaces
    $t1 = ($Text1.ToLower() -replace '\s+', ' ').Trim()
    $t2 = ($Text2.ToLower() -replace '\s+', ' ').Trim()

    if ($t1 -eq $t2) { return 1.0 }
    if (-not $t1 -or -not $t2) { return 0.0 }

    # Character-level Jaccard similarity
    $set1 = [System.Collections.Generic.HashSet[char]]::new($t1.ToCharArray())
    $set2 = [System.Collections.Generic.HashSet[char]]::new($t2.ToCharArray())

    $intersection = [System.Collections.Generic.HashSet[char]]::new($set1)
    $intersection.IntersectWith($set2)

    $union = [System.Collections.Generic.HashSet[char]]::new($set1)
    $union.UnionWith($set2)

    return $intersection.Count / [math]::Max(1, $union.Count)
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
