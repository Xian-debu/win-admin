param(
    [string]$Core = '',
    [string]$Version = 'unknown',
    [Parameter(Mandatory = $true)][string]$Action,
    [int]$X = 0, [int]$Y = 0,
    [int]$X2 = 0, [int]$Y2 = 0,
    [string]$Button = 'left',
    [int]$Count = 1,
    [int]$Steps = 20,
    [int]$Delta = 120,
    [int]$Times = 1,
    [switch]$Horizontal,
    [int]$Dwell = 600,
    [string]$Combo = '',
    [string]$VkName = '',
    [int]$Hold = 20,
    [string]$HeldFile = '',
    [string]$TextFile = '',
    [long]$ExpectHwnd = 0,
    [switch]$DryRun,
    [switch]$Focus,
    [switch]$AllowRelated,
    [string]$VerifyMode = '',
    [switch]$NoRestoreClip
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:WA_VERSION = $Version
. $Core
$dpi = Set-WaDpi
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase | Out-Null

Add-Type -Namespace WaInput -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int d, UIntPtr extra);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
[DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
'@ | Out-Null

function Fail([string]$code, [string]$msg, [int]$exitCode) {
    Write-WaFail $code $msg
    exit $exitCode
}

function Get-Vk([string]$name) {
    $n = $name.Trim().ToLower()
    $map = @{
        'enter' = 0x0D; 'tab' = 0x09; 'esc' = 0x1B; 'escape' = 0x1B; 'space' = 0x20;
        'backspace' = 0x08; 'delete' = 0x2E; 'del' = 0x2E; 'insert' = 0x2D;
        'home' = 0x24; 'end' = 0x23; 'pageup' = 0x21; 'pagedown' = 0x22; 'prior' = 0x21; 'next' = 0x22;
        'up' = 0x26; 'down' = 0x28; 'left' = 0x25; 'right' = 0x27;
        'ctrl' = 0x11; 'control' = 0x11; 'shift' = 0x10; 'alt' = 0x12; 'win' = 0x5B;
        'plus' = 0xBB; 'minus' = 0xBD; 'comma' = 0xBC; 'period' = 0xBE; 'slash' = 0xBF;
        'semicolon' = 0xBA; 'quote' = 0xDE; 'bracketleft' = 0xDB; 'bracketright' = 0xDD;
        'backslash' = 0xDC; 'grave' = 0xC0
    }
    if ($map.ContainsKey($n)) { return $map[$n] }
    if ($n -match '^f([0-9]{1,2})$') {
        $i = [int]$Matches[1]
        if ($i -ge 1 -and $i -le 24) { return 0x70 + $i - 1 }
    }
    if ($n.Length -eq 1) {
        $u = [int][char]$n.ToUpper()
        if (($u -ge 0x30 -and $u -le 0x39) -or ($u -ge 0x41 -and $u -le 0x5A)) { return $u }
    }
    return -1
}

function Get-Root([IntPtr]$h) {
    if ($h -eq [IntPtr]::Zero) { return [IntPtr]::Zero }
    return [WaInput.Native]::GetAncestor($h, 2)
}

function Read-Held {
    if (-not $HeldFile -or -not (Test-Path $HeldFile)) { return @() }
    try { $a = Get-Content -Raw -Path $HeldFile | ConvertFrom-Json } catch { return @() }
    if ($null -eq $a) { return @() }
    return @($a)
}

function Write-Held([int[]]$vks) {
    if (-not $HeldFile) { return }
    $dir = Split-Path -Parent $HeldFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (-not $vks -or $vks.Count -eq 0) { Remove-Item -Force -Path $HeldFile -ErrorAction SilentlyContinue; return }
    $txt = ConvertTo-Json -InputObject @($vks) -Compress
    [IO.File]::WriteAllText($HeldFile, $txt, (New-Object Text.UTF8Encoding($false)))
}

function Get-TargetInfo([IntPtr]$h) {
    if ($h -eq [IntPtr]::Zero) { return $null }
    $w = Get-WaWindowInfo $h
    return $w
}

# Window family (v1.2 T13): a modal child dialog and its owner are different ROOT windows, so
# comparing roots declares "different window" for a window the user is plainly looking at.
# docs/19 F1: the "invalid file name" #32770 could not be clicked for exactly this reason.
# The chain walks BOTH the parent and the owner links (a modal dialog is owner-linked, an MDI
# child is parent-linked), stops at the desktop, and is capped so a cycle cannot hang us.
function Get-FamilyChain([IntPtr]$h) {
    $seen = New-Object System.Collections.ArrayList
    $desktop = [WaInput.Native]::GetDesktopWindow()
    $cur = $h
    for ($i = 0; $i -lt 24 -and $cur -ne [IntPtr]::Zero -and $cur -ne $desktop; $i++) {
        if ($seen -contains $cur.ToInt64()) { break }
        [void]$seen.Add($cur.ToInt64())
        $nx = [WaInput.Native]::GetAncestor($cur, 1)
        if ($nx -eq [IntPtr]::Zero -or $nx -eq $desktop) { $nx = [WaInput.Native]::GetWindow($cur, 4) }
        $cur = $nx
    }
    return $seen
}

function Test-Related([IntPtr]$a, [IntPtr]$b) {
    if ($a -eq $b) { return $true }
    $ca = Get-FamilyChain $a
    $cb = Get-FamilyChain $b
    foreach ($x in $ca) { if ($cb -contains $x) { return $true } }
    return $false
}

# Human-readable description of whatever is under a point: F8 showed a bare hwnd pair leaves the
# operator unable to tell "my coordinate is wrong" from "something is covering the target".
function Get-HitDesc([IntPtr]$h) {
    if ($h -eq [IntPtr]::Zero) { return 'no window' }
    $w = Get-WaWindowInfo $h
    $t = if ($w.title) { '"' + $w.title + '"' } else { '(untitled)' }
    return ('hwnd 0x' + $h.ToInt64().ToString('x') + ' ' + $t + ' class ' + $w.class + ' pid ' + $w.pid + ' rect ' + $w.rect.x + ',' + $w.rect.y + ' ' + $w.rect.w + 'x' + $w.rect.h)
}

function Assert-Target([IntPtr]$target, [int]$px, [int]$py, [bool]$needPoint, [bool]$doFocus) {
    $fgRaw = [WaInput.Native]::GetForegroundWindow()
    $fg = Get-Root $fgRaw
    if ($target -eq [IntPtr]::Zero) { return @{ ok = $true; foreground = $fg; matched = 'hwnd' } }
    if (-not [Wa.Native]::IsWindow($target)) { return @{ ok = $false; code = 'ENV_NO_WINDOW'; msg = 'target hwnd is not a window' } }
    $matched = 'hwnd'
    if ($needPoint) {
        $pt = New-Object WaInput.Native+POINT
        $pt.X = $px; $pt.Y = $py
        $underRaw = [WaInput.Native]::WindowFromPoint($pt)
        $under = Get-Root $underRaw
        $rel = $false
        if ($under -ne $target -and $AllowRelated) { $rel = Test-Related $underRaw $target }
        if ($under -ne $target -and -not $rel) {
            return @{ ok = $false; code = 'ENV_WINDOW_MISMATCH'; msg = ('point (' + $px + ',' + $py + ') hits ' + (Get-HitDesc $underRaw) + ', expected ' + (Get-HitDesc $target) + '; pass --allow-related for an owner/child dialog') }
        }
        if ($rel) { $matched = 'related' }
    }
    $fgOk = ($fg -eq $target)
    if (-not $fgOk -and $AllowRelated -and $fgRaw -ne [IntPtr]::Zero) { $fgOk = Test-Related $fgRaw $target }
    if (-not $fgOk) {
        if ($doFocus) {
            # K49: SW_RESTORE un-maximizes; only a minimized window needs it.
            if ([Wa.Native]::IsIconic($target)) { [WaInput.Native]::ShowWindow($target, 9) | Out-Null }
            [WaInput.Native]::SetForegroundWindow($target) | Out-Null
            Start-Sleep -Milliseconds 150
            $fgRaw = [WaInput.Native]::GetForegroundWindow()
            $fg = Get-Root $fgRaw
            $fgOk = ($fg -eq $target)
            if (-not $fgOk -and $AllowRelated -and $fgRaw -ne [IntPtr]::Zero) { $fgOk = Test-Related $fgRaw $target }
            if (-not $fgOk) {
                [WaInput.Native]::ShowWindow($target, 4) | Out-Null
                [WaInput.Native]::SetForegroundWindow($target) | Out-Null
                Start-Sleep -Milliseconds 150
                $fgRaw = [WaInput.Native]::GetForegroundWindow()
                $fg = Get-Root $fgRaw
                $fgOk = ($fg -eq $target)
                if (-not $fgOk -and $AllowRelated -and $fgRaw -ne [IntPtr]::Zero) { $fgOk = Test-Related $fgRaw $target }
            }
        }
        if (-not $fgOk) {
            return @{ ok = $false; code = 'ENV_NOT_FOREGROUND'; msg = ('target ' + (Get-HitDesc $target) + ' is not foreground (foreground ' + (Get-HitDesc $fgRaw) + ')') }
        }
    }
    return @{ ok = $true; foreground = $fg; matched = $matched }
}

# Hover/wheel targets may be popups (menus, tooltips, combo drop-downs): their root window is
# NOT the app's main window, so match on the owning process instead of the root hwnd (T2).
function Assert-TargetPid([IntPtr]$target, [int]$px, [int]$py) {
    if (-not [Wa.Native]::IsWindow($target)) { return @{ ok = $false; code = 'ENV_NO_WINDOW'; msg = 'target hwnd is not a window' } }
    $pt = New-Object WaInput.Native+POINT
    $pt.X = $px; $pt.Y = $py
    $underRaw = [WaInput.Native]::WindowFromPoint($pt)
    if ($underRaw -eq [IntPtr]::Zero) {
        return @{ ok = $false; code = 'ENV_WINDOW_MISMATCH'; msg = "no window at ($px,$py)" }
    }
    $under = Get-Root $underRaw
    if ($under -eq $target) { return @{ ok = $true; under = $under; matched = 'hwnd' } }
    $tp = 0; $up = 0
    [void][Wa.Native]::GetWindowThreadProcessId($target, [ref]$tp)
    [void][Wa.Native]::GetWindowThreadProcessId($underRaw, [ref]$up)
    if ($tp -gt 0 -and $tp -eq $up) { return @{ ok = $true; under = $under; matched = 'pid'; pid = $tp } }
    return @{ ok = $false; code = 'ENV_WINDOW_MISMATCH'; msg = ("point ($px,$py) hits hwnd 0x" + $under.ToInt64().ToString('x') + " of pid $up, expected hwnd 0x" + $target.ToInt64().ToString('x') + " of pid $tp") }
}

# What is under the cursor right now? window (Win32) + element (UIA) - the verifiable half of hover.
function Get-PointProbe([int]$px, [int]$py) {
    $pt = New-Object WaInput.Native+POINT
    $pt.X = $px; $pt.Y = $py
    $raw = [WaInput.Native]::WindowFromPoint($pt)
    $win = if ($raw -ne [IntPtr]::Zero) { Get-WaWindowInfo $raw } else { $null }
    $el = $null
    try {
        $sp = New-Object System.Windows.Point($px, $py)
        $a = [System.Windows.Automation.AutomationElement]::FromPoint($sp)
        if ($a) {
            $r = $a.Current.BoundingRectangle
            $el = [ordered]@{
                name    = $a.Current.Name
                type    = $a.Current.ControlType.ProgrammaticName
                aid     = $a.Current.AutomationId
                class   = $a.Current.ClassName
                enabled = $a.Current.IsEnabled
                offscreen = $a.Current.IsOffscreen
                rect    = [ordered]@{ x = [int]$r.X; y = [int]$r.Y; w = [int]$r.Width; h = [int]$r.Height }
            }
        }
    } catch { $el = [ordered]@{ error = $_.Exception.Message } }
    [ordered]@{ point = [ordered]@{ x = $px; y = $py }; window = $win; element = $el }
}

function Out-Plan($action, $extra) {
    $fg = Get-Root ([WaInput.Native]::GetForegroundWindow())
    $obj = @{
        ok = $true; action = $action; dryRun = [bool]$DryRun; injected = $false;
        dpiMode = $dpi; version = $Version; at = (Get-Date).ToString('o');
        screen = (Get-WaScreen); foreground = (Get-TargetInfo $fg)
    }
    if ($extra) { foreach ($k in $extra.Keys) { $obj[$k] = $extra[$k] } }
    Out-WaJson $obj
}

# ---- common gates ----
$desk = Get-WaDesktopInfo
if ($desk.secured) { Fail (Get-WaBlockCode $desk) ('input desktop is not Default: ' + $desk.desktop) 3 }
$scr = Get-WaScreen
if (($Action -in @('move', 'click', 'dclick', 'drag', 'wheel', 'hover'))) {
    if ($X -lt $scr.x -or $Y -lt $scr.y -or $X -ge ($scr.x + $scr.w) -or $Y -ge ($scr.y + $scr.h)) {
        Fail 'ARG_OUT_OF_SCREEN' "point ($X,$Y) outside screen $($scr.w)x$($scr.h)" 2
    }
}
if ($Action -in @('click', 'dclick', 'drag', 'wheel', 'hover') -and $ExpectHwnd -le 0) {
    Fail 'ARG_NEED_EXPECT_HWND' 'click/dclick/drag/wheel/hover require -ExpectHwnd (S7: never act blind)' 2
}
if ($Action -eq 'wheel') {
    if ($Delta -eq 0) { Fail 'ARG_BAD_DELTA' 'wheel needs a non-zero -Delta (120 = one notch)' 2 }
    if ($Times -lt 1 -or $Times -gt 50) { Fail 'ARG_BAD_TIMES' 'wheel -Times must be 1..50' 2 }
}
if ($Action -eq 'hover') {
    if ($Dwell -lt 0 -or $Dwell -gt 10000) { Fail 'ARG_BAD_DWELL' 'hover -Dwell must be 0..10000 ms' 2 }
    if ($Steps -lt 1 -or $Steps -gt 60) { Fail 'ARG_BAD_STEPS' 'hover -Steps must be 1..60' 2 }
}

$target = [IntPtr]::Zero
if ($ExpectHwnd -gt 0) { $target = [IntPtr]$ExpectHwnd }

# T14: read back what the focused element holds now. value -> text -> name, in that order;
# "available=false" means the toolkit cannot prove the text landed and the caller asked to verify.
function Get-FocusedReadback {
    $r = @{ available = $false; via = ''; value = ''; focused = $null }
    try {
        $fe = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($null -eq $fe) { return $r }
        $r.focused = @{ name = $fe.Current.Name; type = $fe.Current.ControlType.ProgrammaticName; aid = $fe.Current.AutomationId }
        $vp = $null
        if ($fe.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
            $r.available = $true; $r.via = 'value'; $r.value = [string]$vp.Current.Value; return $r
        }
        $tp = $null
        if ($fe.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) {
            $r.available = $true; $r.via = 'text'; $r.value = [string]$tp.DocumentRange.GetText(-1); return $r
        }
        if ($fe.Current.Name) { $r.available = $true; $r.via = 'name'; $r.value = [string]$fe.Current.Name }
    } catch { }
    return $r
}

function Normalize-Text([string]$t) {
    if ($null -eq $t) { return '' }
    return ($t -replace "`r`n", "`n").TrimEnd()
}

switch ($Action) {
    'move' {
        $chk = Assert-Target $target $X $Y $true ([bool]$Focus)
        if (-not $chk.ok) { Fail $chk.code $chk.msg 3 }
        if ($DryRun) { Out-Plan 'move' @{ point = @{ x = $X; y = $Y } }; exit 0 }
        [WaInput.Native]::SetCursorPos($X, $Y) | Out-Null
        Start-Sleep -Milliseconds 20
        $p = New-Object WaInput.Native+POINT
        [WaInput.Native]::GetCursorPos([ref]$p) | Out-Null
        Out-WaJson @{ ok = $true; action = 'move'; injected = $true; point = @{ x = $p.X; y = $p.Y }; expected = @{ x = $X; y = $Y }; dpiMode = $dpi; version = $Version }
    }
    'click' {
        $chk = Assert-Target $target $X $Y $true ([bool]$Focus)
        if (-not $chk.ok) { Fail $chk.code $chk.msg 3 }
        if ($DryRun) { Out-Plan 'click' @{ point = @{ x = $X; y = $Y }; button = $Button; count = $Count; matched = $chk.matched; target = (Get-TargetInfo $target) }; exit 0 }
        $down = 0x02; $up = 0x04
        if ($Button -eq 'right') { $down = 0x08; $up = 0x10 }
        elseif ($Button -eq 'middle') { $down = 0x20; $up = 0x40 }
        [WaInput.Native]::SetCursorPos($X, $Y) | Out-Null
        Start-Sleep -Milliseconds 25
        for ($i = 0; $i -lt $Count; $i++) {
            [WaInput.Native]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 35
            [WaInput.Native]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
            if ($Count -gt 1) { Start-Sleep -Milliseconds 90 }
        }
        $p = New-Object WaInput.Native+POINT
        [WaInput.Native]::GetCursorPos([ref]$p) | Out-Null
        $fg = Get-Root ([WaInput.Native]::GetForegroundWindow())
        Out-WaJson @{ ok = $true; action = 'click'; injected = $true; matched = $chk.matched; button = $Button; count = $Count; point = @{ x = $p.X; y = $p.Y }; target = (Get-TargetInfo $target); foreground = (Get-TargetInfo $fg); version = $Version }
    }
    'dclick' {
        $chk = Assert-Target $target $X $Y $true ([bool]$Focus)
        if (-not $chk.ok) { Fail $chk.code $chk.msg 3 }
        if ($DryRun) { Out-Plan 'dclick' @{ point = @{ x = $X; y = $Y }; target = (Get-TargetInfo $target) }; exit 0 }
        [WaInput.Native]::SetCursorPos($X, $Y) | Out-Null
        Start-Sleep -Milliseconds 25
        for ($i = 0; $i -lt 2; $i++) {
            [WaInput.Native]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 30
            [WaInput.Native]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 60
        }
        Out-WaJson @{ ok = $true; action = 'dclick'; injected = $true; point = @{ x = $X; y = $Y }; target = (Get-TargetInfo $target); version = $Version }
    }
    'drag' {
        $chk = Assert-Target $target $X $Y $true ([bool]$Focus)
        if (-not $chk.ok) { Fail $chk.code $chk.msg 3 }
        $under2 = Get-Root ([WaInput.Native]::WindowFromPoint((New-Object WaInput.Native+POINT -Property @{ X = $X2; Y = $Y2 })))
        if ($under2 -ne $target) {
            Fail 'ENV_WINDOW_MISMATCH' "drag end point hits hwnd 0x$($under2.ToInt64().ToString('x'))" 3
        }
        if ($DryRun) { Out-Plan 'drag' @{ from = @{ x = $X; y = $Y }; to = @{ x = $X2; y = $Y2 }; steps = $Steps; target = (Get-TargetInfo $target) }; exit 0 }
        [WaInput.Native]::SetCursorPos($X, $Y) | Out-Null
        Start-Sleep -Milliseconds 30
        [WaInput.Native]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 40
        for ($i = 1; $i -le $Steps; $i++) {
            $ix = [int]($X + ($X2 - $X) * $i / $Steps)
            $iy = [int]($Y + ($Y2 - $Y) * $i / $Steps)
            [WaInput.Native]::SetCursorPos($ix, $iy) | Out-Null
            Start-Sleep -Milliseconds 15
        }
        Start-Sleep -Milliseconds 60
        [WaInput.Native]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
        $p = New-Object WaInput.Native+POINT
        [WaInput.Native]::GetCursorPos([ref]$p) | Out-Null
        Out-WaJson @{ ok = $true; action = 'drag'; injected = $true; from = @{ x = $X; y = $Y }; to = @{ x = $p.X; y = $p.Y }; expected = @{ x = $X2; y = $Y2 }; target = (Get-TargetInfo $target); version = $Version }
    }
    'wheel' {
        $chk = Assert-Target $target $X $Y $true ([bool]$Focus)
        if (-not $chk.ok) { Fail $chk.code $chk.msg 3 }
        $flag = if ($Horizontal) { 0x1000 } else { 0x0800 }
        if ($DryRun) {
            Out-Plan 'wheel' @{ point = @{ x = $X; y = $Y }; delta = $Delta; times = $Times; horizontal = [bool]$Horizontal; under = (Get-PointProbe $X $Y); target = (Get-TargetInfo $target) }
            exit 0
        }
        [WaInput.Native]::SetCursorPos($X, $Y) | Out-Null
        Start-Sleep -Milliseconds 60
        $d = $Delta
        # a positive delta scrolls away from the user (up / left); negative scrolls toward (down / right)
        for ($i = 0; $i -lt $Times; $i++) {
            [WaInput.Native]::mouse_event($flag, 0, 0, $d, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 45
        }
        Start-Sleep -Milliseconds 120
        $probe = Get-PointProbe $X $Y
        Out-WaJson @{ ok = $true; action = 'wheel'; injected = $true; point = @{ x = $X; y = $Y }; delta = $Delta; times = $Times; horizontal = [bool]$Horizontal; under = $probe; target = (Get-TargetInfo $target); version = $Version }
    }
    'hover' {
        $chk = Assert-TargetPid $target $X $Y
        if (-not $chk.ok) { Fail $chk.code $chk.msg 3 }
        if ($DryRun) {
            Out-Plan 'hover' @{ point = @{ x = $X; y = $Y }; steps = $Steps; dwell = $Dwell; under = (Get-PointProbe $X $Y); target = (Get-TargetInfo $target) }
            exit 0
        }
        # glide in (a single teleport often does not open hover menus), then dwell, then read what is under it
        $cur = New-Object WaInput.Native+POINT
        [void][WaInput.Native]::GetCursorPos([ref]$cur)
        for ($i = 1; $i -le $Steps; $i++) {
            $ix = [int]($cur.X + ($X - $cur.X) * $i / $Steps)
            $iy = [int]($cur.Y + ($Y - $cur.Y) * $i / $Steps)
            [WaInput.Native]::SetCursorPos($ix, $iy) | Out-Null
            Start-Sleep -Milliseconds 12
        }
        [WaInput.Native]::SetCursorPos($X, $Y) | Out-Null
        Start-Sleep -Milliseconds $Dwell
        $probe = Get-PointProbe $X $Y
        $p2 = New-Object WaInput.Native+POINT
        [void][WaInput.Native]::GetCursorPos([ref]$p2)
        Out-WaJson @{ ok = $true; action = 'hover'; injected = $true; matched = $chk.matched; point = @{ x = $p2.X; y = $p2.Y }; expected = @{ x = $X; y = $Y }; steps = $Steps; dwell = $Dwell; under = $probe; target = (Get-TargetInfo $target); version = $Version }
    }
    'key' {
        if (-not $Combo) { Fail 'ARG_NO_COMBO' 'key needs -Combo (e.g. ctrl+s)' 2 }
        if ($Hold -lt 0 -or $Hold -gt 10000) { Fail 'ARG_BAD_HOLD' "hold out of range: $Hold" 2 }
        $parts = $Combo.ToLower() -split '\+'
        $vks = @()
        foreach ($p in $parts) {
            $vk = Get-Vk $p
            if ($vk -lt 0) { Fail 'ARG_BAD_KEY' "unknown key: $p" 2 }
            $vks += $vk
        }
        $chk = Assert-Target $target 0 0 $false ([bool]$Focus)
        if (-not $chk.ok) { Fail $chk.code $chk.msg 3 }
        if ($DryRun) { Out-Plan 'key' @{ combo = $Combo; vks = $vks; hold = $Hold; target = (Get-TargetInfo $target) }; exit 0 }
        foreach ($vk in $vks) { [WaInput.Native]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 20 }
        Start-Sleep -Milliseconds $Hold
        for ($i = $vks.Count - 1; $i -ge 0; $i--) { [WaInput.Native]::keybd_event([byte]$vks[$i], 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 20 }
        Out-WaJson @{ ok = $true; action = 'key'; injected = $true; combo = $Combo; vks = $vks; hold = $Hold; target = (Get-TargetInfo $target); version = $Version }
    }
    'keydown' {
        if (-not $VkName) { Fail 'ARG_NO_VK' 'keydown needs a key name (e.g. a, shift, f5)' 2 }
        if ($VkName -match '\+') { Fail 'ARG_BAD_KEY' "keydown takes one key; use 'key $VkName' for combos" 2 }
        $vk = Get-Vk $VkName
        if ($vk -lt 0) { Fail 'ARG_BAD_KEY' "unknown key: $VkName" 2 }
        $chk = Assert-Target $target 0 0 $false ([bool]$Focus)
        if (-not $chk.ok) { Fail $chk.code $chk.msg 3 }
        $held = @(Read-Held)
        if ($DryRun) { Out-Plan 'keydown' @{ vk = $vk; key = $VkName; held = $held; target = (Get-TargetInfo $target) }; exit 0 }
        [WaInput.Native]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero)
        if (-not ($held -contains $vk)) { $held += $vk }
        Write-Held $held
        Out-WaJson @{ ok = $true; action = 'keydown'; injected = $true; vk = $vk; key = $VkName; held = $held; target = (Get-TargetInfo $target); version = $Version }
    }
    'keyup' {
        if (-not $VkName) { Fail 'ARG_NO_VK' 'keyup needs a key name (e.g. a, shift, f5)' 2 }
        if ($VkName -match '\+') { Fail 'ARG_BAD_KEY' "keyup takes one key; use 'key $VkName' for combos" 2 }
        $vk = Get-Vk $VkName
        if ($vk -lt 0) { Fail 'ARG_BAD_KEY' "unknown key: $VkName" 2 }
        if ($DryRun) { Out-Plan 'keyup' @{ vk = $vk; key = $VkName; held = @(Read-Held) }; exit 0 }
        [WaInput.Native]::keybd_event([byte]$vk, 0, 2, [UIntPtr]::Zero)
        $held = @(Read-Held | Where-Object { [int]$_ -ne $vk })
        Write-Held $held
        Out-WaJson @{ ok = $true; action = 'keyup'; injected = $true; vk = $vk; key = $VkName; held = $held; version = $Version }
    }
    'releaseall' {
        $held = @(Read-Held)
        if ($DryRun) { Out-Plan 'releaseall' @{ held = $held }; exit 0 }
        foreach ($h in $held) { [WaInput.Native]::keybd_event([byte][int]$h, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 20 }
        Write-Held @()
        Out-WaJson @{ ok = $true; action = 'releaseall'; injected = ($held.Count -gt 0); released = $held; held = @(); version = $Version }
    }

    'type' {
        if (-not $TextFile) { Fail 'ARG_NO_TEXT_FILE' 'type needs -TextFile (UTF-8)' 2 }
        if (-not (Test-Path $TextFile)) { Fail 'ARG_TEXT_FILE_NOT_FOUND' "text file not found: $TextFile" 2 }
        $chk = Assert-Target $target 0 0 $false ([bool]$Focus)
        if (-not $chk.ok) { Fail $chk.code $chk.msg 3 }
        $text = [IO.File]::ReadAllText($TextFile, [Text.Encoding]::UTF8)
        if ($DryRun) { Out-Plan 'type' @{ chars = $text.Length; preview = ($text.Substring(0, [Math]::Min(60, $text.Length))); target = (Get-TargetInfo $target) }; exit 0 }
        $old = ''
        $had = [Windows.Forms.Clipboard]::ContainsText()
        if ($had) { $old = [Windows.Forms.Clipboard]::GetText() }
        [Windows.Forms.Clipboard]::SetText($text)
        Start-Sleep -Milliseconds 120
        [WaInput.Native]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
        [WaInput.Native]::keybd_event(0x56, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 40
        [WaInput.Native]::keybd_event(0x56, 0, 2, [UIntPtr]::Zero)
        [WaInput.Native]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 200
        if (-not $NoRestoreClip) {
            if ($had) { [Windows.Forms.Clipboard]::SetText($old) } else { [Windows.Forms.Clipboard]::Clear() }
        }
        $res = @{ ok = $true; action = 'type'; injected = $true; chars = $text.Length; method = 'clipboard+ctrl+v'; clipRestored = (-not $NoRestoreClip); target = (Get-TargetInfo $target); version = $Version }
        if ($VerifyMode) {
            $fb = Get-FocusedReadback
            $want = Normalize-Text $text
            $got = Normalize-Text $fb.value
            $matched = $false
            if ($fb.available) {
                if ($VerifyMode -eq 'exact') { $matched = ($got -ceq $want) }
                else { $matched = ($want.Length -gt 0 -and $got.Contains($want)) }
            }
            $res.verify = @{ mode = $VerifyMode; available = $fb.available; via = $fb.via; value = $got; expected = $want; matched = $matched; focused = $fb.focused }
            if (-not $matched) {
                $res.ok = $false
                $res.code = 'ENV_TEXT_NOT_ENTERED'
                $res.msg = 'typed text did not land in the focused element; pass --verify only when the target is UIA-readable'
                Out-WaJson $res
                exit 3
            }
        }
        Out-WaJson $res
    }
    default { Fail 'ARG_BAD_ACTION' "unknown action: $Action" 2 }
}