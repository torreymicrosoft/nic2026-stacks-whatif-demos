<#
    Paced demo runner: Deployment Stacks + What-If (NIC 2026), V3.

    Every step shows the whole command first. Press Enter to run it against Azure, and Enter
    again for the next step. The commands are the real ones. This script only runs them in order
    and trims the long IDs out of the output so it fits on the screen.

    Step 10 really deploys app.v2.bicep to the stack. Run SETUP-LAPTOP.cmd (or Prepare-Stage.ps1)
    after every practice run to put the stack back.

        .\demo.ps1               # live against Azure
        .\demo.ps1 -Replay       # no network: shows saved results from the last good live run
        .\demo.ps1 -From 6       # restart at step 6
        .\demo.ps1 -Preflight    # check everything, exit 0 when ready
        .\demo.ps1 -NoPause      # unattended pass (testing)

    While a command runs, click the terminal and press S to show the saved result from the last
    good run instead. It also does that by itself if a What-If takes longer than 90 seconds (30 for the quick steps).
#>
[CmdletBinding()]
param(
    [switch]$Preflight,
    [switch]$NoPause,
    [switch]$Replay,
    [int]$From = 1
)

# Clear the screen, but never fail when there is no real console (e.g. automated tests).
function Reset-Screen { try { Clear-Host } catch { } }

$ErrorActionPreference = 'Stop'
if (Get-Variable PSStyle -ErrorAction SilentlyContinue) { $PSStyle.OutputRendering = 'Ansi' }

$ws  = Join-Path $PSScriptRoot 'stacks-whatif-demo'
$v1  = Join-Path $ws 'app.v1.bicep'
$v2  = Join-Path $ws 'app.v2.bicep'
$rp  = Join-Path $PSScriptRoot '_replay'
$cfgFile = Join-Path $PSScriptRoot 'demo.config.json'
$script:Cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
$script:Esc = [char]27
$RG    = $script:Cfg.resourceGroup
$STACK = $script:Cfg.stackName
$DENY  = $script:Cfg.denySettingsMode
$script:StackId = "/subscriptions/$($script:Cfg.subscriptionId)/resourceGroups/$RG/providers/Microsoft.Resources/deploymentStacks/$STACK"
$script:Pwsh = (Get-Process -Id $PID).Path
$script:WhatIfTimeout = 90
$script:DeployTimeout = 240

$script:TimingLog = Join-Path $env:TEMP 'stacks-demo-timing.txt'
function Write-Timing([string]$Label) {
    try { Add-Content -Path $script:TimingLog -Value ('{0}|{1}' -f (Get-Date).ToString('o'), $Label) -Encoding ASCII } catch { }
}

# Keep lines inside the window so they never wrap when the text is zoomed in.
function Get-RuleWidth {
    try { $w = $Host.UI.RawUI.WindowSize.Width } catch { $w = 0 }
    if ($w -lt 20) { return 70 }
    return [Math]::Min(70, $w - 1)
}

function Banner([int]$N, [string]$Title) {
    $t = "== STEP $N   $Title "
    Write-Host ($t + ('=' * [Math]::Max(3, (Get-RuleWidth) - $t.Length))) -ForegroundColor Cyan
    Write-Host ''
}

# Wait for a fresh Enter. Keys pressed early are thrown away, so nothing gets skipped.
function Wait-Enter([string]$Label = 'next', [switch]$Inline) {
    if ($NoPause) { Start-Sleep -Milliseconds 300; return }
    if ($Inline) { Write-Host "  [Enter] $Label" -ForegroundColor DarkGray -NoNewline }
    else { Write-Host ''; Write-Host "  [Enter] $Label" -ForegroundColor DarkGray }
    try {
        while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
        do { $k = [Console]::ReadKey($true) } until ($k.Key -eq [ConsoleKey]::Enter)
    }
    catch { [void][System.Console]::ReadLine() }
    if ($Inline) { Write-Host -NoNewline ("`r" + (' ' * 30) + "`r") }
}

