# CI Monitor v1.4.0
$h = @{"Accept"="application/vnd.github+json"; "User-Agent"="ci-monitor"}
$start = Get-Date
$tagRunId = $null

for ($i = 1; $i -le 65; $i++) {
    Start-Sleep -Seconds 60
    $allDone = $true
    $statuses = @()
    try {
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/wcdmac/open-live-writer-flutter/actions/runs?per_page=10" -Headers $h
        $active = $r.workflow_runs | Where-Object { $_.status -ne "completed" -and $_.run_number -gt 13 }
        if ($active) { $allDone = $false }
        $tagRun = $r.workflow_runs | Where-Object { $_.head_branch -eq "v1.4.0" } | Select-Object -First 1
        if ($tagRun) { $tagRunId = $tagRun.id }
        $statuses = ($r.workflow_runs | Select-Object -First 3 | ForEach-Object { "#$($_.run_number): $($_.status)/$($_.conclusion)" })
    } catch {
        $statuses = @("API error: $($_.Exception.Message)")
        $allDone = $false
    }
    $elapsed = [int]((Get-Date) - $start).TotalMinutes
    Write-Host "[$elapsed min] $($statuses -join ' | ')"
    if ($allDone) { Write-Host "ALL_RUNS_COMPLETED"; break }
}
Write-Host "===== FINAL STATUS (tag run) ====="
try {
    if ($tagRunId) {
        $jobs = Invoke-RestMethod -Uri "https://api.github.com/repos/wcdmac/open-live-writer-flutter/actions/runs/$tagRunId/jobs" -Headers $h
        foreach ($j in $jobs.jobs) { Write-Host "  [$($j.conclusion)] $($j.name)" }
    }
} catch { Write-Host "final detail error: $($_.Exception.Message)" }
