param(
    [string]$Core = '',
    [string]$Version = 'unknown',
    [Parameter(Mandatory = $true)][string]$Action,
    [int]$X = 0, [int]$Y = 0,
    [int]$X2 = 0, [int]$Y2 = 0,
    [string]$Button = 'left',
    [int]$Count = 1,
    [int]$Steps = 20,
    [string]$Combo = '',
    [string]$TextFile = '',
    [long]$ExpectHwnd = 0,
    [switch]$DryRun,
    [switch]$Focus,
    [switch]$NoRestoreClip
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. $Core
$env:WA_VERSION = $Version
$dpi = Set-WaDpi
Add-Type -AssemblyName System.Windows.Forms | Out-Null

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

function Get-TargetInfo([IntPtr]$h) {
    if ($h -eq [IntPtr]::Zero) { return $null }
    $w = Get-WaWindowInfo $h
    return $w
}

function Assert-Target([IntPtr]$target, [int]$px, [int]$py, [bool]$needPoint, [bool]$doFocus) {
    $fg = Get-Root ([WaInput.Native]::GetForegroundWindow())
    if ($target -ne [IntPtr]::Zero) {
        if (-not [Wa.Native]::IsWindow($target)) { return @{ ok = $false; code = 'ENV_NO_WINDOW'; msg = 'target hwnd is not a window' } }
        if ($needPoint) {
            $pt = New-Object WaInput.Native+POINT
            $pt.X = $px; $pt.Y = $py
            $under = Get-Root ([WaInput.Native]::WindowFromPoint($pt))
            if ($under -ne $target) {
                return @{ ok = $false; code = 'ENV_WINDOW_MISMATCH'; msg = "point ($px,$py) hits hwnd 0x$($under.ToInt64().ToString('x')), expected 0x$($target.ToInt64().ToString('x'))" }
            }
        }
        if ($fg -ne $target) {
            if ($doFocus) {
                [WaInput.Native]::ShowWindow($target, 9) | Out-Null
                [WaInput.Native]::SetForegroundWindow($target) | Out-Null
                Start-Sleep -Milliseconds 150
                $fg = Get-Root ([WaInput.Native]::GetForegroundWindow())
            }
            if ($fg -ne $target) {
                return @{ ok = $false; code = 'ENV_NOT_FOREGROUND'; msg = "target 0x$($target.ToInt64().ToString('x')) is not foreground (foreground 0x$($fg.ToInt64().ToString('x')))" }
            }
        }
    }
    return @{ ok = $true; foreground = $fg }
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
if ($desk.secured) { Fail 'SESSION_LOCKED' ('input desktop is not Default: ' + $desk.desktop) 3 }
$scr = Get-WaScreen
if (($Action -in @('move', 'click', 'dclick', 'drag', 'wheel'))) {
    if ($X -lt $scr.x -or $Y -lt $scr.y -or $X -ge ($scr.x + $scr.w) -or $Y -ge ($scr.y + $scr.h)) {
        Fail 'ARG_OUT_OF_SCREEN' "point ($X,$Y) outside screen $($scr.w)x$($scr.h)" 2
    }
}
if ($Action -in @('click', 'dclick', 'drag') -and $ExpectHwnd -le 0) {
    Fail 'ARG_NEED_EXPECT_HWND' 'click/dclick/drag require -ExpectHwnd (S7: never click blind)' 2
}

$target = [IntPtr]::Zero
if ($ExpectHwnd -gt 0) { $target = [IntPtr]$ExpectHwnd }

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
        if ($DryRun) { Out-Plan 'click' @{ point = @{ x = $X; y = $Y }; button = $Button; count = $Count; target = (Get-TargetInfo $target) }; exit 0 }
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
        Out-WaJson @{ ok = $true; action = 'click'; injected = $true; button = $Button; count = $Count; point = @{ x = $p.X; y = $p.Y }; target = (Get-TargetInfo $target); foreground = (Get-TargetInfo $fg); version = $Version }
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
    'key' {
        if (-not $Combo) { Fail 'ARG_NO_COMBO' 'key needs -Combo (e.g. ctrl+s)' 2 }
        $chk = Assert-Target $target 0 0 $false ([bool]$Focus)
        if (-not $chk.ok) { Fail $chk.code $chk.msg 3 }
        if ($DryRun) { Out-Plan 'key' @{ combo = $Combo }; exit 0 }
        $parts = $Combo.ToLower() -split '\+'
        $vks = @()
        foreach ($p in $parts) {
            $vk = Get-Vk $p
            if ($vk -lt 0) { Fail 'ARG_BAD_KEY' "unknown key: $p" 2 }
            $vks += $vk
        }
        foreach ($vk in $vks) { [WaInput.Native]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 20 }
        for ($i = $vks.Count - 1; $i -ge 0; $i--) { [WaInput.Native]::keybd_event([byte]$vks[$i], 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 20 }
        Out-WaJson @{ ok = $true; action = 'key'; injected = $true; combo = $Combo; vks = $vks; target = (Get-TargetInfo $target); version = $Version }
    }
    'type' {
        if (-not $TextFile) { Fail 'ARG_NO_TEXT_FILE' 'type needs -TextFile (UTF-8)' 2 }
        if (-not (Test-Path $TextFile)) { Fail 'ARG_NO_TEXT_FILE' "missing file: $TextFile" 2 }
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
        Out-WaJson @{ ok = $true; action = 'type'; injected = $true; chars = $text.Length; method = 'clipboard+ctrl+v'; clipRestored = (-not $NoRestoreClip); target = (Get-TargetInfo $target); version = $Version }
    }
    default { Fail 'ARG_BAD_ACTION' "unknown action: $Action" 2 }
}