# ---------------------------------------------------------------- VS Code
# Show files in VS Code when running in VS Code's terminal; otherwise print them here.
$script:CodeCmd   = if ($env:EV2_DEMO_CODE_CMD) { $env:EV2_DEMO_CODE_CMD } else { 'code' }
$script:UseEditor = (($env:TERM_PROGRAM -eq 'vscode') -or ($env:EV2_DEMO_FORCE_EDITOR -eq '1')) -and
                    [bool](Get-Command $script:CodeCmd -ErrorAction SilentlyContinue)

function Invoke-Code([string[]]$CodeArgs) {
    $ErrorActionPreference = 'Continue'
    try { $null = & $script:CodeCmd @CodeArgs 2>&1 } catch { }
}

function Open-InEditor([string]$Path, [string]$Find) {
    if (-not $script:UseEditor) { return }
    $line = 1
    if ($Find) {
        $m = Select-String -Path $Path -SimpleMatch -Pattern $Find | Select-Object -First 1
        if ($m) { $line = $m.LineNumber }
    }
    Invoke-Code @('-r', '-g', ('{0}:{1}' -f $Path, $line))
}

function Open-Diff([string]$Left, [string]$Right) {
    if ($script:UseEditor) { Invoke-Code @('-r', '--diff', $Left, $Right); return }
    Compare-Object (Get-Content $Left) (Get-Content $Right) | ForEach-Object {
        $c = if ($_.SideIndicator -eq '=>') { 'Green' } else { 'Red' }
        $s = if ($_.SideIndicator -eq '=>') { '+ ' } else { '- ' }
        Write-Host ("  " + $s + $_.InputObject) -ForegroundColor $c
    }
}

# ---------------------------------------------------------------- formatting
function Remove-Ansi([string]$s) { [regex]::Replace($s, "$($script:Esc)\[[0-9;]*m", '') }
function Color([string]$Text, [string]$Code) { "$($script:Esc)[${Code}m$Text$($script:Esc)[0m" }

function Format-Wrapped([string]$Text, [int]$Width = 66) {
    $out = @(); $line = ''
    foreach ($w in ($Text -split ' ')) {
        if (("$line $w").Trim().Length -gt $Width) { $out += '  ' + $line.Trim(); $line = $w } else { $line = "$line $w" }
    }
    if ($line.Trim()) { $out += '  ' + $line.Trim() }
    $out -join "`n"
}

# The real cmdlet output, with the long IDs, the symbol legend (it's on the slide) and the
# bookkeeping lines taken out so it fits on the screen.
function Format-AzText([string]$Text) {
    $sub = $script:Cfg.subscriptionId
    $prefix = "/subscriptions/$sub/resourceGroups/$RG/providers/"
    $scope  = "/subscriptions/$sub/resourceGroups/$RG"
    $skip = '^\s*(Resource Id|Stack Resource Id|Correlation Id|Creation Time|Expiration Time|Provisioning State|Name|What if)\s*:\s*'
    $out = New-Object System.Collections.Generic.List[string]
    $blank = 0; $legend = $false
    foreach ($l in ($Text -split "\r?\n")) {
        $p = (Remove-Ansi $l) -replace "`r", ''
        if ($legend) {
            if ($p -match '^\s+[-+~=x*v!] [A-Z]') { continue }
            $legend = $false
        }
        if ($p -match '^Resource and property changes are indicated with these symbols') { $legend = $true; continue }
        if ($p -cmatch ($skip + '$') -or $p -cmatch '^\s*(Resource Id|Stack Resource Id|Correlation Id|Creation Time|Expiration Time|Provisioning State)\s*:') { continue }
        if ($p -match 'You can help us improve the accuracy|Getting the latest status of all resources|^The deployment will update the following scope') { continue }
        if (-not $p.Trim()) { $blank++; if ($blank -gt 1) { continue } } else { $blank = 0 }
        $out.Add(($l -replace "`r", '').Replace($prefix, '').Replace($scope, "resourceGroups/$RG"))
    }
    (($out -join "`n").Trim("`r", "`n"))
}

