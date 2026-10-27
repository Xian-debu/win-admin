param(
    [string]$Core = '',
    [string]$Version = 'unknown',
    [string]$Action = 'list',
    [long]$Hwnd = 0,
    # v1.1 (T1): state / set
    [string]$State = '',
    [int]$X = [int]::MinValue,
    [int]$Y = [int]::MinValue,
    [int]$Width = -1,
    [int]$Height = -1,
    [string]$Topmost = '',
    [long]$OwnedBy = 0,
    [switch]$IncludeEmpty,
    [switch]$DryRun
)
$env:WA_VERSION = $Version
if (-not $Core) { $Core = Join-Path $PSScriptRoot 'lib/wa-core.ps1' }
. $Core

# SWP flags
$SWP_NOSIZE = 0x0001; $SWP_NOMOVE = 0x0002; $SWP_NOZORDER = 0x0004
$HWND_TOPMOST = [IntPtr](-1); $HWND_NOTOPMOST = [IntPtr](-2)

function Test-TargetWindow([long]$h, [string]$who) {
    if (-not $h) { Write-WaFail 'ARG_NEED_TARGET' "$who needs -Hwnd"; return $false }
    if (-not [Wa.Native]::IsWindow([IntPtr]$h)) {
        Write-WaFail 'ENV_NO_WINDOW' "not a window handle: $h"; return $false
    }
    return $true
}

function Get-SetExpectations {
    $exp = [ordered]@{ state = ''; x = $null; y = $null; w = $null; h = $null; topmost = $null }
    if ($State) {
        switch ($State) {
            'max' { $exp.state = 'maximized' }
            'min' { $exp.state = 'minimized' }
            'restore' { $exp.state = 'normal' }
            'normal' { $exp.state = 'normal' }
            default { }
        }
    }
    if ($X -ne [int]::MinValue) { $exp.x = $X }
    if ($Y -ne [int]::MinValue) { $exp.y = $Y }
    if ($Width -ge 0) { $exp.w = $Width }
    if ($Height -ge 0) { $exp.h = $Height }
    if ($Topmost -eq 'on') { $exp.topmost = $true }
    elseif ($Topmost -eq 'off') { $exp.topmost = $false }
    return $exp
}

# Assert the post-state against what was asked (E9/E10): a silent no-op is a failure, not a success.
function Compare-Expectation($exp, $b, $a) {
    $bad = @()
    if ($exp.state -eq 'maximized' -and -not $a.maximized) { $bad += "state: want maximized, got $($a.state)" }
    if ($exp.state -eq 'minimized' -and -not $a.minimized) { $bad += "state: want minimized, got $($a.state)" }
    if ($exp.state -eq 'normal' -and $a.state -ne 'normal') { $bad += "state: want normal, got $($a.state)" }
    if ($null -ne $exp.topmost -and $a.topmost -ne $exp.topmost) {
        $bad += "topmost: want $($exp.topmost), got $($a.topmost)"
    }
    # geometry assertions only make sense when the window is not maximized/minimized
    if ($a.state -eq 'normal') {
        if ($null -ne $exp.x -and [Math]::Abs($a.rect.x - $exp.x) -gt 2) { $bad += "x: want $($exp.x), got $($a.rect.x)" }
        if ($null -ne $exp.y -and [Math]::Abs($a.rect.y - $exp.y) -gt 2) { $bad += "y: want $($exp.y), got $($a.rect.y)" }
        if ($null -ne $exp.w -and [Math]::Abs($a.rect.w - $exp.w) -gt 2) { $bad += "w: want $($exp.w), got $($a.rect.w)" }
        if ($null -ne $exp.h -and [Math]::Abs($a.rect.h - $exp.h) -gt 2) { $bad += "h: want $($exp.h), got $($a.rect.h)" }
    }
    return $bad
}

