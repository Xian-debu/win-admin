param([Parameter(Mandatory=$true)][string]$Png, [Parameter(Mandatory=$true)][string]$Items)
# win/wannotate.ps1 - draw numbered element boxes onto a screenshot (used by ops/map, T16).
# Input: a TSV file "idx<TAB>x<TAB>y<TAB>w<TAB>h<TAB>actionable" in PNG pixel coordinates.
# The PNG is read into memory first: Image.FromFile keeps the file locked, so saving back to the
# same path fails with a generic GDI+ error (K50).
$ErrorActionPreference = 'Stop'
try {
  Add-Type -AssemblyName System.Drawing | Out-Null
  $bytes = [System.IO.File]::ReadAllBytes($Png)
  $ms = New-Object System.IO.MemoryStream(,$bytes)
  $img = [System.Drawing.Image]::FromStream($ms)
  $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.DrawImage($img, 0, 0, $img.Width, $img.Height)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
  $penHot = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(235, 30, 30), 2)
  $penCold = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 150, 150), 1)
  $font = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
  $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 240, 90))
  $fg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
  $n = 0; $hot = 0
  foreach ($line in [System.IO.File]::ReadAllLines($Items)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $p = $line -split "`t"
    if ($p.Count -lt 6) { continue }
    $idx = [int]$p[0]; $x = [int]$p[1]; $y = [int]$p[2]; $w = [int]$p[3]; $h = [int]$p[4]; $a = [int]$p[5]
    if ($w -le 0 -or $h -le 0) { continue }
    if ($x -lt 0 -or $y -lt 0 -or $x -ge $img.Width -or $y -ge $img.Height) { continue }
    $rw = [Math]::Min($w, $img.Width - $x); $rh = [Math]::Min($h, $img.Height - $y)
    if ($rw -le 0 -or $rh -le 0) { continue }
    if ($a -eq 1) { $g.DrawRectangle($penHot, $x, $y, $rw - 1, $rh - 1); $hot++ }
    else { $g.DrawRectangle($penCold, $x, $y, $rw - 1, $rh - 1) }
    $label = [string]$idx
    $sz = $g.MeasureString($label, $font)
    $lx = [Math]::Max(0, [Math]::Min($x, $img.Width - $sz.Width - 2))
    $ly = [Math]::Max(0, [Math]::Min($y, $img.Height - $sz.Height - 2))
    $g.FillRectangle($bg, [float]$lx, [float]$ly, [float]$sz.Width, [float]$sz.Height)
    $g.DrawString($label, $font, $fg, [float]$lx, [float]$ly)
    $n++
  }
  $g.Dispose()
  $img.Dispose(); $ms.Dispose()
  $tmp = $Png + '.annotating.png'
  $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Move-Item -LiteralPath $tmp -Destination $Png -Force
  $penHot.Dispose(); $penCold.Dispose(); $font.Dispose(); $bg.Dispose(); $fg.Dispose()
  Write-Output ('{"ok":true,"boxes":' + $n + ',"actionable":' + $hot + '}')
  exit 0
} catch {
  $m = $_.Exception.Message -replace '"', "'"
  $m = $m -replace "[^\x20-\x7e]", "?"
  Write-Output ('{"ok":false,"code":"EXEC_FAIL","msg":"' + $m + '"}')
  exit 5
}
