# win-admin core: shared helpers for the Windows-side payload.
# Invariants: stdout carries exactly one JSON object; diagnostics go to stderr;
# no input injection code lives here (D14).
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$script:WaVersion = $env:WA_VERSION
if (-not $script:WaVersion) { $script:WaVersion = 'unknown' }

foreach ($asm in @('System.Drawing', 'UIAutomationClient', 'UIAutomationTypes')) {
    try { Add-Type -AssemblyName $asm -ErrorAction Stop } catch {
        [Console]::Error.WriteLine("warn: assembly $asm unavailable: $($_.Exception.Message)")
    }
}

if (-not ('Wa.Native' -as [type])) {
    Add-Type -Namespace Wa -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern IntPtr OpenInputDesktop(uint f, bool inherit, uint access);
[DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr h);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool GetUserObjectInformation(IntPtr h, int idx, System.Text.StringBuilder info, int len, out int needed);
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
[DllImport("user32.dll")] public static extern uint GetDpiForSystem();
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public delegate bool EnumProc(IntPtr h, IntPtr p);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
'@
}

# Physical-pixel coordinate model (D4): must be per-monitor-v2 aware before any metric is read.
function Set-WaDpi {
    try {
        if ([Wa.Native]::SetProcessDpiAwarenessContext([IntPtr]-4)) { return 'per-monitor-v2' }
    } catch { }
    try {
        if ([Wa.Native]::SetProcessDPIAware()) { return 'system' }
    } catch { }
    return 'unaware'
}

function Out-WaJson($obj) {
    $obj | ConvertTo-Json -Compress -Depth 10
}

function Write-WaFail([string]$code, [string]$msg) {
    $o = [ordered]@{
        ok      = $false
        code    = $code
        msg     = $msg
        version = $script:WaVersion
        at      = (Get-Date).ToUniversalTime().ToString('o')
    }
    Out-WaJson $o
}

function Exit-WaCode([string]$code) {
    if ($code -like 'ARG*') { exit 2 }
    if ($code -like 'ENV*' -or $code -like 'SESSION*' -or $code -like 'UAC*') { exit 3 }
    if ($code -like 'GUARD*') { exit 4 }
    exit 5
}

function Get-WaDesktopInfo {
    # Test hook (D21): S3/S4 acceptance without locking the user out. Fail-closed by design:
    # the hook can only claim a SECURED desktop, never override a real secured state.
    $hook = Join-Path $env:PUBLIC 'win-admin/tmp/force-desktop.txt'
    if (Test-Path $hook) {
        $forced = ((Get-Content -Raw $hook) -as [string]).Trim()
        if ($forced -and $forced -ne 'Default') {
            return @{ secured = $true; desktop = $forced; reason = 'test-hook' }
        }
    }
    $h = [Wa.Native]::OpenInputDesktop(0, $false, 0x0101)
    if ($h -eq [IntPtr]::Zero) {
        return @{ secured = $true; desktop = $null; reason = 'OpenInputDesktop failed' }
    }
    $sb = New-Object System.Text.StringBuilder 256
    $needed = 0
    $ok = [Wa.Native]::GetUserObjectInformation($h, 2, $sb, 512, [ref]$needed)
    [void][Wa.Native]::CloseDesktop($h)
    $name = if ($ok) { $sb.ToString() } else { $null }
    @{ secured = ($name -ne 'Default'); desktop = $name; reason = $null }
}

# Map a secured desktop to the refusal code: Winlogon/Secure desktop = UAC prompt, anything else = locked session.
function Get-WaBlockCode($desk, [string]$default = 'SESSION_LOCKED') {
    if (-not $desk -or -not $desk.secured) { return $null }
    if ($desk.desktop -match 'Winlogon|Secure') { return 'UAC_SECURE_DESKTOP' }
    return $default
}

function Get-WaScreen {
    $x = [Wa.Native]::GetSystemMetrics(76)
    $y = [Wa.Native]::GetSystemMetrics(77)
    $w = [Wa.Native]::GetSystemMetrics(78)
    $h = [Wa.Native]::GetSystemMetrics(79)
    if ($w -le 0 -or $h -le 0) {
        $x = 0; $y = 0
        $w = [Wa.Native]::GetSystemMetrics(0)
        $h = [Wa.Native]::GetSystemMetrics(1)
    }
    $dpi = 96
    try { $dpi = [int][Wa.Native]::GetDpiForSystem() } catch { }
    if ($dpi -le 0) { $dpi = 96 }
    [ordered]@{
        x = $x; y = $y; w = $w; h = $h
        dpi = $dpi
        scale = [math]::Round($dpi / 96.0 * 100)
        primary = [ordered]@{ w = [Wa.Native]::GetSystemMetrics(0); h = [Wa.Native]::GetSystemMetrics(1) }
    }
}

