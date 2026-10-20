param([string]$Core = '', [string]$Version = 'unknown', [string]$Action = 'list', [long]$Hwnd = 0)
$env:WA_VERSION = $Version
if (-not $Core) { $Core = Join-Path $PSScriptRoot 'lib/wa-core.ps1' }
. $Core

try {
    [void](Set-WaDpi)
    if ($Action -eq 'info') {
        if (-not $Hwnd) {
            Write-WaFail 'ARG_NEED_TARGET' 'info needs -Hwnd'
            exit 2
        }
        if (-not [Wa.Native]::IsWindow([IntPtr]$Hwnd)) {
            Write-WaFail 'ENV_NO_WINDOW' "not a window handle: $Hwnd"
            exit 3
        }
        $w = Get-WaWindowInfo ([IntPtr]$Hwnd)
        Out-WaJson ([ordered]@{ ok = $true; action = 'info'; window = $w; at = (Get-Date).ToUniversalTime().ToString('o') })
        exit 0
    }
    if ($Action -ne 'list') {
        Write-WaFail 'ARG_BAD_ACTION' "unsupported action: $Action (list|info)"
        exit 2
    }
    $wins = Get-WaTopWindows
    Out-WaJson ([ordered]@{
        ok      = $true
        action  = 'list'
        count   = $wins.Count
        windows = $wins
        at      = (Get-Date).ToUniversalTime().ToString('o')
    })
    exit 0
} catch {
    Write-WaFail 'EXEC_FAIL' $_.Exception.Message
    exit 5
}