try {
    [void](Set-WaDpi)
    if ($Action -eq 'info') {
        if (-not (Test-TargetWindow $Hwnd 'info')) { exit 2 }
        $w = Get-WaWindowInfo ([IntPtr]$Hwnd)
        Out-WaJson ([ordered]@{ ok = $true; action = 'info'; window = $w; at = (Get-Date).ToUniversalTime().ToString('o') })
        exit 0
    }
    if ($Action -eq 'focus') {
        if (-not (Test-TargetWindow $Hwnd 'focus')) { exit 2 }
        if (-not (Set-WaForeground ([IntPtr]$Hwnd))) {
            Write-WaFail 'ENV_NOT_FOREGROUND' "could not bring hwnd $Hwnd to the foreground"
            exit 3
        }
        $w = Get-WaWindowInfo ([IntPtr]$Hwnd)
        Out-WaJson ([ordered]@{ ok = $true; action = 'focus'; foreground = $true; window = $w; at = (Get-Date).ToUniversalTime().ToString('o') })
        exit 0
    }
    if ($Action -eq 'close') {
        if (-not (Test-TargetWindow $Hwnd 'close')) { exit 2 }
        # WM_CLOSE: graceful request; the app decides (a modified document shows its own save prompt).
        [void][Wa.Native]::PostMessage([IntPtr]$Hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        $w = Get-WaWindowInfo ([IntPtr]$Hwnd)
        Out-WaJson ([ordered]@{ ok = $true; action = 'close'; requested = $true; window = $w; at = (Get-Date).ToUniversalTime().ToString('o') })
        exit 0
    }
    if ($Action -eq 'state') {
        if (-not (Test-TargetWindow $Hwnd 'state')) { exit 2 }
        $st = Get-WaWindowState ([IntPtr]$Hwnd)
        $fg = [Wa.Native]::GetForegroundWindow().ToInt64()
        $wa = Get-WaWorkArea
        Out-WaJson ([ordered]@{
            ok         = $true
            action     = 'state'
            window     = $st
            screen     = (Get-WaScreen)
            work_area  = $wa
            foreground = ($fg -eq $Hwnd)
            at         = (Get-Date).ToUniversalTime().ToString('o')
        })
        exit 0
    }
    if ($Action -eq 'set') {
        if (-not (Test-TargetWindow $Hwnd 'set')) { exit 2 }
        if ($State -and $State -notin @('max', 'min', 'restore', 'normal')) {
            Write-WaFail 'ARG_BAD_STATE' "unknown -State '$State' (max|min|restore|normal)"
            exit 2
        }
        if ($Topmost -and $Topmost -notin @('on', 'off')) {
            Write-WaFail 'ARG_BAD_TOPMOST' "unknown -Topmost '$Topmost' (on|off)"
            exit 2
        }
        if ($Width -eq 0 -or $Height -eq 0 -or $Width -lt -1 -or $Height -lt -1) {
            Write-WaFail 'ARG_BAD_GEOMETRY' 'width/height must be > 0'
            exit 2
        }
        $h = [IntPtr]$Hwnd
        $before = Get-WaWindowState $h
        $exp = Get-SetExpectations
        $none = (-not $State) -and ($X -eq [int]::MinValue) -and ($Y -eq [int]::MinValue) -and ($Width -lt 0) -and ($Height -lt 0) -and (-not $Topmost)
        if ($none) {
            Write-WaFail 'ARG_NOTHING_TO_DO' 'set needs at least one of -State / -X / -Y / -Width / -Height / -Topmost'
            exit 2
        }
        $plan = [ordered]@{}
        if ($State) { $plan.state = $State }
        if ($X -ne [int]::MinValue) { $plan.x = $X }
        if ($Y -ne [int]::MinValue) { $plan.y = $Y }
        if ($Width -ge 0) { $plan.w = $Width }
        if ($Height -ge 0) { $plan.h = $Height }
        if ($Topmost) { $plan.topmost = $Topmost }
        if ($DryRun) {
            Out-WaJson ([ordered]@{
                ok = $true; action = 'set'; dry_run = $true; plan = $plan
                before = $before; work_area = (Get-WaWorkArea)
                at = (Get-Date).ToUniversalTime().ToString('o')
            })
            exit 0
        }
        $applied = @()
        if ($State) {
            $sw = switch ($State) { 'max' { 3 } 'min' { 6 } 'restore' { 9 } 'normal' { 1 } }
            [void][Wa.Native]::ShowWindow($h, $sw)
            $applied += "ShowWindow($sw)"
            Start-Sleep -Milliseconds 200
        }
        $wantGeom = ($X -ne [int]::MinValue) -or ($Y -ne [int]::MinValue) -or ($Width -ge 0) -or ($Height -ge 0)
        if ($wantGeom) {
            # geometry is ignored while maximized: restore first, then place
            $cur = (Get-WaWindowState $h)
            if ($cur.maximized) {
                [void][Wa.Native]::ShowWindow($h, 9)
                $applied += 'ShowWindow(9) before move/resize'
                Start-Sleep -Milliseconds 200
                $cur = (Get-WaWindowState $h)
            }
            $nx = if ($X -ne [int]::MinValue) { $X } else { $cur.rect.x }
            $ny = if ($Y -ne [int]::MinValue) { $Y } else { $cur.rect.y }
            $nw = if ($Width -ge 0) { $Width } else { $cur.rect.w }
            $nh = if ($Height -ge 0) { $Height } else { $cur.rect.h }
            $flags = $SWP_NOZORDER
            if ($X -eq [int]::MinValue -and $Y -eq [int]::MinValue) { $flags = $flags -bor $SWP_NOMOVE }
            if ($Width -lt 0 -and $Height -lt 0) { $flags = $flags -bor $SWP_NOSIZE }
            [void][Wa.Native]::SetWindowPos($h, [IntPtr]::Zero, $nx, $ny, $nw, $nh, $flags)
            $applied += "SetWindowPos($nx,$ny,$nw,$nh,0x$($flags.ToString('x4')))"
            Start-Sleep -Milliseconds 200
        }
        if ($Topmost) {
            $after = if ($Topmost -eq 'on') { $HWND_TOPMOST } else { $HWND_NOTOPMOST }
            [void][Wa.Native]::SetWindowPos($h, $after, 0, 0, 0, 0, ($SWP_NOMOVE -bor $SWP_NOSIZE))
            $applied += "SetWindowPos(topmost=$Topmost)"
            Start-Sleep -Milliseconds 200
        }
        Start-Sleep -Milliseconds 150
        $afterState = Get-WaWindowState $h
        $bad = Compare-Expectation $exp $before $afterState
        if ($bad.Count -gt 0) {
            Out-WaJson ([ordered]@{
                ok = $false; code = 'ENV_STATE_UNCHANGED'
                msg = ("post-state does not match the request: " + ($bad -join '; '))
                action = 'set'; plan = $plan; applied = $applied
                before = $before; after = $afterState; mismatches = $bad
                at = (Get-Date).ToUniversalTime().ToString('o')
            })
            exit 3
        }
        Out-WaJson ([ordered]@{
            ok = $true; action = 'set'; plan = $plan; applied = $applied
            before = $before; after = $afterState
            at = (Get-Date).ToUniversalTime().ToString('o')
        })
        exit 0
    }
    if ($Action -ne 'list') {
        Write-WaFail 'ARG_BAD_ACTION' "unsupported action: $Action (list|info|focus|close|state|set)"
        exit 2
    }
    $wins = Get-WaTopWindows -IncludeEmpty:$IncludeEmpty
    if ($OwnedBy -ne 0) {
        $want = ('0x{0:x}' -f $OwnedBy)
        $wins = @($wins | Where-Object { $_.owner -eq $want })
    }
    Out-WaJson ([ordered]@{
        ok        = $true
        action    = 'list'
        includeEmpty = [bool]$IncludeEmpty
        ownedBy   = $(if ($OwnedBy -ne 0) { ('0x{0:x}' -f $OwnedBy) } else { $null })
        count     = $wins.Count
        windows   = $wins
        at      = (Get-Date).ToUniversalTime().ToString('o')
    })
    exit 0
} catch {
    Write-WaFail 'EXEC_FAIL' $_.Exception.Message
    exit 5
}
