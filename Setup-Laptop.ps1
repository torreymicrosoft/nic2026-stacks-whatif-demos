<#
    One-time setup for the Stacks What-If demo on a new machine.
    Checks what's needed, asks before installing anything, adds the demo-only Enter shortcut
    to VS Code, signs in to Azure, prepares the stage, then opens VS Code and the script.

        .\Setup-Laptop.ps1           # normal
        .\Setup-Laptop.ps1 -NoOpen   # checks only: no Azure changes, no windows
#>
[CmdletBinding()]
param(
    [switch]$NoOpen,
    [string]$KeybindingsPath = (Join-Path $env:APPDATA 'Code\User\keybindings.json')
)

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$ws   = Join-Path $here 'stacks-whatif-demo'
$ok   = $true

function Say([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }
function Ask([string]$Question) {
    Write-Host "$Question (Y/N) " -ForegroundColor Yellow -NoNewline
    return ((Read-Host) -match '^(y|yes)$')
}
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

Say ''
Say 'Stacks What-If demo setup' Cyan
Say ''

# 0. PowerShell 7 (Az and the demo's background What-Ifs need it).
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @PSBoundParameters
        return
    }
    if (Ask '  PowerShell 7 is missing. Install it with winget now?') {
        winget install -e --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements
        Say '  Done. Close this window and double-click SETUP-LAPTOP.cmd again.' Yellow
    }
    else { Say '  MISS PowerShell 7' Red }
    return
}
Say "  OK   PowerShell $($PSVersionTable.PSVersion)" Green

# 1. Bicep CLI on PATH (Az PowerShell uses it to read .bicep files).
if (Get-Command bicep -ErrorAction SilentlyContinue) { Say '  OK   Bicep CLI' Green }
elseif (Ask '  Bicep CLI is missing. Install it with winget now?') {
    winget install -e --id Microsoft.Bicep --accept-source-agreements --accept-package-agreements
    Update-SessionPath
    if (Get-Command bicep -ErrorAction SilentlyContinue) { Say '  OK   Bicep CLI installed' Green } else { Say '  MISS Bicep CLI. Open a new window and run this again.' Red; $ok = $false }
}
else { Say '  MISS Bicep CLI' Red; $ok = $false }

# 1a. Bicep CLI version. The talk uses 0.48.1. Older ones still deploy the demo, so this only warns.
$bv = $null; if ((((& bicep --version 2>$null) -join ' ')) -match '(\d+\.\d+\.\d+)') { $bv = [version]$Matches[1] }
if ($bv -and $bv -lt [version]'0.48.1') {
    if (Ask "  Bicep CLI is $bv. Update it to the latest with winget now?") {
        winget upgrade -e --id Microsoft.Bicep --accept-source-agreements --accept-package-agreements
        Update-SessionPath
    }
    else { Say "  WARN Bicep CLI $bv (the talk shows 0.48.1)" Yellow }
}

# 1b. Azure CLI 2.88 or later has 'az stack-whatif'. The demo runs PowerShell and only prints the az
#     lines, so this only warns. If you install it here, close every VS Code window and reopen.
$azv = $null
if (Get-Command az -ErrorAction SilentlyContinue) { $azv = [version]((& az version --query '\"azure-cli\"' -o tsv 2>$null) | Select-Object -First 1) }
if ($azv -and $azv -ge [version]'2.88.0') { Say "  OK   Azure CLI $azv" Green }
elseif (Ask "  Azure CLI is $(if ($azv) { $azv } else { 'missing' }). 2.88 or later has 'az stack-whatif'. Install or update it with winget now?") {
    winget install -e --id Microsoft.AzureCLI --accept-source-agreements --accept-package-agreements
    Update-SessionPath
    Say '  Done. Close every VS Code window and reopen so its terminals find the new az.' Yellow
}
else { Say "  WARN Azure CLI $(if ($azv) { $azv } else { 'missing' }) (az stack-whatif needs 2.88+)" Yellow }

