param([string]$Core = '', [string]$Version = 'unknown')
$env:WA_VERSION = $Version
if (-not $Core) { $Core = Join-Path $PSScriptRoot 'lib/wa-core.ps1' }
. $Core

try {
    $dpiMode = Set-WaDpi
    $desk = Get-WaDesktopInfo
    $screen = Get-WaScreen
    $fg = $null
    $h = [Wa.Native]::GetForegroundWindow()
    if ($h -ne [IntPtr]::Zero) { $fg = Get-WaWindowInfo $h }
    $proc = Get-Process -Id $PID
    $os = $null
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { }
    $out = [ordered]@{
        ok        = $true
        version   = $script:WaVersion
        at        = (Get-Date).ToUniversalTime().ToString('o')
        host      = $env:COMPUTERNAME
        user      = $env:USERNAME
        os        = if ($os) { [ordered]@{ caption = $os.Caption; build = $os.BuildNumber; version = $os.Version } } else { $null }
        session   = [ordered]@{ id = $proc.SessionId; interactive = ($desk.secured -eq $false) }
        desktop   = $desk
        screen    = $screen
        dpiMode   = $dpiMode
        foreground = $fg
        powershell = $PSVersionTable.PSVersion.ToString()
        pid       = $PID
    }
    Out-WaJson $out
    exit 0
} catch {
    Write-WaFail 'EXEC_FAIL' $_.Exception.Message
    exit 5
}
