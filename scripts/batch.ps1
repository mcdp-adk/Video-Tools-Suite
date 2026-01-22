# Batch download module for Video Tools Suite
# Sequential processing (one video at a time)

# Import utils for Show-* message functions
if (-not (Get-Command "Show-Success" -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\utils.ps1"
}

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

    Show-Info "Starting batch processing: $total videos"
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
            Show-Step "[$completedCount/$total] Processing: $($result.Title)"

            Invoke-FullWorkflow -InputUrl $url -GenerateTranscript:$script:GenerateTranscriptInWorkflow
            $result.Success = $true
            Show-Success "[$completedCount/$total] OK: $($result.Title)"
        }
        catch {
            $result.Error = $_.Exception.Message
            $displayName = if ($result.Title) { $result.Title } else { $url }
            Show-Error "[$completedCount/$total] FAILED: $displayName"
            Show-Hint "  Error: $($result.Error)"
        }

        $results += $result
        Write-Host ""
    }

    $Host.UI.RawUI.WindowTitle = $originalTitle

    # Summary
    $successCount = ($results | Where-Object { $_.Success }).Count
    $failedResults = @($results | Where-Object { -not $_.Success })

    if ($failedResults.Count -eq 0) {
        Show-Success "[SUCCESS] Batch complete: $successCount / $total"
    } else {
        Show-Warning "[COMPLETE] Success: $successCount / $total, Failed: $($failedResults.Count)"
        Write-Host ""
        Show-Error "Failed items:"
        foreach ($item in $failedResults) {
            $displayName = if ($item.Title) { $item.Title } else { $item.Url }
            Show-Error "  - $displayName"
            Show-Hint "    $($item.Error)"
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
