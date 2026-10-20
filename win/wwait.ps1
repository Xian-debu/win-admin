param(
    [string]$Core = '',
    [string]$Version = 'unknown',
    [string]$Title = '',
    [long]$Hwnd = 0,
    [int]$Timeout = 10,
    [int]$Interval = 100
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -Namespace WaWait -Name Native -MemberDefinition @'
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
'@ | Out-Null
try { [WaWait.Native]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null } catch { }
$env:WA_VERSION = $Version

function Out-Json($o) { Write-Output ($o | ConvertTo-Json -Compress -Depth 10) }

if (-not $Title -and -not $Hwnd) {
    Out-Json @{ ok = $false; code = 'ARG_NEED_TARGET'; msg = 'wwait needs -Title or -Hwnd' }
    exit 2
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$re = if ($Title) { [regex]$Title } else { $null }
$polls = 0
$hit = $null

while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
    $polls = $polls + 1
    if ($Hwnd) {
        if ([WaWait.Native]::IsWindow([IntPtr]$Hwnd) -and [WaWait.Native]::IsWindowVisible([IntPtr]$Hwnd)) {
            $sb = New-Object System.Text.StringBuilder 512
            [void][WaWait.Native]::GetWindowTextW([IntPtr]$Hwnd, $sb, 512)
            $hit = @{ hwnd = ('0x{0:x}' -f $Hwnd); hwnd_dec = $Hwnd; title = $sb.ToString() }
        }
    } else {
        $script:found = $null
        $cb = [WaWait.Native+EnumProc]{
            param($h, $l)
            if (-not $script:found -and [WaWait.Native]::IsWindowVisible($h)) {
                $sb = New-Object System.Text.StringBuilder 512
                [void][WaWait.Native]::GetWindowTextW($h, $sb, 512)
                $t = $sb.ToString()
                if ($t -and $t -match $re) {
                    $script:found = @{ hwnd = ('0x{0:x}' -f $h.ToInt64()); hwnd_dec = $h.ToInt64(); title = $t }
                }
            }
            return $true
        }
        [void][WaWait.Native]::EnumWindows($cb, [IntPtr]::Zero)
        $hit = $script:found
    }
    if ($hit) { break }
    Start-Sleep -Milliseconds $Interval
}

$elapsed = [int]$sw.Elapsed.TotalMilliseconds
if (-not $hit) {
    Out-Json @{ ok = $false; code = 'ENV_WAIT_TIMEOUT'; msg = "no window matched within $Timeout s"; polls = $polls; elapsed_ms = $elapsed; title = $Title; timeout_s = $Timeout; at_epoch_ms = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) }
    exit 3
}
Out-Json ([ordered]@{
    ok = $true
    mode = 'wait'
    window = $hit
    elapsed_ms = $elapsed
    polls = $polls
    interval_ms = $Interval
    timeout_s = $Timeout
    at_epoch_ms = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
})
exit 0
