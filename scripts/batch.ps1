# Batch download module for Video Tools Suite
# Parallel download + sequential translate/mux

# Import dependencies
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}
if (-not (Get-Command "Set-VtsWindowTitle" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\tui-utils.ps1"
}
if (-not (Get-Command "Invoke-VideoDownload" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\download.ps1"
}
if (-not (Get-Command "Invoke-SubtitleTranslator" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\translate.ps1"
}
if (-not (Get-Command "Invoke-SubtitleMuxer" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\mux.ps1"
}
if (-not (Get-Command "Invoke-TranscriptGenerator" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\transcript.ps1"
}

# Configuration (set by vts.ps1)
$script:BatchParallelDownloads = 3
$script:BatchOutputDir = "$PSScriptRoot\..\output"
$script:GenerateTranscriptInWorkflow = $false
$script:TargetLanguage = "zh-Hans"

#region Helper Functions

# Download a single video (for parallel execution in jobs)
function Invoke-SingleDownload {
    param(
        [string]$Url,
        [string]$OutputDir
    )

    try {
        $project = New-VideoProjectDir -Url $Url
        $videoPath = Invoke-VideoDownload -Url $Url -ProjectDir $project.ProjectDir -Quiet
        $subResult = Invoke-SubtitleDownload -Url $Url -ProjectDir $project.ProjectDir -TargetLanguage $script:TargetLanguage -Quiet

        return @{
            Success = $true
            Url = $Url
            ProjectDir = $project.ProjectDir
            VideoPath = $videoPath
            SubtitlePath = $subResult.SubtitleFile
            SubtitleType = $subResult.SubtitleType
            SkipTranslation = $subResult.SkipTranslation
            Title = $project.VideoTitle
            VideoId = $project.VideoId
        }
    }
    catch {
        return @{
            Success = $false
            Url = $Url
            Error = $_.Exception.Message
            Title = $null
            VideoId = $null
        }
    }
}

# Parallel download with TUI progress
function Invoke-ParallelDownload {
    param(
        [string[]]$Urls,
        [int]$MaxParallel = 3
    )

    $total = $Urls.Count
    $completed = 0
    $results = @()
    $jobs = @()
    $urlQueue = [System.Collections.Queue]::new()
    foreach ($url in $Urls) { $urlQueue.Enqueue($url) }

    # Slot tracking
    $slots = @{}
    for ($i = 0; $i -lt $MaxParallel; $i++) {
        $slots[$i] = @{ Status = "waiting"; VideoId = ""; Job = $null }
    }

    # TUI setup
    $tuiStartLine = [Console]::CursorTop

    Write-Host ""
    Write-Host "  [Phase 1/3] Downloading ($MaxParallel parallel)" -ForegroundColor Yellow
    Write-Host "  $(New-ProgressBar -Current 0 -Total $total)"
    Write-Host ""

    # Initialize slot display
    for ($i = 0; $i -lt $MaxParallel; $i++) {
        $icon = $script:StatusIcon.Waiting
        Write-Host "    Slot $($i + 1): $icon (waiting)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  Completed: 0  |  Failed: 0  |  Remaining: $total" -ForegroundColor Gray

    $progressLine = $tuiStartLine + 2
    $slotStartLine = $tuiStartLine + 4
    $summaryLine = $slotStartLine + $MaxParallel + 1

    # Update window title
    Set-VtsWindowTitle -Phase Download -Status "Download [0/$total] $MaxParallel parallel"

    $successCount = 0
    $failedCount = 0

    while ($completed -lt $total) {
        # Start new jobs if slots available and queue not empty
        for ($slotIdx = 0; $slotIdx -lt $MaxParallel; $slotIdx++) {
            if ($slots[$slotIdx].Status -eq "waiting" -and $urlQueue.Count -gt 0) {
                $url = $urlQueue.Dequeue()
                $videoId = Get-VideoId -Url $url

                # Update slot display - starting
                $icon = $script:StatusIcon.InProgress
                Write-AtPosition -X 4 -Y ($slotStartLine + $slotIdx) `
                    -Text "Slot $($slotIdx + 1): $icon [$videoId] Downloading..." -Color Cyan

                # Start job
                $job = Start-Job -ScriptBlock {
                    param($ScriptRoot, $Url, $TargetLang)
                    . "$ScriptRoot\utils.ps1"
                    . "$ScriptRoot\download.ps1"
                    $script:TargetLanguage = $TargetLang

                    try {
                        $project = New-VideoProjectDir -Url $Url
                        $videoPath = Invoke-VideoDownload -Url $Url -ProjectDir $project.ProjectDir -Quiet
                        $subResult = Invoke-SubtitleDownload -Url $Url -ProjectDir $project.ProjectDir -TargetLanguage $script:TargetLanguage -Quiet

                        return @{
                            Success = $true
                            Url = $Url
                            ProjectDir = $project.ProjectDir
                            VideoPath = $videoPath
                            SubtitlePath = $subResult.SubtitleFile
                            SubtitleType = $subResult.SubtitleType
                            SkipTranslation = $subResult.SkipTranslation
                            Title = $project.VideoTitle
                            VideoId = $project.VideoId
                        }
                    }
                    catch {
                        return @{
                            Success = $false
                            Url = $Url
                            Error = $_.Exception.Message
                            Title = $null
                            VideoId = $null
                        }
                    }
                } -ArgumentList $PSScriptRoot, $url, $script:TargetLanguage

                $slots[$slotIdx] = @{ Status = "running"; VideoId = $videoId; Job = $job; Url = $url }
            }
        }

        # Check for completed jobs
        for ($slotIdx = 0; $slotIdx -lt $MaxParallel; $slotIdx++) {
            if ($slots[$slotIdx].Status -eq "running" -and $slots[$slotIdx].Job.State -eq 'Completed') {
                $result = Receive-Job -Job $slots[$slotIdx].Job
                Remove-Job -Job $slots[$slotIdx].Job

                $completed++
                $results += $result

                # Update counters
                if ($result.Success) {
                    $successCount++
                    $icon = $script:StatusIcon.Done
                    $color = "Green"
                    $status = "Done"
                } else {
                    $failedCount++
                    $icon = $script:StatusIcon.Failed
                    $color = "Red"
                    $status = "Failed"
                }

                # Update slot display - completed
                Write-AtPosition -X 4 -Y ($slotStartLine + $slotIdx) `
                    -Text "Slot $($slotIdx + 1): $icon [$($slots[$slotIdx].VideoId)] $status" -Color $color

                # Mark slot as waiting for next job
                $slots[$slotIdx] = @{ Status = "waiting"; VideoId = ""; Job = $null }

                # Update progress bar
                Write-AtPosition -X 2 -Y $progressLine `
                    -Text (New-ProgressBar -Current $completed -Total $total) -Color White

                # Update summary line
                Write-AtPosition -X 2 -Y $summaryLine `
                    -Text "Completed: $successCount  |  Failed: $failedCount  |  Remaining: $($total - $completed)" -Color Gray

                # Update window title
                Set-VtsWindowTitle -Phase Download -Status "Download [$completed/$total] $MaxParallel parallel"
            }
            elseif ($slots[$slotIdx].Status -eq "running" -and $slots[$slotIdx].Job.State -eq 'Failed') {
                # Handle failed jobs
                $errorMsg = $slots[$slotIdx].Job.ChildJobs[0].JobStateInfo.Reason.Message
                Remove-Job -Job $slots[$slotIdx].Job -Force

                $completed++
                $failedCount++
                $results += @{
                    Success = $false
                    Url = $slots[$slotIdx].Url
                    Error = $errorMsg
                    VideoId = $slots[$slotIdx].VideoId
                }

                $icon = $script:StatusIcon.Failed
                Write-AtPosition -X 4 -Y ($slotStartLine + $slotIdx) `
                    -Text "Slot $($slotIdx + 1): $icon [$($slots[$slotIdx].VideoId)] Failed" -Color Red

                $slots[$slotIdx] = @{ Status = "waiting"; VideoId = ""; Job = $null }

                # Update progress and summary
                Write-AtPosition -X 2 -Y $progressLine `
                    -Text (New-ProgressBar -Current $completed -Total $total) -Color White
                Write-AtPosition -X 2 -Y $summaryLine `
                    -Text "Completed: $successCount  |  Failed: $failedCount  |  Remaining: $($total - $completed)" -Color Gray
                Set-VtsWindowTitle -Phase Download -Status "Download [$completed/$total] $MaxParallel parallel"
            }
        }

        Start-Sleep -Milliseconds 300
    }

    Write-Host ""
    return $results
}

#endregion

#region Main Functions

# Process multiple URLs with parallel download + sequential translate/mux
function Invoke-BatchWorkflow {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Urls,
        [switch]$SkipTranslate,
        [switch]$SkipMux
    )

    $total = $Urls.Count
    $originalTitle = Save-WindowTitle

    Show-Info "Starting batch processing: $total videos"
    Write-Host ""

    #region Phase 1: Parallel Download
    $downloadResults = Invoke-ParallelDownload -Urls $Urls -MaxParallel $script:BatchParallelDownloads

    $successfulDownloads = @($downloadResults | Where-Object { $_.Success })
    $failedDownloads = @($downloadResults | Where-Object { -not $_.Success })

    if ($successfulDownloads.Count -eq 0) {
        Show-Error "All downloads failed!"
        Restore-WindowTitle -Title $originalTitle
        return @{
            Total = $total
            Success = 0
            Failed = $failedDownloads
        }
    }

    Show-Success "Downloads complete: $($successfulDownloads.Count) succeeded, $($failedDownloads.Count) failed"
    Write-Host ""
    #endregion

    #region Phase 2: Transcript (optional, sequential)
    if ($script:GenerateTranscriptInWorkflow) {
        Write-Host "  [Phase 2/3] Generating transcripts" -ForegroundColor Yellow

        $transcriptCount = 0
        foreach ($item in $successfulDownloads) {
            if ($item.SubtitlePath) {
                $transcriptCount++
                Set-VtsWindowTitle -Phase Transcript -Status "Transcript [$transcriptCount/$($successfulDownloads.Count)]"

                $transcriptPath = Join-Path $item.ProjectDir "transcript.txt"
                try {
                    Invoke-TranscriptGenerator -InputPath $item.SubtitlePath -OutputPath $transcriptPath -Quiet | Out-Null
                } catch {
                    # Transcript failure is non-fatal
                    Show-Warning "    Transcript failed for $($item.VideoId): $_"
                }
            }
        }
        Show-Success "  Transcripts generated: $transcriptCount"
        Write-Host ""
    }
    #endregion

    #region Phase 3: Translate + Mux (sequential)
    if (-not $SkipTranslate) {
        Write-Host "  [Phase 3/3] Translating and muxing" -ForegroundColor Yellow

        $processCount = 0
        foreach ($item in $successfulDownloads) {
            $processCount++
            $displayName = if ($item.Title) { $item.Title } else { $item.VideoId }

            # Skip if no subtitle or translation not needed
            if ($item.SkipTranslation -or -not $item.SubtitlePath) {
                $icon = $script:StatusIcon.Skipped
                Show-Hint "    $icon [$processCount/$($successfulDownloads.Count)] $displayName (no translation needed)"
                continue
            }

            Show-Detail "    [$processCount/$($successfulDownloads.Count)] $displayName"

            try {
                # Translate
                Set-VtsWindowTitle -Phase Translate -Status "Translate [$processCount/$($successfulDownloads.Count)]"
                $bilingualPath = Join-Path $item.ProjectDir "bilingual.ass"
                Invoke-SubtitleTranslator -InputPath $item.SubtitlePath -OutputPath $bilingualPath -Quiet | Out-Null

                # Mux
                if (-not $SkipMux -and $item.VideoPath) {
                    Set-VtsWindowTitle -Phase Mux -Status "Mux [$processCount/$($successfulDownloads.Count)]"
                    $outputMkv = Join-Path $script:BatchOutputDir "$($item.VideoId).mkv"
                    Invoke-SubtitleMuxer -VideoPath $item.VideoPath -SubtitlePath $bilingualPath -OutputPath $outputMkv -Quiet | Out-Null
                }

                $icon = $script:StatusIcon.Done
                Show-Success "    $icon $displayName"
                $item.TranslateSuccess = $true
            }
            catch {
                $icon = $script:StatusIcon.Failed
                Show-Error "    $icon ${displayName}: $_"
                $item.TranslateSuccess = $false
                $item.TranslateError = $_.Exception.Message
            }
        }
        Write-Host ""
    }
    #endregion

    # Restore window title
    Restore-WindowTitle -Title $originalTitle

    # Final summary
    $translateFailed = @($successfulDownloads | Where-Object { $_.TranslateSuccess -eq $false })
    $totalSuccess = $successfulDownloads.Count - $translateFailed.Count

    Write-Host ""
    if ($failedDownloads.Count -eq 0 -and $translateFailed.Count -eq 0) {
        Show-Success "[SUCCESS] Batch complete: $totalSuccess / $total"
    } else {
        Show-Warning "[COMPLETE] Success: $totalSuccess / $total"

        if ($failedDownloads.Count -gt 0) {
            Write-Host ""
            Show-Error "Download failures:"
            foreach ($item in $failedDownloads) {
                $displayName = if ($item.VideoId) { $item.VideoId } else { $item.Url }
                Show-Error "  - $displayName"
                Show-Hint "    $($item.Error)"
            }
        }

        if ($translateFailed.Count -gt 0) {
            Write-Host ""
            Show-Error "Translate/Mux failures:"
            foreach ($item in $translateFailed) {
                Show-Error "  - $($item.Title)"
                Show-Hint "    $($item.TranslateError)"
            }
        }
    }

    return @{
        Total = $total
        Success = $totalSuccess
        DownloadFailed = $failedDownloads
        TranslateFailed = $translateFailed
    }
}

# Retry failed items from a previous batch
function Invoke-BatchRetry {
    param(
        [Parameter(Mandatory=$true)]
        [array]$FailedItems
    )

    $urls = $FailedItems | ForEach-Object { $_.Url }
    return Invoke-BatchWorkflow -Urls $urls
}

#endregion
