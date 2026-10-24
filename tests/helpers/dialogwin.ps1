param(
    [string]$OutFile = 'C:/Users/Public/win-admin/tmp/dialogwin.json'
)
# tests/helpers/dialogwin.ps1 - window-family fixture for T13 (v1.2).
# Three real top-level windows: a main window, a modal-style child dialog OWNED by it (so the
# pair is one window family but two different roots), and an unrelated window. C14 needs exactly
# this shape: an owner-linked dialog is what docs/19 F1 could not click.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
Add-Type -Namespace WaTest4 -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
'@ | Out-Null
try { [WaTest4.Dpi]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null } catch { }

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$eventsFile = Join-Path $dir 'dialogwin-events.txt'
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($eventsFile, '', $utf8)
function Log([string]$line) { [IO.File]::AppendAllText($eventsFile, ($line + [char]10), $utf8) }

function New-Title([string]$t, [int]$w, [int]$h, [int]$x, [int]$y) {
    $win = New-Object System.Windows.Window
    $win.Title = $t
    $win.Width = $w
    $win.Height = $h
    $win.Left = $x
    $win.Top = $y
    $win.WindowStartupLocation = 'Manual'
    return $win
}

$main = New-Title 'wa-dialog' 440 340 380 380
$mp = New-Object System.Windows.Controls.StackPanel
$mp.Margin = New-Object System.Windows.Thickness(12)
$mlbl = New-Object System.Windows.Controls.TextBlock
$mlbl.Text = 'MAIN-LABEL'
$mlbl.Height = 24
$mp.Children.Add($mlbl) | Out-Null
$mbtn = New-Object System.Windows.Controls.Button
$mbtn.Content = 'MAIN-BTN'
$mbtn.Height = 36
[System.Windows.Automation.AutomationProperties]::SetAutomationId($mbtn, 'wa-main-btn')
$mbtn.Add_Click({ Log 'main clicked' })
$mp.Children.Add($mbtn) | Out-Null
$main.Content = $mp

$child = New-Title 'wa-dialog-child' 380 260 900 420
$cp = New-Object System.Windows.Controls.StackPanel
$cp.Margin = New-Object System.Windows.Thickness(12)
$clbl = New-Object System.Windows.Controls.TextBlock
$clbl.Text = 'CHILD-LABEL 子对话框'
$clbl.Height = 24
$cp.Children.Add($clbl) | Out-Null
$cbtn = New-Object System.Windows.Controls.Button
$cbtn.Content = 'CHILD-BTN'
$cbtn.Height = 36
[System.Windows.Automation.AutomationProperties]::SetAutomationId($cbtn, 'wa-child-btn')
$cbtn.Add_Click({ Log 'child clicked' })
$cp.Children.Add($cbtn) | Out-Null
$cedit = New-Object System.Windows.Controls.TextBox
$cedit.Height = 28
[System.Windows.Automation.AutomationProperties]::SetAutomationId($cedit, 'wa-child-edit')
$cp.Children.Add($cedit) | Out-Null
$child.Content = $cp

$other = New-Title 'wa-dialog-other' 320 240 1400 420
$op = New-Object System.Windows.Controls.StackPanel
$op.Margin = New-Object System.Windows.Thickness(12)
$obtn = New-Object System.Windows.Controls.Button
$obtn.Content = 'OTHER-BTN'
$obtn.Height = 36
$obtn.Add_Click({ Log 'other clicked' })
$op.Children.Add($obtn) | Out-Null
$other.Content = $op

function Get-Handle($w) {
    $h = New-Object System.Windows.Interop.WindowInteropHelper $w
    return $h.Handle.ToInt64()
}

$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnLastWindowClose'
$null = $app.Dispatcher.InvokeAsync({
    $main.Show()
    $child.Owner = $main
    $child.Show()
    $other.Show()
    $o = [ordered]@{
        hwnd_dec       = (Get-Handle $main)
        child_hwnd_dec = (Get-Handle $child)
        other_hwnd_dec = (Get-Handle $other)
        events         = $eventsFile
    }
    [IO.File]::WriteAllText($OutFile, ($o | ConvertTo-Json -Compress), $utf8)
})
[void]$app.Run()