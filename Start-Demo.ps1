<#
    One-step launcher for the Stacks What-If demo.
    Checks Azure, shows the title, runs the demo. Press Enter whenever the script says [Enter.]

        .\Start-Demo.ps1             # live (falls back to saved results if Azure isn't ready)
        .\Start-Demo.ps1 -Replay     # saved results only, no network
        .\Start-Demo.ps1 -From 6     # restart at step 6
#>
[CmdletBinding()]
param([int]$From = 1, [switch]$NoPause, [switch]$Replay)

# Clear the screen, but never fail when there is no real console (e.g. automated tests).
function Reset-Screen { try { Clear-Host } catch { } }

$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
try { $Host.UI.RawUI.WindowTitle = 'Stacks What-If demo' } catch { }

$demo   = Join-Path $PSScriptRoot 'demo.ps1'
$psExe  = (Get-Process -Id $PID).Path
$timing = Join-Path $env:TEMP 'stacks-demo-timing.txt'

function Write-Timing([string]$Label) {
    try { Add-Content -Path $timing -Value ('{0}|{1}' -f (Get-Date).ToString('o'), $Label) -Encoding ASCII } catch { }
}

# Wait for a fresh Enter. Keys pressed early are thrown away, so nothing gets skipped.
function Wait-Enter {
    if ($NoPause) { return }
    try {
        while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
        do { $k = [Console]::ReadKey($true) } until ($k.Key -eq [ConsoleKey]::Enter)
    }
    catch { [void][Console]::ReadLine() }
}

# VS Code can open this terminal very narrow, and with the big demo font the text needs about 64
# characters wide. Wait here until the terminal has been dragged wider.
function Get-TermWidth { try { $Host.UI.RawUI.WindowSize.Width } catch { 0 } }
if (-not $NoPause) {
    $w = Get-TermWidth
    if ($w -gt 0 -and $w -lt 64) {
        Reset-Screen
        Write-Host ''
        Write-Host '  This terminal is too narrow.' -ForegroundColor Yellow
        Write-Host '  Drag its left edge left, to about the middle of the screen.' -ForegroundColor Yellow
        Write-Host '  The demo carries on by itself.' -ForegroundColor DarkGray
        while ((Get-TermWidth) -lt 64) { Start-Sleep -Milliseconds 250 }
    }
}

Reset-Screen
Write-Host ''
Write-Host '  Getting ready, one moment...' -ForegroundColor DarkGray

$pfArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $demo, '-Preflight')
if ($Replay) { $pfArgs += '-Replay' }
$check = & $psExe @pfArgs 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -and -not $Replay) {
    # Live isn't ready (no network, not signed in, stack not prepared). Fall back to saved results.
    $replayCheck = & $psExe -NoProfile -ExecutionPolicy Bypass -File $demo -Preflight -Replay 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Reset-Screen
        Write-Host ''
        Write-Host '  Azure is not ready, so this run uses saved results from the last good run.' -ForegroundColor Yellow
        Write-Host ($check.Trim() -split "`r?`n" | Where-Object { $_ -match 'MISS|FAIL' } | Select-Object -First 2 | ForEach-Object { '  ' + $_.Trim() }) -ForegroundColor DarkGray
        Write-Host '  Press Enter to continue.' -ForegroundColor DarkGray
        Wait-Enter
        $Replay = $true
    }
    else {
        Reset-Screen
        Write-Host '  Something is not ready. Here is what the check found:' -ForegroundColor Red
        Write-Host $check
        Write-Host '  Screenshot this window and paste it into the Copilot chat.' -ForegroundColor Yellow
        Wait-Enter
        exit 1
    }
}

if ($From -le 1) {
    Remove-Item $timing -ErrorAction SilentlyContinue
    Reset-Screen
    Write-Host ''
    Write-Host '  Deployment Stacks  +  What-If' -ForegroundColor Cyan
    Write-Host '  NIC 2026, Oslo' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [Enter] start' -ForegroundColor DarkGray
    Write-Timing 'title'
    # Enter starts at step 1. A number key starts at that step (0 is step 10), for when the
    # terminal got closed in the middle of the demo.
    if (-not $NoPause) {
        try {
            while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
            while ($true) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq [ConsoleKey]::Enter) { break }
                if ($k.KeyChar -match '^[0-9]$') { $From = if ($k.KeyChar -eq '0') { 10 } else { [int]"$($k.KeyChar)" }; break }
            }
        }
        catch { [void][Console]::ReadLine() }
    }
    if ($From -gt 1) { Write-Timing "restart at step $From" }
}
else { Write-Timing "restart at step $From" }

$run = @{ From = $From }
if ($NoPause) { $run.NoPause = $true }
if ($Replay)  { $run.Replay = $true }
& $demo @run

# Hold the closing screen until the last Enter, so the recording or session ends cleanly.
Wait-Enter
Write-Timing 'end'
