param(
    [string]$Title = 'wa-select',
    [string]$OutFile = 'C:/Users/Public/win-admin/tmp/selectwin.json',
    [string]$EventsFile = 'C:/Users/Public/win-admin/tmp/selectwin-events.txt'
)
# tests/helpers/selectwin.ps1 - select-control fixture for T30 (v1.4).
# Two real shapes of "pick one from a list":
#   * panel type: REGION-TRIGGER expands an in-window scrollable list of 28 buttons (B站分区那类),
#     option 28 is far below the panel viewport, so a click must reveal it first;
#   * native type: a WPF ComboBox whose item list lives in its own top-level popup HWND owned by
#     this window - a different UIA root that the caller has to discover and click inside.
# State is observable from outside: the window title becomes 'region:REGION-07' / 'cbo:GREEN',
# the value label reads 'REGION-VALUE:...', and every event is appended to the events file.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
Add-Type -Namespace WaTest5 -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
'@ | Out-Null
try { [WaTest5.Dpi]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null } catch { }

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($EventsFile, '', $utf8)
function Log([string]$line) { [IO.File]::AppendAllText($EventsFile, ($line + [char]10), $utf8) }

$win = New-Object System.Windows.Window
$win.Title = $Title
$win.Width = 560
$win.Height = 720
$win.WindowStartupLocation = 'CenterScreen'

$root = New-Object System.Windows.Controls.StackPanel
$root.Margin = New-Object System.Windows.Thickness(12)

$lbl = New-Object System.Windows.Controls.TextBlock
$lbl.Text = 'SEL-TITLE'
$lbl.Height = 24
$root.Children.Add($lbl) | Out-Null

# --- native type: WPF ComboBox (item list = separate popup HWND, owner = this window)
$cbo = New-Object System.Windows.Controls.ComboBox
$cbo.Height = 30
$cbo.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($cbo, 'wa-cbo')
foreach ($c in @('RED', 'GREEN', 'BLUE')) {
    $item = New-Object System.Windows.Controls.ComboBoxItem
    $item.Content = $c
    [void]$cbo.Items.Add($item)
}
$cbo.Add_SelectionChanged({
    if ($cbo.SelectedItem) {
        $win.Title = 'cbo:' + $cbo.SelectedItem.Content
        Log ('cbo ' + $cbo.SelectedItem.Content)
    }
})
$root.Children.Add($cbo) | Out-Null

# --- panel type: trigger expands an in-page list; option click updates value + collapses
$val = New-Object System.Windows.Controls.TextBlock
$val.Text = 'REGION-VALUE:none'
$val.Height = 24
[System.Windows.Automation.AutomationProperties]::SetAutomationId($val, 'wa-region-value')
$root.Children.Add($val) | Out-Null

$trg = New-Object System.Windows.Controls.Button
$trg.Content = 'REGION-TRIGGER'
$trg.Height = 36
$trg.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($trg, 'wa-region-trigger')
$root.Children.Add($trg) | Out-Null

$grp = New-Object System.Windows.Controls.GroupBox
$grp.Header = 'REGION-PANEL'
$grp.Height = 210
$grp.Visibility = 'Collapsed'
[System.Windows.Automation.AutomationProperties]::SetAutomationId($grp, 'wa-region-panel')
$sv = New-Object System.Windows.Controls.ScrollViewer
$sv.VerticalScrollBarVisibility = 'Auto'
$sv.HorizontalScrollBarVisibility = 'Disabled'
$stack = New-Object System.Windows.Controls.StackPanel
for ($i = 1; $i -le 28; $i++) {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = ('REGION-{0:d2}' -f $i)
    $b.Height = 34
    $b.Margin = New-Object System.Windows.Thickness(2)
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($b, ('region-{0:d2}' -f $i))
    $b.Add_Click({
        param($s, $e)
        $val.Text = 'REGION-VALUE:' + $s.Content
        $grp.Visibility = 'Collapsed'
        $win.Title = 'region:' + $s.Content
        Log ('region ' + $s.Content)
    }.GetNewClosure())
    $stack.Children.Add($b) | Out-Null
}
$sv.Content = $stack
$grp.Content = $sv
$root.Children.Add($grp) | Out-Null

$trg.Add_Click({
    if ($grp.Visibility -eq 'Visible') { $grp.Visibility = 'Collapsed'; Log 'panel-close' }
    else { $grp.Visibility = 'Visible'; Log 'panel-open' }
}.GetNewClosure())

$win.Content = $root

$script:hwnd = [IntPtr]::Zero
$win.Add_Loaded({
    $script:hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
    $o = [ordered]@{
        ok = $true
        pid = $PID
        hwnd = ('0x{0:x}' -f [int64]$script:hwnd)
        hwnd_dec = [int64]$script:hwnd
        title = $win.Title
        rect = @{ x = [int]$win.Left; y = [int]$win.Top; w = [int]$win.Width; h = [int]$win.Height }
    }
    [IO.File]::WriteAllText($OutFile, ($o | ConvertTo-Json -Compress -Depth 5), $utf8)
    Log 'loaded'
})

$win.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'Escape' -and $grp.Visibility -eq 'Visible') {
        $grp.Visibility = 'Collapsed'
        Log 'panel-esc'
        $e.Handled = $true
    }
}.GetNewClosure())

[void]$win.ShowDialog()
