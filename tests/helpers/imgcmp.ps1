param(
    [Parameter(Mandatory=$true)][string]$A,
    [Parameter(Mandatory=$true)][string]$B,
    [string]$Pixels = ''   # semicolon-separated 'x,y' pairs to compare
)
# tests/helpers/imgcmp.ps1 - compare two PNGs for the m12 acceptance script.
# Prints one JSON object: {ok,size_a,size_b,same_size,diff_ratio,samples:[{x,y,eq,rgb_a,rgb_b}]}
Add-Type -AssemblyName System.Drawing
try {
    $ia = [System.Drawing.Bitmap]::FromFile($A)
    $ib = [System.Drawing.Bitmap]::FromFile($B)
    $sameSize = ($ia.Width -eq $ib.Width -and $ia.Height -eq $ib.Height)
    $diff = 0; $total = 0
    if ($sameSize) {
        for ($y = 0; $y -lt $ia.Height; $y += 3) {
            for ($x = 0; $x -lt $ia.Width; $x += 3) {
                $total++
                if ($ia.GetPixel($x, $y).ToArgb() -ne $ib.GetPixel($x, $y).ToArgb()) { $diff++ }
            }
        }
    }
    $samples = @()
    if ($Pixels) {
        foreach ($p in ($Pixels -split ';')) {
            if (-not $p) { continue }
            $xy = $p -split ','
            $px = [int]$xy[0]; $py = [int]$xy[1]
            $ca = $ia.GetPixel($px, $py); $cb = $ib.GetPixel($px, $py)
            $samples += [ordered]@{
                x = $px; y = $py
                eq = ($ca.ToArgb() -eq $cb.ToArgb())
                rgb_a = ('#{0:x2}{1:x2}{2:x2}' -f $ca.R, $ca.G, $ca.B)
                rgb_b = ('#{0:x2}{1:x2}{2:x2}' -f $cb.R, $cb.G, $cb.B)
            }
        }
    }
    $ratio = 0.0
    if ($total -gt 0) { $ratio = [math]::Round($diff / $total, 4) }
    $out = [ordered]@{
        ok = $true
        size_a = @($ia.Width, $ia.Height)
        size_b = @($ib.Width, $ib.Height)
        same_size = $sameSize
        diff_ratio = $ratio
        samples = $samples
    }
    $ia.Dispose(); $ib.Dispose()
    $out | ConvertTo-Json -Compress -Depth 5
    exit 0
} catch {
    [ordered]@{ ok = $false; code = 'EXEC_FAIL'; msg = $_.Exception.Message } | ConvertTo-Json -Compress
    exit 5
}
