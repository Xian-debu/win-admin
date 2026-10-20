param(
  [string]$Core = '',
  [string]$Version = 'unknown',
  [Parameter(Mandatory=$true)][string]$Exe,
  [string]$Arguments = '',
  [string]$Title = '',
  [int]$Timeout = 10
)
# Must be first: -File/-stdin invocations get no PROLOG from winps (K1).
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:WA_VERSION = $Version
if ($Core -ne '') { . $Core }

# Local fail helper: writes the failure JSON and exits with the documented code.
function Fail([string]$code, [string]$msg, [int]$rc = 3) { Write-WaFail $code $msg; exit $rc }
# Unexpected terminating errors must still yield one JSON object on stdout.
trap { Write-WaFail 'EXEC_FAIL' $_.Exception.Message; exit 5 }

$desk = Get-WaDesktopInfo
if ($desk.secured) { Fail (Get-WaBlockCode $desk) ("desktop secured: " + $desk.desktop) }

$resolved = $Exe
if (-not (Test-Path -LiteralPath $Exe)) {
  $cmd = Get-Command $Exe -ErrorAction SilentlyContinue
  if ($null -eq $cmd) { Fail 'ENV_NO_EXE' ("cannot find executable: " + $Exe) }
  $resolved = $cmd.Source
}
$proc = $null
$t0 = Get-Date
try {
  if ($Arguments -ne '') { $proc = Start-Process -FilePath $resolved -ArgumentList $Arguments -PassThru }
  else { $proc = Start-Process -FilePath $resolved -PassThru }
} catch { Fail 'EXEC_START_FAILED' $_.Exception.Message }

$deadline = $t0.AddSeconds($Timeout)
$found = $null
$visible = @()
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 100
  $visible = @(Get-WaTopWindows)
  foreach ($w in $visible) {
    if ($w.pid -eq $proc.Id) { $found = $w; break }
  }
  if ($null -ne $found) { break }
  if ($Title -ne '') {
    foreach ($w in $visible) {
      if ($w.title -match $Title) { $found = $w; break }
    }
    if ($null -ne $found) { break }
  }
}
$elapsed = [int]((Get-Date) - $t0).TotalMilliseconds
if ($null -eq $found) {
  $exited = $false
  try { $exited = $proc.HasExited } catch { $exited = $true }
  $msg = "no window for pid " + $proc.Id + " within " + $Timeout + "s (exited=" + $exited + ")"
  Fail 'ENV_WAIT_TIMEOUT' $msg
}
Out-WaJson @{
  ok = $true
  version = $Version
  exe = $resolved
  arguments = $Arguments
  pid = $proc.Id
  elapsed_ms = $elapsed
  window = @{
    hwnd = $found.hwnd
    hwnd_dec = $found.hwnd_dec
    title = $found.title
    class = $found.class
    pid = $found.pid
    process = $found.process
    rect = $found.rect
  }
}