# Get-AzResourceGroupDeploymentStack output, minus the IDs and the two cleanup settings that
# only matter for subscription and management group stacks. Resource lists go one per line.
function Format-StackText([string]$Text) {
    $prefix = "/subscriptions/$($script:Cfg.subscriptionId)/resourceGroups/$RG/providers/"
    $drop = '^(Id|CorrelationId|DeploymentId|CreationTime\(UTC\)|resourceGroupsCleanupAction|managementGroupsCleanupAction|Duration|Description|Error)$'
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($l in ((Remove-Ansi $Text) -split "\r?\n")) {
        if ($l -match '^(\S[^:]*?)\s*:\s?(.*)$') {
            $entries.Add([pscustomobject]@{ Label = $Matches[1].Trim(); Values = [System.Collections.Generic.List[string]]::new() })
            if ($Matches[2].Trim()) { $entries[$entries.Count - 1].Values.Add($Matches[2].Trim()) }
        }
        elseif ($l.Trim() -and $entries.Count) { $entries[$entries.Count - 1].Values.Add($l.Trim()) }
    }
    $keep = @($entries | Where-Object { $_.Label -notmatch $drop })
    if (-not $keep) { return (Remove-Ansi $Text).Trim() }
    $w = ($keep | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
    $out = foreach ($e in $keep) {
        $vals = @($e.Values | ForEach-Object { $_.Replace($prefix, '') })
        if ($e.Label -match 'Resources$') {
            $e.Label.PadRight($w) + ' :'
            foreach ($v in $vals) { '    ' + $v }
        }
        else { $e.Label.PadRight($w) + ' : ' + ($vals -join ' ') }
    }
    '  ' + (($out -join "`n") -replace "`n", "`n  ")
}

function Format-DenyMessage([string]$Message) {
    $m = ($Message -split "`r?`n")[0]
    $m = [regex]::Replace($m, " with object id '[^']+'", '')
    $m = [regex]::Replace($m, "'/subscriptions/[^']*/([^/']+)'", "'`$1'")
    $m = [regex]::Replace($m, "the deny assignment with name 'Deny assignment '[^']+' created by Deployment Stack '([^']+)'\.'", "the deny assignment created by Deployment Stack '`$1'")
    $m = [regex]::Replace($m, " and Id '[^']+' at scope '[^']+'", '')
    return $m
}

# PowerShell first (what runs here), then the same thing in the Azure CLI.
function Show-Command([string[]]$Ps, [string]$Az) {
    foreach ($l in $Ps) {
        if ($l -match '^\s') { Write-Host ('    ' + $l) -ForegroundColor Yellow }
        else { Write-Host ('PS> ' + $l) -ForegroundColor Yellow }
    }
    Write-Host ''
    Write-Host (Format-Wrapped ('Azure CLI:  ' + $Az) ((Get-RuleWidth) - 4)) -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------- running a step live
# Runs one command in the background with a timer on screen. Returns the text to show.
# The live result is saved for -Replay. If Azure fails or is too slow (or you press S), it
# shows the result from the last good run instead, and says so.
function Invoke-Live([string]$Key, [scriptblock]$StartJob, [scriptblock]$Render, [int]$Timeout) {
    $file = Join-Path $rp "$Key.txt"
    if ($Replay) {
        if (Test-Path $file) { return @{ Text = (Get-Content $file -Raw); Note = $null; Seconds = $null } }
        return @{ Text = $null; Note = "No saved result for $Key."; Seconds = $null }
    }
    $note = $null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $job = & $StartJob
        $canKeys = -not $NoPause
        while ($job.State -in 'NotStarted', 'Running') {
            $s = [int]$sw.Elapsed.TotalSeconds
            Write-Host -NoNewline ("`r  Running in Azure... {0}s   " -f $s) -ForegroundColor DarkGray
            if ($s -ge $Timeout) { $note = 'Azure is taking longer than usual'; break }
            if ($canKeys) {
                try {
                    if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq [ConsoleKey]::S) { $note = 'Switched to the saved result'; break }
                }
                catch { $canKeys = $false }
            }
            Start-Sleep -Milliseconds 200
        }
        Write-Host -NoNewline ("`r" + (' ' * 40) + "`r")
        # A delete test that's still waiting must not go through later, after step 10 detaches the network.
        if ($note -and $job.Name -eq 'deny-test') { try { $null = $job.StopJobAsync() } catch { } }
        if (-not $note) {
            if ($job.State -ne 'Completed') {
                $reason = $job.ChildJobs[0].JobStateInfo.Reason
                throw $(if ($reason) { $reason.Message } else { "it ended in state $($job.State)" })
            }
            $text = & $Render ((Receive-Job $job 6>$null) -join "`n")
            if ($text) { Set-Content -Path $file -Value $text -Encoding utf8 -NoNewline }
            return @{ Text = $text; Note = $null; Seconds = [int]$sw.Elapsed.TotalSeconds }
        }
    }
    catch {
        Write-Host -NoNewline ("`r" + (' ' * 40) + "`r")
        $note = 'The live call failed (' + (($_.Exception.Message -split "`r?`n")[0]) + ')'
    }
    $saved = if (Test-Path $file) { Get-Content $file -Raw } else { $null }
    return @{ Text = $saved; Note = "$note, so this is the result from my last run."; Seconds = $null }
}

