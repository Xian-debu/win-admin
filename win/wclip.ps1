param(
    [string]$Core = '',
    [string]$Version = 'unknown',
    [string]$Action = 'get',
    [string]$Text = '',
    [string]$TextFile = ''
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. $Core
$env:WA_VERSION = $Version
Set-WaDpi | Out-Null
Add-Type -AssemblyName System.Windows.Forms | Out-Null

function Get-ClipText {
    if ([Windows.Forms.Clipboard]::ContainsText()) { return [Windows.Forms.Clipboard]::GetText() }
    return ''
}

try {
    switch ($Action) {
        'get' {
            $t = Get-ClipText
            Out-WaJson @{ ok = $true; action = 'get'; text = $t; len = $t.Length; version = $Version }
        }
        'set' {
            if ($TextFile) {
                $t = [IO.File]::ReadAllText($TextFile, [Text.Encoding]::UTF8)
            } else {
                $t = $Text
            }
            [Windows.Forms.Clipboard]::SetText($t)
            $back = Get-ClipText
            if ($back -ne $t) {
                Write-WaFail 'EXEC_CLIPBOARD_MISMATCH' 'clipboard readback differs from input'
                exit 5
            }
            Out-WaJson @{ ok = $true; action = 'set'; len = $t.Length; version = $Version }
        }
        'clear' {
            [Windows.Forms.Clipboard]::Clear()
            Out-WaJson @{ ok = $true; action = 'clear'; version = $Version }
        }
        default {
            Write-WaFail 'ARG_BAD_ACTION' "unknown action: $Action"
            exit 2
        }
    }
} catch {
    Write-WaFail 'EXEC_FAIL' $_.Exception.Message
    exit 5
}
