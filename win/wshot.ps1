param(
    [string]$Core = '',
    [string]$Out = '',
    [int]$X = -999999,
    [int]$Y = -999999,
    [int]$W = 0,
    [int]$H = 0
)
$env:WA_VERSION = if ($env:WA_VERSION) { $env:WA_VERSION } else { 'unknown' }
if (-not $Core) { $Core = Join-Path $PSScriptRoot 'lib/wa-core.ps1' }
. $Core

try {
    $dpiMode = Set-WaDpi
    $desk = Get-WaDesktopInfo
    if ($desk.secured) {
        Write-WaFail 'ENV_SECURE_DESKTOP' "input desktop unavailable: $($desk.reason)"
        exit 3
    }
    $screen = Get-WaScreen
    if ($X -eq -999999) { $X = $screen.x }
    if ($Y -eq -999999) { $Y = $screen.y }
    if ($W -le 0) { $W = $screen.w }
    if ($H -le 0) { $H = $screen.h }
    if ($X -lt $screen.x -or $Y -lt $screen.y -or ($X + $W) -gt ($screen.x + $screen.w) -or ($Y + $H) -gt ($screen.y + $screen.h)) {
        Write-WaFail 'ARG_OUT_OF_SCREEN' ("rect {0},{1} {2}x{3} outside screen {4},{5} {6}x{7}" -f $X, $Y, $W, $H, $screen.x, $screen.y, $screen.w, $screen.h)
        exit 2
    }
    if (-not $Out) {
        $dir = Join-Path $env:PUBLIC 'win-admin/shots'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $Out = Join-Path $dir ("shot-" + (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '.png')
    }
    $dir = Split-Path -Parent $Out
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($X, $Y, 0, 0, (New-Object System.Drawing.Size $W, $H))
    $g.Dispose()
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $len = (Get-Item $Out).Length
    Out-WaJson ([ordered]@{
        ok      = $true
        path    = $Out
        x       = $X; y = $Y; w = $W; h = $H
        bytes   = $len
        screen  = $screen
        dpiMode = $dpiMode
        at      = (Get-Date).ToUniversalTime().ToString('o')
    })
    exit 0
} catch {
    Write-WaFail 'EXEC_FAIL' $_.Exception.Message
    exit 5
}