# One step: the command, Enter to run it, then the result on a clean screen.
function Invoke-Step([int]$N, [string]$Title, [string[]]$Ps, [string]$Az, [string]$Recap, [string]$Key,
                     [scriptblock]$StartJob, [scriptblock]$Render, [int]$Timeout = $script:WhatIfTimeout) {
    Reset-Screen
    Write-Timing "step $N"
    Banner $N $Title
    Show-Command $Ps $Az
    Wait-Enter 'run it' -Inline
    Write-Timing "run $N"
    $r = Invoke-Live $Key $StartJob $Render $Timeout
    Write-Timing "result $N"
    Reset-Screen
    Banner $N $Title
    $took = if ($r.Seconds) { "   ($($r.Seconds)s)" } else { '' }
    Write-Host ("PS> $Recap$took") -ForegroundColor DarkGray
    Write-Host ''
    if ($r.Note) { Write-Host (Format-Wrapped "($($r.Note))" ((Get-RuleWidth) - 4)) -ForegroundColor DarkGray; Write-Host '' }
    if ($r.Text) { Write-Host $r.Text }
    Wait-Enter 'next'
}

# ---------------------------------------------------------------- the background jobs
# -WhatIf prints its result straight to the console, so it runs in its own PowerShell and
# this keeps what it printed.
function Start-RegularWhatIf([string]$Template) {
    Start-ThreadJob -ArgumentList $script:Pwsh, $script:Cfg.subscriptionId, $RG, $Template -ScriptBlock {
        param($pwsh, $sub, $rg, $tf)
        $cmd = "`$PSStyle.OutputRendering = 'Ansi'; Import-Module Az.Resources -WarningAction SilentlyContinue; " +
               "`$null = Set-AzContext -Subscription '$sub' -WarningAction SilentlyContinue; " +
               "New-AzResourceGroupDeployment -ResourceGroupName '$rg' -TemplateFile '$tf' -WhatIf -WarningAction SilentlyContinue"
        $out = & $pwsh -NoProfile -NonInteractive -Command $cmd 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $out -notmatch 'Resource changes:') { throw $out.Trim() }
        $out
    }
}

function Start-StacksWhatIf([string]$Name, [string]$Template, [string]$Aou) {
    Start-ThreadJob -ArgumentList $script:Cfg, $script:StackId, $Name, $Template, $Aou -ScriptBlock {
        param($cfg, $stackId, $name, $tf, $aou)
        if (Get-Variable PSStyle -ErrorAction SilentlyContinue) { $PSStyle.OutputRendering = 'Ansi' }
        Import-Module Az.Resources -MinimumVersion 10.2.1 -WarningAction SilentlyContinue
        $r = New-AzResourceGroupDeploymentStackWhatIfResult -Name $name -ResourceGroupName $cfg.resourceGroup `
            -StackResourceId $stackId -TemplateFile $tf -ActionOnUnmanage $aou -DenySettingsMode $cfg.denySettingsMode `
            -RetentionInterval PT1H -Force -WarningAction SilentlyContinue -ErrorAction Stop
        $r | Out-String -Width 4096
    }
}

