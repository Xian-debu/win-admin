# tests/helpers/deepwin.ps1 - WPF fixture for v1.3 (T20/T21): a deliberately DEEP control tree.
#
# Why: Chromium puts page content at UIA depth 13-25, and v1.2's wuia defaulted to depth 3 (find:
# 12), which is why the real B站 page looked like "the DOM never enters the tree" (docs/21 F2).
# This fixture reproduces the geometry offline: 22 nested GroupBox controls, so the leaf button
# sits at depth ~23, with no browser involved.
#
# -Lazy: build the leaf controls only after -LazyMs, so a single walk really is "cold" and the
# warm/retry path in wuia (passes>1) can be asserted deterministically.
param(
    [string]$Title = 'wa-deep',
    [string]$Out = '',
    [switch]$Lazy,
    [int]$LazyMs = 600
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null

$w = New-Object System.Windows.Window
$w.Title = $Title
$w.Width = 860; $w.Height = 920
$w.WindowStartupLocation = 'Manual'
$w.Left = 120; $w.Top = 80
$root = New-Object System.Windows.Controls.StackPanel
$root.Margin = '4'
$w.Content = $root

$events = if ($Out) { [IO.Path]::ChangeExtension($Out, '.events.txt') } else { '' }
function Log-Event([string]$line) {
    if (-not $events) { return }
    try { [IO.File]::AppendAllText($events, "$line
", (New-Object Text.UTF8Encoding($false))) } catch { }
}

$leaf = New-Object System.Windows.Controls.StackPanel

function New-Btn([string]$text, [string]$aid, $onClick) {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $text
    $b.Width = 220; $b.Height = 30; $b.Margin = '2'
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($b, $aid)
    [System.Windows.Automation.AutomationProperties]::SetName($b, $text)
    if ($onClick) { $b.Add_Click($onClick) }
    return $b
}

$deepBtn = New-Btn '深层按钮' 'deep-btn' {
    Log-Event 'clicked:deep-btn'
    $w.Title = 'clicked:deep-btn'
}
$titleBtn = New-Btn '改标题' 'title-btn' {
    Log-Event 'clicked:title-btn'
    $w.Title = 'deepwin-title-changed'
}
$noopBtn = New-Btn '无效果' 'noop-btn' {
    Log-Event 'clicked:noop-btn'
}
[void]$leaf.Children.Add($deepBtn)
[void]$leaf.Children.Add($titleBtn)
[void]$leaf.Children.Add($noopBtn)

$tb1 = New-Object System.Windows.Controls.TextBlock
$tb1.Text = '第一条文本'; $tb1.Margin = '2'
[System.Windows.Automation.AutomationProperties]::SetAutomationId($tb1, 'text-1')
$tb2 = New-Object System.Windows.Controls.TextBlock
$tb2.Text = '第二条文本'; $tb2.Margin = '2'
[System.Windows.Automation.AutomationProperties]::SetAutomationId($tb2, 'text-2')
$tb3 = New-Object System.Windows.Controls.TextBlock
$tb3.Text = '第三条文本'; $tb3.Margin = '2'
[System.Windows.Automation.AutomationProperties]::SetAutomationId($tb3, 'text-3')
[void]$leaf.Children.Add($tb1)
[void]$leaf.Children.Add($tb2)
[void]$leaf.Children.Add($tb3)

$edit = New-Object System.Windows.Controls.TextBox
$edit.Width = 260; $edit.Height = 28; $edit.Margin = '2'
[System.Windows.Automation.AutomationProperties]::SetAutomationId($edit, 'wa-edit')
[System.Windows.Automation.AutomationProperties]::SetName($edit, '编辑框')
[void]$leaf.Children.Add($edit)

# 22 nested GroupBoxes -> the leaf controls live at UIA depth ~23 (each GroupBox is a Group control).
$inner = $leaf
for ($i = 22; $i -ge 1; $i--) {
    $gb = New-Object System.Windows.Controls.GroupBox
    $gb.Header = "L$i"
    $gb.Padding = '2'
    $gb.Margin = '2'
    $gb.BorderThickness = '1'
    $gb.FontSize = 8
    $gb.Content = $inner
    $inner = $gb
}

function Write-Info {
    if (-not $Out) { return }
    $h = (New-Object System.Windows.Interop.WindowInteropHelper($w)).Handle
    $o = [ordered]@{
        ok = $true
        pid = $PID
        hwnd = ('0x{0:x}' -f [long]$h)
        hwnd_dec = [long]$h
        title = $w.Title
        lazy = [bool]$Lazy
        rects = [ordered]@{}
    }
    foreach ($pair in @(@('deep', $deepBtn), @('title', $titleBtn), @('noop', $noopBtn), @('edit', $edit))) {
        $el = $pair[1]
        if (-not $el.ActualWidth) { continue }
        try {
            $p = $el.PointToScreen((New-Object System.Windows.Point(0, 0)))
            $o.rects[$pair[0]] = [ordered]@{ x = [int]$p.X; y = [int]$p.Y; w = [int]$el.ActualWidth; h = [int]$el.ActualHeight }
        } catch { }
    }
    [IO.File]::WriteAllText($Out, ($o | ConvertTo-Json -Depth 6 -Compress), (New-Object Text.UTF8Encoding($false)))
}

if ($Lazy) {
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($LazyMs)
    $timer.Add_Tick({
        $btn = New-Btn '延迟出现' 'lazy-btn' { Log-Event 'clicked:lazy-btn' }
        [void]$leaf.Children.Insert(0, $btn)
        $root.Children.Clear()
        [void]$root.Children.Add($inner)
        $timer.Stop()
    })
    $timer.Start()
} else {
    [void]$root.Children.Add($inner)
}

$w.Add_ContentRendered({
    Write-Info
})
[void]$w.ShowDialog()