function Get-WaWindowInfo([IntPtr]$h) {
    $sb = New-Object System.Text.StringBuilder 512
    [void][Wa.Native]::GetWindowTextW($h, $sb, 512)
    $title = $sb.ToString()
    $cb = New-Object System.Text.StringBuilder 256
    [void][Wa.Native]::GetClassNameW($h, $cb, 256)
    $pid_ = 0
    [void][Wa.Native]::GetWindowThreadProcessId($h, [ref]$pid_)
    $r = New-Object Wa.Native+RECT
    $hasRect = [Wa.Native]::GetWindowRect($h, [ref]$r)
    $pname = $null
    try { $pname = (Get-Process -Id $pid_ -ErrorAction Stop).ProcessName } catch { }
    [ordered]@{
        hwnd      = ('0x{0:x}' -f $h.ToInt64())
        hwnd_dec  = $h.ToInt64()
        title     = $title
        class     = $cb.ToString()
        pid       = $pid_
        process   = $pname
        visible   = [Wa.Native]::IsWindowVisible($h)
        minimized = [Wa.Native]::IsIconic($h)
        rect      = [ordered]@{ x = $r.Left; y = $r.Top; w = ($r.Right - $r.Left); h = ($r.Bottom - $r.Top) }
    }
}

# Foreground activation without synthetic input. Windows blocks SetForegroundWindow from a
# background process; attaching our input queue to BOTH the target window's thread and the
# current foreground thread lifts that restriction (measured 2026-10-21, M4).
function Set-WaForeground([IntPtr]$h) {
    [void][Wa.Native]::ShowWindow($h, 9)
    [void][Wa.Native]::BringWindowToTop($h)
    if ([Wa.Native]::GetForegroundWindow() -eq $h) { return $true }
    [void][Wa.Native]::SetForegroundWindow($h)
    if ([Wa.Native]::GetForegroundWindow() -eq $h) { return $true }
    $pid0 = [uint32]0
    $fg = [Wa.Native]::GetForegroundWindow()
    $fgThread = [Wa.Native]::GetWindowThreadProcessId($fg, [ref]$pid0)
    $targetThread = [Wa.Native]::GetWindowThreadProcessId($h, [ref]$pid0)
    $myThread = [Wa.Native]::GetCurrentThreadId()
    $attached = @()
    foreach ($t in @($fgThread, $targetThread)) {
        if ($t -ne 0 -and $t -ne $myThread) {
            if ([Wa.Native]::AttachThreadInput($myThread, $t, $true)) { $attached += $t }
        }
    }
    [void][Wa.Native]::SetForegroundWindow($h)
    [void][Wa.Native]::BringWindowToTop($h)
    foreach ($t in $attached) { [void][Wa.Native]::AttachThreadInput($myThread, $t, $false) }
    for ($i = 0; $i -lt 20; $i++) {
        if ([Wa.Native]::GetForegroundWindow() -eq $h) { return $true }
        Start-Sleep -Milliseconds 50
    }
    return $false
}

function Get-WaTopWindows {
    $found = New-Object System.Collections.ArrayList
    $cb = [Wa.Native+EnumProc]{
        param($h, $p)
        [void]$found.Add($h)
        return $true
    }
    [void][Wa.Native]::EnumWindows($cb, [IntPtr]::Zero)
    $out = New-Object System.Collections.ArrayList
    $tb = New-Object System.Text.StringBuilder 512
    foreach ($h in $found) {
        # cheap pre-filter: 474 top-level windows exist, but only ~13 are visible with a title.
        if (-not [Wa.Native]::IsWindowVisible($h)) { continue }
        [void]$tb.Clear()
        $n = [Wa.Native]::GetWindowTextW($h, $tb, 512)
        if ($n -le 0) { continue }
        [void]$out.Add((Get-WaWindowInfo $h))
    }
    $out.ToArray()
}
