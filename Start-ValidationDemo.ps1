<#
.SYNOPSIS
    Backup validation demo for the NIC session (cut from the V3 talk for time): bicep snapshot and
    lint on the same pull request as the Stacks demo, after a refactor that changes nothing.
    Local only. Nothing here talks to Azure. Press Enter whenever it waits.
#>
param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot 'stacks-whatif-demo-debug'
Set-Location $dir

function Wait-Enter { if ($NoPause) { return }; Write-Host ''; Write-Host '  [Enter]' -ForegroundColor DarkGray; [void][Console]::ReadLine() }
function Show-Step([int]$n, [string]$title) {
    try { Clear-Host } catch { }
    $t = "== STEP $n   $title "
    Write-Host ($t + ('=' * [Math]::Max(3, 64 - $t.Length))) -ForegroundColor Cyan
    Write-Host ''
}
function Show-Command([string]$c) { Write-Host "PS> $c" -ForegroundColor Yellow; Write-Host '' }
function Open-InEditor([string[]]$EditorArgs) {
    $cmd = if ($env:EV2_DEMO_CODE_CMD) { $env:EV2_DEMO_CODE_CMD } elseif ($env:TERM_PROGRAM -eq 'vscode' -or $env:EV2_DEMO_FORCE_EDITOR) { 'code' } else { $null }
    if ($cmd -and (Get-Command $cmd -ErrorAction SilentlyContinue)) { & $cmd -r @EditorArgs 2>$null | Out-Null }
}
function Write-Colored([string]$text) {
    foreach ($line in ($text -split "`r?`n")) {
        $l = $line -replace 'resourceId\(subscription\(\)\.subscriptionId, resourceGroup\(\)\.name, ', 'resourceId('
        $color = switch -Regex ($l) { '^\s*\+ ' { 'Green' } '^\s*~ ' { 'Magenta' } '^\s*- ' { 'Red' } 'failed|Expected' { 'Yellow' } default { 'Gray' } }
        Write-Host "  $l" -ForegroundColor $color
    }
}
function Reset-Files {
    Copy-Item main.v1.bicep main.bicep -Force
    Remove-Item main.snapshot.json -ErrorAction SilentlyContinue
}

if (-not (Get-Command bicep -ErrorAction SilentlyContinue)) { Write-Host '  The bicep CLI is missing. Run SETUP-LAPTOP.cmd first.' -ForegroundColor Red; exit 1 }

# VS Code can open this terminal very narrow on a new machine. Wait until it's been dragged wider.
function Get-TermWidth { try { $Host.UI.RawUI.WindowSize.Width } catch { 0 } }
if (-not $NoPause) {
    $w = Get-TermWidth
    if ($w -gt 0 -and $w -lt 60) {
        try { Clear-Host } catch { }
        Write-Host ''
        Write-Host '  This terminal is too narrow.' -ForegroundColor Yellow
        Write-Host '  Drag its left edge to the middle of the screen.' -ForegroundColor Yellow
        Write-Host '  The demo carries on by itself.' -ForegroundColor DarkGray
        while ((Get-TermWidth) -lt 60) { Start-Sleep -Milliseconds 250 }
    }
}
Reset-Files
try { Clear-Host } catch { }
Write-Host ''; Write-Host '  Validation demo: snapshot and lint' -ForegroundColor Cyan
Write-Host '  Same pull request as the Stacks demo, but it all runs on this laptop without Azure.' -ForegroundColor Gray
Wait-Enter

Show-Step 1 'Take a snapshot of the template'
Open-InEditor @('-g', (Join-Path $dir 'main.bicep'))
Show-Command 'bicep snapshot main.bicepparam --mode overwrite'
& bicep snapshot main.bicepparam --mode overwrite 2>&1 | Out-Null
if (Test-Path main.snapshot.json) { Write-Host '  Wrote main.snapshot.json. You check this file in next to your template.' -ForegroundColor Green }
Open-InEditor @('-g', (Join-Path $dir 'main.snapshot.json'))
Wait-Enter

Show-Step 2 'Refactor: move the storage account into a module'
Show-Command 'Copy-Item main.refactor.bicep main.bicep'
Copy-Item main.refactor.bicep main.bicep -Force
Write-Host '  main.bicep now uses modules/storage.bicep for the storage account. Nothing else changed.' -ForegroundColor Gray
Open-InEditor @('--diff', (Join-Path $dir 'main.v1.bicep'), (Join-Path $dir 'main.bicep'))
Wait-Enter

Show-Step 3 'Check the refactor against the snapshot'
Show-Command 'bicep snapshot main.bicepparam --mode validate'
$out = (& bicep snapshot main.bicepparam --mode validate 2>&1 | Out-String).Trim()
$code = $LASTEXITCODE
if ($out) { Write-Colored $out }
if ($code -eq 0) { Write-Host '  It passed, with exit code 0. No resource changed, so the refactor is safe.' -ForegroundColor Green }
Wait-Enter

Show-Step 4 'The pull request'
Show-Command 'Copy-Item main.v2.bicep main.bicep'
Copy-Item main.v2.bicep main.bicep -Force
Write-Host '  main.bicep now has the pull request: the SSH rule, and no virtual network.' -ForegroundColor Gray
Open-InEditor @('--diff', (Join-Path $dir 'main.v1.bicep'), (Join-Path $dir 'main.bicep'))
Wait-Enter

Show-Step 5 'Check the pull request against the snapshot'
Show-Command 'bicep snapshot main.bicepparam --mode validate'
$out = (& bicep snapshot main.bicepparam --mode validate 2>&1 | Out-String).Trim()
Write-Colored $out
Write-Host ''
Write-Host '  "Failed" means the resources are different from the snapshot. That is what you want it to catch.' -ForegroundColor Yellow
Wait-Enter

Show-Step 6 'Lint it'
Show-Command 'bicep lint main.bicep'
$lint = (& bicep lint main.bicep 2>&1 | Out-String).Trim()
if ($lint) { Write-Colored $lint } else { Write-Host '  No lint problems.' -ForegroundColor Green }
Wait-Enter

Show-Step 7 'Make lint fail the build'
Open-InEditor @('-g', (Join-Path $dir 'mistakes.bicep'))
Write-Host '  bicepconfig.json in this folder turns these rules up to errors:' -ForegroundColor Gray
foreach ($rule in ((Get-Content (Join-Path $dir 'bicepconfig.json') -Raw | ConvertFrom-Json).analyzers.core.rules.PSObject.Properties)) {
    Write-Host ("    {0,-26} {1}" -f $rule.Name, $rule.Value.level) -ForegroundColor Gray
}
Write-Host ''
Show-Command 'bicep lint mistakes.bicep'
$out = (& bicep lint mistakes.bicep 2>&1 | Out-String).Trim()
$code = $LASTEXITCODE
foreach ($line in ($out -split "`r?`n")) {
    $l = [regex]::Replace($line, ' \[https://aka\.ms/bicep/linter-diagnostics#[^\]]+\]', '')
    $l = $l.Replace("$dir\", '').Replace(" Please use a parameter value, an expression, or the string 'global'.", '')
    Write-Host "  $l" -ForegroundColor $(if ($l -match ': Error ') { 'Red' } else { 'Gray' })
}
Write-Host ''
Write-Host "  bicep lint returned exit code $code, so a CI build would stop here." -ForegroundColor Yellow
Wait-Enter

Reset-Files
Write-Host ''; Write-Host '  Done. Back to the slides.' -ForegroundColor Cyan