function Start-Quick([scriptblock]$Body, [string]$Name = 'quick') {
    Start-ThreadJob -Name $Name -ArgumentList $script:Cfg, $Body.ToString() -ScriptBlock {
        param($cfg, $body)
        if (Get-Variable PSStyle -ErrorAction SilentlyContinue) { $PSStyle.OutputRendering = 'Ansi' }
        Import-Module Az.Resources -MinimumVersion 10.2.1 -WarningAction SilentlyContinue
        & ([scriptblock]::Create($body)) $cfg
    }
}

# ---------------------------------------------------------------- preflight
if ($Preflight) {
    Write-Host 'Preflight' -ForegroundColor Cyan
    $ok = $true
    foreach ($p in @($v1, $v2, $cfgFile)) {
        if (Test-Path $p) { Write-Host "  OK   $(Split-Path $p -Leaf)" -ForegroundColor Green } else { Write-Host "  MISS $p" -ForegroundColor Red; $ok = $false }
    }
    if ($Replay) {
        $need = '01-stack', '02-deny', '03-regular-v1', '04-stacks-v1', '06-regular-v2', '07-stacks-v2-detach', '08-stacks-v2-delete', '09-results', '10-deploy'
        $missing = @($need | Where-Object { -not (Test-Path (Join-Path $rp "$_.txt")) })
        if (-not $missing) { Write-Host "  OK   $($need.Count) saved results for replay" -ForegroundColor Green }
        else { Write-Host "  MISS saved results: $($missing -join ', '). Run a live pass first." -ForegroundColor Red; $ok = $false }
    }
    else {
        if ($PSVersionTable.PSVersion.Major -ge 7) { Write-Host "  OK   PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green }
        else { Write-Host "  MISS PowerShell 7 (this is $($PSVersionTable.PSVersion))" -ForegroundColor Red; $ok = $false }
        $mod = Get-Module Az.Resources -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if ($mod -and $mod.Version -ge [version]'10.2.1') { Write-Host "  OK   Az.Resources $($mod.Version)" -ForegroundColor Green }
        else { Write-Host '  MISS Az.Resources 10.2.1 or later' -ForegroundColor Red; $ok = $false }
        if ($ok) {
            try {
                Import-Module Az.Resources -MinimumVersion 10.2.1 -WarningAction SilentlyContinue
                $ctx = Set-AzContext -Subscription $script:Cfg.subscriptionId -WarningAction SilentlyContinue
                Write-Host "  OK   signed in: $($ctx.Account.Id) | $($ctx.Subscription.Name)" -ForegroundColor Green
                $s = Get-AzResourceGroupDeploymentStack -ResourceGroupName $RG -Name $STACK -WarningAction SilentlyContinue
                $names = @($s.Resources | ForEach-Object { ($_.Id -split '/')[-1] })
                $nsg = Get-AzResource -ResourceGroupName $RG -Name 'nsg-app' -ResourceType 'Microsoft.Network/networkSecurityGroups' -ExpandProperties -ErrorAction SilentlyContinue
                $rules = @($nsg.Properties.securityRules | ForEach-Object { $_.name })
                if ($s.ProvisioningState -eq 'succeeded' -and $names.Count -eq 3 -and ($names -contains 'vnet-app') -and ($names -contains 'nsg-app') -and
                    "$($s.ResourcesCleanupAction)" -eq 'detach' -and -not ($rules -contains 'allow-ssh')) {
                    Write-Host "  OK   stack '$($s.Name)' is at the starting point (3 resources, detach, $($s.DenySettings.Mode), no SSH rule)" -ForegroundColor Green
                }
                else { Write-Host "  MISS stack is not at the starting point. Run .\Prepare-Stage.ps1" -ForegroundColor Red; $ok = $false }
            }
            catch { Write-Host "  MISS Azure: $(($_.Exception.Message -split "`r?`n")[0])" -ForegroundColor Red; $ok = $false }
        }
    }
    Write-Host ''
    if ($ok) { Write-Host 'Ready.' -ForegroundColor Green; exit 0 }
    Write-Host 'Not ready. Fix the above, or use -Replay.' -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- start
if (-not $Replay) {
    Import-Module Az.Resources -MinimumVersion 10.2.1 -WarningAction SilentlyContinue
    $null = Set-AzContext -Subscription $script:Cfg.subscriptionId -WarningAction SilentlyContinue
}

$psRg = "    -ResourceGroupName $RG ``"

if ($From -le 1) {
    Open-InEditor $v1 'resource vnet'
    Invoke-Step 1 'The stack' `
        -Ps @('$stack = Get-AzResourceGroupDeploymentStack `', $psRg, "    -Name $STACK", '$stack') `
        -Az "az stack group show --resource-group $RG --name $STACK" `
        -Recap "Get-AzResourceGroupDeploymentStack -Name $STACK" -Key '01-stack' -Timeout 30 `
        -StartJob { Start-Quick { param($cfg) Get-AzResourceGroupDeploymentStack -ResourceGroupName $cfg.resourceGroup -Name $cfg.stackName -WarningAction SilentlyContinue | Out-String -Width 4096 } } `
        -Render { param($t) Format-StackText $t }
}

if ($From -le 2) {
    Invoke-Step 2 'Deny settings' `
        -Ps @('Remove-AzResource `', $psRg, '    -ResourceName vnet-app `', '    -ResourceType Microsoft.Network/virtualNetworks `', '    -Force') `
        -Az "az network vnet delete --resource-group $RG --name vnet-app" `
        -Recap 'Remove-AzResource -ResourceName vnet-app' -Key '02-deny' -Timeout 30 `
        -StartJob { Start-Quick -Name 'deny-test' -Body {
            param($cfg)
            $s = Get-AzResourceGroupDeploymentStack -ResourceGroupName $cfg.resourceGroup -Name $cfg.stackName -WarningAction SilentlyContinue
            # Safety: only try the delete when the stack manages vnet-app and its deny settings will block it.
            # After step 10 the network is detached, so without a reset this delete would really happen.
            $managed = @($s.Resources | Where-Object { $_.Id -match '/virtualNetworks/vnet-app$' })
            if ("$($s.DenySettings.Mode)" -notmatch 'deny' -or -not $managed) { return 'SKIPPED' }
            try {
                Remove-AzResource -ResourceGroupName $cfg.resourceGroup -ResourceName 'vnet-app' -ResourceType 'Microsoft.Network/virtualNetworks' -Force -ErrorAction Stop | Out-Null
                'DELETED'
            }
            catch { 'DENIED ' + $_.Exception.Message }
        } } `
        -Render { param($t)
            if ($t -match '^SKIPPED') { return (Color (Format-Wrapped "Skipped: the stack isn't protecting vnet-app right now, so this delete would really happen. Run SETUP-LAPTOP.cmd to reset the demo." ((Get-RuleWidth) - 4)) '33') }
            if ($t -match '^DELETED') { return (Color '  The delete went through.' '33') }
            Color (Format-Wrapped (Format-DenyMessage ($t -replace '^DENIED ', '')) ((Get-RuleWidth) - 4)) '31'
        }
}

$psStackWhatIf = {
    param([string]$Name, [string]$File, [string]$Aou)
    @('New-AzResourceGroupDeploymentStackWhatIfResult `', "    -Name $Name ``", $psRg, '    -StackResourceId $stack.Id `',
      "    -TemplateFile $File ``", "    -ActionOnUnmanage $Aou ``", "    -DenySettingsMode $DENY ``", '    -RetentionInterval PT1H `', '    -Force')
}
$azStackWhatIf = {
    param([string]$Name, [string]$File, [string]$Aou)
    $aouCli = if ($Aou -eq 'DetachAll') { 'detachAll' } else { 'deleteResources' }
    "az stack-whatif group create --name $Name --resource-group $RG --stack-id <stack-app ID> --template-file $File --action-on-unmanage $aouCli --deny-settings-mode denyDelete --retention-interval PT1H"
}

if ($From -le 3) {
    Invoke-Step 3 'Regular What-If, nothing changed' `
        -Ps @('New-AzResourceGroupDeployment `', $psRg, '    -TemplateFile app.v1.bicep `', '    -WhatIf') `
        -Az "az deployment group what-if --resource-group $RG --template-file app.v1.bicep" `
        -Recap 'New-AzResourceGroupDeployment -TemplateFile app.v1.bicep -WhatIf' -Key '03-regular-v1' `
        -StartJob { Start-RegularWhatIf $v1 } -Render { param($t) Format-AzText $t }
}

if ($From -le 4) {
    Invoke-Step 4 'Stacks What-If, nothing changed' `
        -Ps (& $psStackWhatIf 'whatif-main' 'app.v1.bicep' 'DetachAll') `
        -Az (& $azStackWhatIf 'whatif-main' 'app.v1.bicep' 'DetachAll') `
        -Recap 'New-AzResourceGroupDeploymentStackWhatIfResult -Name whatif-main -TemplateFile app.v1.bicep' -Key '04-stacks-v1' `
        -StartJob { Start-StacksWhatIf 'whatif-main' $v1 'DetachAll' } -Render { param($t) Format-AzText $t }
}

if ($From -le 5) {
    Reset-Screen
    Write-Timing 'step 5'
    Banner 5 'The pull request'
    Open-Diff $v1 $v2
    Write-Host "  app.v1.bicep is what's deployed now." -ForegroundColor Gray
    Write-Host '  app.v2.bicep is the pull request. Two changes:' -ForegroundColor Gray
    Write-Host ''
    Write-Host (Color '  + a rule that opens SSH (port 22) to the internet' '32')
    Write-Host (Color '  - the virtual network is gone from the template' '31')
    if (-not $script:UseEditor) { Write-Host '' }
    Wait-Enter 'next'
}

if ($From -le 6) {
    Invoke-Step 6 'Regular What-If on the pull request' `
        -Ps @('New-AzResourceGroupDeployment `', $psRg, '    -TemplateFile app.v2.bicep `', '    -WhatIf') `
        -Az "az deployment group what-if --resource-group $RG --template-file app.v2.bicep" `
        -Recap 'New-AzResourceGroupDeployment -TemplateFile app.v2.bicep -WhatIf' -Key '06-regular-v2' `
        -StartJob { Start-RegularWhatIf $v2 } -Render { param($t) Format-AzText $t }
}

if ($From -le 7) {
    Invoke-Step 7 'Stacks What-If on the pull request' `
        -Ps (& $psStackWhatIf 'pr-142' 'app.v2.bicep' 'DetachAll') `
        -Az (& $azStackWhatIf 'pr-142' 'app.v2.bicep' 'DetachAll') `
        -Recap 'New-AzResourceGroupDeploymentStackWhatIfResult -Name pr-142 -ActionOnUnmanage DetachAll' -Key '07-stacks-v2-detach' `
        -StartJob { Start-StacksWhatIf 'pr-142' $v2 'DetachAll' } -Render { param($t) Format-AzText $t }
}

if ($From -le 8) {
    Invoke-Step 8 'Delete instead of detach' `
        -Ps (& $psStackWhatIf 'pr-142-delete' 'app.v2.bicep' 'DeleteResources') `
        -Az (& $azStackWhatIf 'pr-142-delete' 'app.v2.bicep' 'DeleteResources') `
        -Recap 'New-AzResourceGroupDeploymentStackWhatIfResult -Name pr-142-delete -ActionOnUnmanage DeleteResources' -Key '08-stacks-v2-delete' `
        -StartJob { Start-StacksWhatIf 'pr-142-delete' $v2 'DeleteResources' } -Render { param($t) Format-AzText $t }
}

if ($From -le 9) {
    Invoke-Step 9 'The result is a resource' `
        -Ps @('Get-AzResourceGroupDeploymentStackWhatIfResult `', "    -ResourceGroupName $RG |", '    Format-Table Name, Type') `
        -Az "az stack-whatif group list --resource-group $RG --output table" `
        -Recap 'Get-AzResourceGroupDeploymentStackWhatIfResult' -Key '09-results' -Timeout 30 `
        -StartJob { Start-Quick { param($cfg) Get-AzResourceGroupDeploymentStackWhatIfResult -ResourceGroupName $cfg.resourceGroup | Sort-Object Name | Format-Table Name, Type | Out-String -Width 4096 } } `
        -Render { param($t) Format-AzText $t }
}

if ($From -le 10) {
    Invoke-Step 10 'Deploy it and check' `
        -Ps @('Set-AzResourceGroupDeploymentStack `', "    -Name $STACK ``", $psRg, '    -TemplateFile app.v2.bicep `', '    -ActionOnUnmanage DetachAll `', "    -DenySettingsMode $DENY ``", '    -Force') `
        -Az "az stack group create --name $STACK --resource-group $RG --template-file app.v2.bicep --action-on-unmanage detachAll --deny-settings-mode denyDelete --yes" `
        -Recap 'Set-AzResourceGroupDeploymentStack -TemplateFile app.v2.bicep -ActionOnUnmanage DetachAll' -Key '10-deploy' -Timeout $script:DeployTimeout `
        -StartJob {
            # Never detach the network while the delete test from step 2 might still go through.
            $pending = @(Get-Job -Name 'deny-test' -ErrorAction SilentlyContinue | Where-Object { $_.State -in 'Running', 'NotStarted' })
            foreach ($j in $pending) { try { $null = $j.StopJobAsync() } catch { } ; $null = Wait-Job $j -Timeout 10 }
            if (@(Get-Job -Name 'deny-test' -ErrorAction SilentlyContinue | Where-Object { $_.State -in 'Running', 'NotStarted' })) {
                throw 'the delete test from step 2 is still running, so the deploy was skipped to keep vnet-app safe'
            }
            Start-ThreadJob -ArgumentList $script:Cfg, $v2 -ScriptBlock {
            param($cfg, $template)
            if (Get-Variable PSStyle -ErrorAction SilentlyContinue) { $PSStyle.OutputRendering = 'Ansi' }
            Import-Module Az.Resources -MinimumVersion 10.2.1 -WarningAction SilentlyContinue
            $s = Set-AzResourceGroupDeploymentStack -Name $cfg.stackName -ResourceGroupName $cfg.resourceGroup -TemplateFile $template `
                -ActionOnUnmanage DetachAll -DenySettingsMode $cfg.denySettingsMode -Force -WarningAction SilentlyContinue -ErrorAction Stop
            $still = [bool](Get-AzResource -ResourceGroupName $cfg.resourceGroup -Name 'vnet-app' -ErrorAction SilentlyContinue)
            ($s | Out-String -Width 4096) + "`nVNET_STILL_THERE=$still"
        } } `
        -Render { param($t)
            $still = $t -match 'VNET_STILL_THERE=True'
            $body = Format-StackText ($t -replace '(?m)^VNET_STILL_THERE=\w+\s*$', '')
            $tail = if ($still) { Color "  vnet-app is still in the resource group.`n  The stack just stopped managing it." '32' }
                    else { Color '  vnet-app is not in the resource group anymore.' '33' }
            $body + "`n`n" + $tail
        }
}

Reset-Screen
Write-Timing 'recap'
Banner 11 'Recap'
Write-Host "  Regular What-If doesn't know about your stack, and you get" -ForegroundColor Green
Write-Host '  the noise too.' -ForegroundColor Green
Write-Host ''
Write-Host '  Stacks What-If shows what happens to everything the stack' -ForegroundColor Green
Write-Host '  manages, including what gets detached or deleted, and it' -ForegroundColor Green
Write-Host '  filters out most of the noise.' -ForegroundColor Green
Write-Host ''
# Don't wait for a call that's still running in the background (for example one that timed out).
Get-Job -ErrorAction SilentlyContinue | Where-Object { $_.State -notin 'Running', 'NotStarted' } | Remove-Job -Force -ErrorAction SilentlyContinue
