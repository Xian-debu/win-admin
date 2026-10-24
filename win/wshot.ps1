param(
    [string]$Core = '',
    [string]$Out = '',
    [int]$X = -999999,
    [int]$Y = -999999,
    [int]$W = 0,
    [int]$H = 0,
    [long]$Hwnd = 0,
    [int]$Grid = 0,
    [switch]$Clip
)
$env:WA_VERSION = if ($env:WA_VERSION) { $env:WA_VERSION } else { 'unknown' }
if (-not $Core) { $Core = Join-Path $PSScriptRoot 'lib/wa-core.ps1' }
. $Core

try {
    $dpiMode = Set-WaDpi
    $desk = Get-WaDesktopInfo
    if ($desk.secured) {
        Write-WaFail (Get-WaBlockCode $desk 'ENV_SECURE_DESKTOP') "input desktop unavailable: $($desk.reason)"
        exit 3
    }
    $screen = Get-WaScreen
    # T9: -Hwnd shoots exactly the window rect. bin/wshot rejects --hwnd together with --rect,
    # so there is exactly one source for the geometry here.
    if ($Hwnd -ne 0) {
        $ws = Get-WaWindowState $Hwnd
        if (-not $ws) { Write-WaFail 'ENV_NO_WINDOW' ("not a window handle: " + $Hwnd); exit 3 }
        $r = $ws.rect
        if ($r.w -le 0 -or $r.h -le 0) { Write-WaFail 'ENV_NO_WINDOW' ("window has no drawable area: " + $Hwnd); exit 3 }
        $X = $r.x; $Y = $r.y; $W = $r.w; $H = $r.h
    }
    if ($X -eq -999999) { $X = $screen.x }
    if ($Y -eq -999999) { $Y = $screen.y }
    if ($W -le 0) { $W = $screen.w }
    if ($H -le 0) { $H = $screen.h }
    # T15: --clip trims the request to the screen instead of failing; without it the failure
    # message must say what was asked, what the screen is, and the two ways to fix it.
    $reqX = $X; $reqY = $Y; $reqW = $W; $reqH = $H
    $clipped = $false
    if ($X -lt $screen.x -or $Y -lt $screen.y -or ($X + $W) -gt ($screen.x + $screen.w) -or ($Y + $H) -gt ($screen.y + $screen.h)) {
        if ($Clip) {
            $x1 = [Math]::Max($X, $screen.x)
            $y1 = [Math]::Max($Y, $screen.y)
            $x2 = [Math]::Min($X + $W, $screen.x + $screen.w)
            $y2 = [Math]::Min($Y + $H, $screen.y + $screen.h)
            if (($x2 - $x1) -lt 1 -or ($y2 - $y1) -lt 1) {
                Write-WaFail 'ARG_OUT_OF_SCREEN' ("requested {0},{1} {2}x{3} does not intersect the screen {4},{5} {6}x{7}" -f $reqX, $reqY, $reqW, $reqH, $screen.x, $screen.y, $screen.w, $screen.h)
                exit 2
            }
            $X = $x1; $Y = $y1; $W = $x2 - $x1; $H = $y2 - $y1
            $clipped = $true
        } else {
            $msg = "rect {0},{1} {2}x{3} outside screen {4},{5} {6}x{7}" -f $reqX, $reqY, $reqW, $reqH, $screen.x, $screen.y, $screen.w, $screen.h
            $msg += "; pass --clip to trim it, or --box X1,Y1,X2,Y2 for a left-top/right-bottom pair"
            Write-WaFail 'ARG_OUT_OF_SCREEN' $msg
            exit 2
        }
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
    # T9: -Grid N draws a ruler over the pixels. Lines land on multiples of N in *screen*
    # coordinates and each line is labelled with that absolute coordinate, so a reader can map
    # image pixels back to click coordinates without arithmetic.
    if ($Grid -gt 0) {
        $penMinor = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 255, 0, 0)), 1
        $penMajor = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160, 255, 0, 0)), 1
        $font = New-Object System.Drawing.Font 'Consolas', 8
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 255, 40, 40))
        $sx = $X - ($X % $Grid); if ($sx -lt $X) { $sx += $Grid }
        for ($gx = $sx; $gx -le ($X + $W - 1); $gx += $Grid) {
            $lx = $gx - $X
            if (($gx % ($Grid * 5)) -eq 0) { $pen = $penMajor } else { $pen = $penMinor }
            $g.DrawLine($pen, $lx, 0, $lx, $H - 1)
            $g.DrawString([string]$gx, $font, $brush, [float]($lx + 2), [float]2)
        }
        $sy = $Y - ($Y % $Grid); if ($sy -lt $Y) { $sy += $Grid }
        for ($gy = $sy; $gy -le ($Y + $H - 1); $gy += $Grid) {
            $ly = $gy - $Y
            if (($gy % ($Grid * 5)) -eq 0) { $pen = $penMajor } else { $pen = $penMinor }
            $g.DrawLine($pen, 0, $ly, $W - 1, $ly)
            $g.DrawString([string]$gy, $font, $brush, [float]2, [float]($ly + 1))
        }
        $penMinor.Dispose(); $penMajor.Dispose(); $font.Dispose(); $brush.Dispose()
    }
    $g.Dispose()
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $len = (Get-Item $Out).Length
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Out).Hash.ToLower()
    $hwndS = if ($Hwnd -ne 0) { '0x{0:x}' -f $Hwnd } else { '' }
    Out-WaJson ([ordered]@{
        ok      = $true
        path    = $Out
        x       = $X; y = $Y; w = $W; h = $H
        rect    = @{ x = $X; y = $Y; w = $W; h = $H }
        image   = @{ w = $W; h = $H }
        scale   = $(if ($screen.dpi) { [Math]::Round([double]$screen.dpi / 96.0, 2) } else { 1 })
        requested = @{ x = $reqX; y = $reqY; w = $reqW; h = $reqH }
        clipped = $clipped
        bytes   = $len
        sha256  = $sha
        grid    = $Grid
        hwnd    = $hwndS
        screen  = $screen
        dpiMode = $dpiMode
        at      = (Get-Date).ToUniversalTime().ToString('o')
    })
    exit 0
} catch {
    Write-WaFail 'EXEC_FAIL' $_.Exception.Message
    exit 5
}
