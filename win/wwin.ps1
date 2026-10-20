param([string]$Core = '', [string]$Version = 'unknown', [string]$Action = 'list')
$env:WA_VERSION = $Version
if (-not $Core) { $Core = Join-Path $PSScriptRoot 'lib/wa-core.ps1' }
. $Core

try {
    [void](Set-WaDpi)
    if ($Action -ne 'list') {
        Write-WaFail 'ARG_BAD_ACTION' "unsupported action: $Action (M1 only supports list)"
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
