# Batch download module for Video Tools Suite
# Sequential processing (one video at a time)

# Process multiple URLs sequentially with full workflow
function Invoke-BatchWorkflow {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Urls
    )

    $total = $Urls.Count
    $originalTitle = $Host.UI.RawUI.WindowTitle
    $completedCount = 0
    $results = @()

    Write-Host "Starting batch processing: $total videos" -ForegroundColor Cyan
    Write-Host ""

    foreach ($url in $Urls) {
        $completedCount++
        $Host.UI.RawUI.WindowTitle = "批量处理 [$completedCount/$total]"

        $result = @{
            Url = $url
            Success = $false
            Error = $null
            Title = $null
        }

        try {
            $result.Title = Get-VideoTitle -Url $url
            Write-Host "[$completedCount/$total] Processing: $($result.Title)" -ForegroundColor Yellow

            Invoke-FullWorkflow -InputUrl $url -GenerateTranscript:$script:GenerateTranscriptInWorkflow
            $result.Success = $true
            Write-Host "[$completedCount/$total] OK: $($result.Title)" -ForegroundColor Green
        }
        catch {
            $result.Error = $_.Exception.Message
            $displayName = if ($result.Title) { $result.Title } else { $url }
            Write-Host "[$completedCount/$total] FAILED: $displayName" -ForegroundColor Red
            Write-Host "  Error: $($result.Error)" -ForegroundColor DarkGray
        }

        $results += $result
        Write-Host ""
    }

    $Host.UI.RawUI.WindowTitle = $originalTitle

    # Summary
    $successCount = ($results | Where-Object { $_.Success }).Count
    $failedResults = @($results | Where-Object { -not $_.Success })

    if ($failedResults.Count -eq 0) {
        Write-Host "[SUCCESS] Batch complete: $successCount / $total" -ForegroundColor Green
    } else {
        Write-Host "[COMPLETE] Success: $successCount / $total, Failed: $($failedResults.Count)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Failed items:" -ForegroundColor Red
        foreach ($item in $failedResults) {
            $displayName = if ($item.Title) { $item.Title } else { $item.Url }
            Write-Host "  - $displayName" -ForegroundColor Red
            Write-Host "    $($item.Error)" -ForegroundColor DarkGray
        }
    }

    return @{
        Total = $total
        Success = $successCount
        Failed = $failedResults
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