# 2. Az.Resources 10.2.1 or later (has the Stacks What-If cmdlets).
$mod = Get-Module Az.Resources -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if ($mod -and $mod.Version -ge [version]'10.2.1') { Say "  OK   Az.Resources $($mod.Version)" Green }
elseif (Ask '  Az.Resources 10.2.1 (Stacks What-If cmdlets) is missing. Install it now?') {
    Install-Module Az.Resources -RequiredVersion 10.2.1 -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
    $mod = Get-Module Az.Resources -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($mod -and $mod.Version -ge [version]'10.2.1') { Say "  OK   Az.Resources $($mod.Version) installed" Green } else { Say '  MISS Az.Resources' Red; $ok = $false }
}
else { Say '  MISS Az.Resources 10.2.1' Red; $ok = $false }

# 3. VS Code, and the Bicep extension (the AI demo needs it for the Bicep MCP server).
$code = Get-Command code -ErrorAction SilentlyContinue
if ($code) { Say '  OK   VS Code' Green }
elseif (Ask '  VS Code is missing. Install it with winget now?') {
    winget install -e --id Microsoft.VisualStudioCode --accept-source-agreements --accept-package-agreements
    Update-SessionPath
    $code = Get-Command code -ErrorAction SilentlyContinue
    if ($code) { Say '  OK   VS Code installed' Green } else { Say '  MISS VS Code. Open a new window and run this again.' Red; $ok = $false }
}
else { Say '  MISS VS Code' Red; $ok = $false }

function Test-BicepExtension {
    $dirs = @((Join-Path $env:USERPROFILE '.vscode\extensions'), (Join-Path $env:USERPROFILE '.vscode-insiders\extensions'))
    if ($env:VSCODE_EXTENSIONS) { $dirs += $env:VSCODE_EXTENSIONS }
    foreach ($d in $dirs) {
        if (Get-ChildItem -Path $d -Directory -Filter 'ms-azuretools.vscode-bicep-*' -ErrorAction SilentlyContinue) { return $true }
    }
    if ($code -and ((& code --list-extensions 2>$null) -match 'ms-azuretools\.vscode-bicep')) { return $true }
    return $false
}
if ($code) {
    if (Test-BicepExtension) { Say '  OK   Bicep extension' Green }
    elseif (Ask '  Could not find the Bicep extension for VS Code. Install it now?') {
        & code --install-extension ms-azuretools.vscode-bicep
        if (Test-BicepExtension) { Say '  OK   Bicep extension installed' Green } else { Say '  NOTE Could not confirm the Bicep extension. The Stacks demo still works, but the AI demo needs it.' Yellow }
    }
    else { Say '  NOTE Skipped the Bicep extension. The Stacks demo still works, but the AI demo needs it.' Yellow }
}

# 3b. ZoomIt (optional). Ctrl+1 zooms in where the mouse is, which helps people at the back read the
#     terminal and the portal. It uses Ctrl+1 to Ctrl+4, so click the Edge tabs instead of Ctrl+1/2/3.
function Find-ZoomIt {
    $c = Get-Command ZoomIt64.exe, ZoomIt.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($p in @("$env:LOCALAPPDATA\Microsoft\WinGet\Links\ZoomIt64.exe", "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ZoomIt.exe")) { if (Test-Path $p) { return $p } }
    $pkg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Directory -Filter 'Microsoft.Sysinternals.ZoomIt*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) { $exe = Get-ChildItem $pkg.FullName -Recurse -Filter 'ZoomIt64.exe' -ErrorAction SilentlyContinue | Select-Object -First 1; if ($exe) { return $exe.FullName } }
    return $null
}
$zoomIt = Find-ZoomIt
if ($zoomIt) { Say '  OK   ZoomIt' Green }
elseif (Ask '  ZoomIt is not installed. It zooms in where your mouse is during the demo (optional). Install it with winget now?') {
    winget install -e --id Microsoft.Sysinternals.ZoomIt --accept-source-agreements --accept-package-agreements
    $zoomIt = Find-ZoomIt
    if ($zoomIt) { Say '  OK   ZoomIt installed' Green } else { Say '  NOTE Could not find ZoomIt after installing. Open a new window and run this again.' Yellow }
}
else { Say '  NOTE Skipped ZoomIt. Ctrl+= in VS Code and Edge still zooms in.' Yellow }
# The AI demo folder sits next to this script.
$aiFolder = Join-Path $here 'ai-demo'
if ((Test-Path (Join-Path $aiFolder '.github\skills\migrate-resources-to-stack\SKILL.md')) -and (Test-Path (Join-Path $aiFolder 'whatif.ps1'))) { Say '  OK   AI demo folder' Green }
else { Say '  NOTE AI demo folder not found next to this script.' Yellow }

