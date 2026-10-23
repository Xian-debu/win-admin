param(
    [string]$Title = 'wa-uia',
    [string]$OutFile = 'C:/Users/Public/win-admin/tmp/uiawnd.json'
)
# tests/helpers/uiawnd.ps1 - UIA control fixture for T5/T6 (find + act).
# One control per pattern the toolkit may need, plus states a test can read back from disk:
# click counter, edit value, toggle state, combo/list selection. Everything is named so tests
# find it by name/aid instead of by pixel.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
Add-Type -Namespace WaTest3 -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
'@ | Out-Null
try { [WaTest3.Dpi]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null } catch { }

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$eventsFile = Join-Path $dir 'uiawnd-events.txt'
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($eventsFile, '', $utf8)
function Log([string]$line) { [IO.File]::AppendAllText($eventsFile, ($line + [char]10), $utf8) }

$win = New-Object System.Windows.Window
$win.Title = $Title
$win.Width = 520
$win.Height = 620
$win.WindowStartupLocation = 'CenterScreen'

$root = New-Object System.Windows.Controls.StackPanel
$root.Margin = New-Object System.Windows.Thickness(10)

$lbl = New-Object System.Windows.Controls.TextBlock
$lbl.Text = 'LBL-TITLE'
$lbl.Height = 24
$root.Children.Add($lbl) | Out-Null

$btn = New-Object System.Windows.Controls.Button
$btn.Content = 'BTN-COUNT'
$btn.Height = 36
$btn.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($btn, 'wa-btn')
$script:n = 0
$btn.Add_Click({ $script:n = $script:n + 1; Log "click $($script:n)" })
$root.Children.Add($btn) | Out-Null

$dis = New-Object System.Windows.Controls.Button
$dis.Content = 'BTN-DISABLED'
$dis.Height = 32
$dis.IsEnabled = $false
$dis.Margin = New-Object System.Windows.Thickness(0, 2, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($dis, 'wa-disabled')
$root.Children.Add($dis) | Out-Null

$edit = New-Object System.Windows.Controls.TextBox
$edit.Height = 60
$edit.FontSize = 14
[System.Windows.Automation.AutomationProperties]::SetAutomationId($edit, 'wa-edit')
$edit.Add_TextChanged({ Log ("value " + $edit.Text) })
$root.Children.Add($edit) | Out-Null

$chk = New-Object System.Windows.Controls.CheckBox
$chk.Content = 'CHK-A'
$chk.Height = 28
$chk.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($chk, 'wa-chk')
# UIA's Toggle pattern sets IsChecked without raising Click, so log the state events instead.
$chk.Add_Checked({ Log 'toggle True' })
$chk.Add_Unchecked({ Log 'toggle False' })
$root.Children.Add($chk) | Out-Null

$cbo = New-Object System.Windows.Controls.ComboBox
$cbo.Height = 30
$cbo.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($cbo, 'wa-cbo')
foreach ($c in @('RED', 'GREEN', 'BLUE')) {
    $item = New-Object System.Windows.Controls.ComboBoxItem
    $item.Content = $c
    [void]$cbo.Items.Add($item)
}
$cbo.Add_SelectionChanged({ if ($cbo.SelectedItem) { Log ("select " + $cbo.SelectedItem.Content) } })
$root.Children.Add($cbo) | Out-Null

$list = New-Object System.Windows.Controls.ListBox
$list.Height = 110
$list.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($list, 'wa-list')
foreach ($c in @('ROW-ONE', 'ROW-TWO', 'ROW-THREE')) {
    $li = New-Object System.Windows.Controls.ListBoxItem
    $li.Content = $c
    [void]$list.Items.Add($li)
}
$list.Add_SelectionChanged({ if ($list.SelectedItem) { Log ("row " + $list.SelectedItem.Content) } })
$root.Children.Add($list) | Out-Null

$ghost = New-Object System.Windows.Controls.TextBlock
$ghost.Text = 'GHOST'
$ghost.Visibility = 'Collapsed'
$root.Children.Add($ghost) | Out-Null

$win.Content = $root

$win.Add_Loaded({
    $helper = New-Object System.Windows.Interop.WindowInteropHelper -ArgumentList $win
    $h = $helper.Handle
    $win.UpdateLayout()
    function P($c) { $p = $c.PointToScreen((New-Object System.Windows.Point(0, 0))); return @{ x = [int]$p.X; y = [int]$p.Y; w = [int]$c.ActualWidth; h = [int]$c.ActualHeight } }
    $obj = @{
        kind     = 'wpf'
        hwnd     = ('0x' + $h.ToInt64().ToString('x'))
        hwnd_dec = $h.ToInt64()
        pid      = $PID
        title    = $Title
        at       = (Get-Date).ToString('o')
        rects    = @{ btn = (P $btn); edit = (P $edit); chk = (P $chk); cbo = (P $cbo); list = (P $list) }
        events   = $eventsFile
    }
    [IO.File]::WriteAllText($OutFile, ($obj | ConvertTo-Json -Compress -Depth 6), $utf8)
})

[void]$win.ShowDialog()