# 4. Demo-only Enter shortcut, merged into any existing VS Code keybindings.
$entry = @'
    // Stacks What-If demo: Enter in a file under stacks-whatif-demo advances the demo.
    // Delete this entry when you're done with the demo. It has no effect anywhere else.
    {
        "key": "enter",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u000D" },
        "when": "editorTextFocus && resourcePath =~ /stacks-whatif-demo/i"
    }
'@
try {
    $kb = if (Test-Path $KeybindingsPath) { Get-Content $KeybindingsPath -Raw } else { '' }
    if ($kb -match 'stacks-whatif-demo') { Say '  OK   Enter shortcut (already there)' Green }
    else {
        if ($kb.Trim() -eq '') {
            $new = "// Place your key bindings in this file to override the defaults`r`n[`r`n$entry`r`n]`r`n"
        }
        else {
            Copy-Item $KeybindingsPath "$KeybindingsPath.bak-stacksdemo" -Force
            $m = [regex]::Match($kb, '(?m)^\s*\[')
            if (-not $m.Success) { throw 'could not find the start of the keybindings list' }
            $open = $m.Index + $m.Length
            $rest = $kb.Substring($open)
            $body = [regex]::Replace($rest, '(?s)/\*.*?\*/|//[^\r\n]*', '')
            $sep  = if ($body.TrimStart().StartsWith(']')) { '' } else { ',' }
            $new  = $kb.Substring(0, $open) + "`r`n" + $entry + $sep + $rest
        }
        $dir = Split-Path $KeybindingsPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [System.IO.File]::WriteAllText($KeybindingsPath, $new)
        Say '  OK   Enter shortcut added to VS Code' Green
    }
}
catch { Say "  NOTE Enter shortcut not added ($($_.Exception.Message)). Click the terminal before each Enter instead." Yellow }

if (-not $ok) { Say ''; Say 'Not ready yet. Fix the red items above, then run this again.' Red; return }

# 5. Sign in and put Azure at the starting point.
if (-not $NoOpen) {
    Say ''
    & (Join-Path $here 'Prepare-Stage.ps1')
    if (-not $?) { Say 'Azure prep did not finish. The demo can still run with saved results (-Replay).' Yellow }
}

# 6. Full check.
Say ''
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'demo.ps1') -Preflight
$live = ($LASTEXITCODE -eq 0)

# 7. Open everything: the talking points, the portal, the AI demo window, and the main demo last so it's in front.
#    The validation demo is a backup now, so it doesn't open. OPEN-VALIDATION-DEMO.cmd opens it if you need it.
if (-not $NoOpen) {
    Start-Process notepad.exe -ArgumentList "`"$(Join-Path $here 'TELEPROMPTER.md')`""
    & (Join-Path $here 'Open-Portal.ps1')
    Start-Sleep -Seconds 2
    & cmd.exe /c "`"$(Join-Path $here 'OPEN-AI-DEMO.cmd')`""
    Start-Sleep -Seconds 3
    & code -n "$ws" 2>$null
    # ZoomIt runs in the tray. Start it now so Ctrl+1 works on stage.
    if ($zoomIt -and -not (Get-Process ZoomIt64, ZoomIt -ErrorAction SilentlyContinue)) { Start-Process $zoomIt }
}

Say ''
Say 'All set.' Green
Say '  1. VS Code opens two windows: Stacks What-If demo and AI demo. If one asks'
Say '     whether you trust the authors, click "Yes, I trust the authors".'
Say '  2. In Edge, sign in to the portal if it asks. Leave the three tabs open, and zoom the portal to 175% (Ctrl+plus).'
Say '  3. The AI demo window opens with the saved Copilot chat and the skill. If the chat shows raw text, press Ctrl+Shift+V.'
Say '  4. In the Stacks What-If demo window, press Ctrl + ` (the key under Esc) to start the demo.'
if (-not $live) { Say '  Azure is not ready, so the demo will use saved results. That is fine for rehearsing.' Yellow }
Say '  5. Then follow START-HERE.md.'
