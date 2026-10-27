param(
    [string]$Title = 'wa-scroll',
    [string]$OutFile = 'C:/Users/Public/win-admin/tmp/scrollwin.json'
)
# tests/helpers/scrollwin.ps1 - scroll/select/chip fixture for v1.4 (T28-T31).
# Everything is named so tests find it by name/aid, never by pixel:
#   ScrollViewer + 30 buttons  -> ops/reveal target far below the fold (F20)
#   OPEN-PANEL + inner list   -> in-page dropdown panel whose list scrolls (F21 panel path)
#   CBO-XX ComboBox (40 items)-> native popup that is its own top-level HWND (F21 native path)
#   TAG-INPUT + TAG-LIST      -> chip input; text starting with '#' drops the first Enter (F22)
#   LOAD-READY                -> READY-MARK appears 1.2 s later (F22 wait-ready)
# The window title is the observable state: 'opt:OPT-08' / 'panel:PANEL-07' / 'cbo:CBO-12'.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
Add-Type -Namespace WaTest4 -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
'@ | Out-Null
try { [WaTest4.Dpi]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null } catch { }

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$eventsFile = Join-Path $dir 'scrollwin-events.txt'
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($eventsFile, '', $utf8)
function Log([string]$line) { [IO.File]::AppendAllText($eventsFile, ($line + [char]10), $utf8) }

$win = New-Object System.Windows.Window
$win.Title = $Title
$win.Width = 760
$win.Height = 1040
$win.WindowStartupLocation = 'CenterScreen'

$root = New-Object System.Windows.Controls.StackPanel
$root.Margin = New-Object System.Windows.Thickness(10)

$lbl = New-Object System.Windows.Controls.TextBlock
$lbl.Text = 'SCROLL-TITLE'
$lbl.Height = 22
$root.Children.Add($lbl) | Out-Null

# ---- scroll container: 240 px tall, 30 buttons (about 5 visible) ----
$sv = New-Object System.Windows.Controls.ScrollViewer
$sv.Height = 240
$sv.VerticalScrollBarVisibility = 'Auto'
$sv.HorizontalScrollBarVisibility = 'Disabled'
[System.Windows.Automation.AutomationProperties]::SetAutomationId($sv, 'wa-sv')
$svStack = New-Object System.Windows.Controls.StackPanel
$script:opts = @{}
for ($i = 1; $i -le 30; $i++) {
    $name = ('OPT-{0:d2}' -f $i)
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $name
    $b.Height = 40
    $b.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($b, ('opt-{0:d2}' -f $i))
    $b.Add_Click({ param($s, $e) $win.Title = 'opt:' + $s.Content; Log ('opt ' + $s.Content) }.GetNewClosure())
    $svStack.Children.Add($b) | Out-Null
    $script:opts[$name] = $b
}
$sv.Content = $svStack
$root.Children.Add($sv) | Out-Null

# ---- in-page dropdown panel (B站分区那类): trigger + collapsed list of 25 items ----
$panelBtn = New-Object System.Windows.Controls.Button
$panelBtn.Content = 'OPEN-PANEL'
$panelBtn.Height = 34
$panelBtn.Margin = New-Object System.Windows.Thickness(0, 8, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($panelBtn, 'wa-open-panel')
$root.Children.Add($panelBtn) | Out-Null

$panel = New-Object System.Windows.Controls.Border
$panel.Visibility = 'Collapsed'
$panel.BorderBrush = [System.Windows.Media.Brushes]::Gray
$panel.BorderThickness = New-Object System.Windows.Thickness(1)
$psv = New-Object System.Windows.Controls.ScrollViewer
$psv.Height = 180
$psv.VerticalScrollBarVisibility = 'Auto'
$psv.HorizontalScrollBarVisibility = 'Disabled'
[System.Windows.Automation.AutomationProperties]::SetAutomationId($psv, 'wa-panel-sv')
$pStack = New-Object System.Windows.Controls.StackPanel
$script:panelItems = @{}
for ($i = 1; $i -le 25; $i++) {
    $name = ('PANEL-{0:d2}' -f $i)
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $name
    $b.Height = 34
    $b.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($b, ('panel-{0:d2}' -f $i))
    $b.Add_Click({ param($s, $e) $win.Title = 'panel:' + $s.Content; Log ('panel ' + $s.Content) }.GetNewClosure())
    $pStack.Children.Add($b) | Out-Null
    $script:panelItems[$name] = $b
}
$psv.Content = $pStack
$panel.Child = $psv
$panelBtn.Add_Click({ $panel.Visibility = 'Visible'; Log 'panel-open' })
$root.Children.Add($panel) | Out-Null

# ---- native popup combo (40 items; WPF renders the list in its own popup HWND) ----
$cbo = New-Object System.Windows.Controls.ComboBox
$cbo.Width = 240
$cbo.Height = 32
$cbo.Margin = New-Object System.Windows.Thickness(0, 8, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($cbo, 'wa-cbo')
for ($i = 1; $i -le 40; $i++) { [void]$cbo.Items.Add(('CBO-{0:d2}' -f $i)) }
$cbo.Add_SelectionChanged({ if ($cbo.SelectedItem) { $win.Title = 'cbo:' + $cbo.SelectedItem; Log ('cbo ' + $cbo.SelectedItem) } })
$root.Children.Add($cbo) | Out-Null

$cboVal = New-Object System.Windows.Controls.TextBlock
$cboVal.Text = 'CBO-VALUE:none'
$cboVal.Height = 22
[System.Windows.Automation.AutomationProperties]::SetAutomationId($cboVal, 'wa-cbo-value')
$root.Children.Add($cboVal) | Out-Null

# ---- chip input: Enter adds 'TAG-<text>'; '#'-prefixed text loses its first Enter ----
$tag = New-Object System.Windows.Controls.TextBox
$tag.Height = 30
$tag.Margin = New-Object System.Windows.Thickness(0, 8, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($tag, 'wa-tag-input')
$root.Children.Add($tag) | Out-Null

$tagList = New-Object System.Windows.Controls.WrapPanel
$tagList.MinHeight = 62
[System.Windows.Automation.AutomationProperties]::SetAutomationId($tagList, 'wa-tag-list')
$root.Children.Add($tagList) | Out-Null

$script:swallowOnce = $false
$tag.Add_KeyDown({
    param($s, $e)
    if ($e.Key -ne 'Enter') { return }
    $t = $s.Text
    if ([string]::IsNullOrWhiteSpace($t)) { return }
    if ($t.StartsWith('#') -and -not $script:swallowOnce) {
        $script:swallowOnce = $true
        $s.Clear()
        Log ('swallowed ' + $t)
        $e.Handled = $true
        return
    }
    $chip = New-Object System.Windows.Controls.Border
    $chip.BorderBrush = [System.Windows.Media.Brushes]::SteelBlue
    $chip.BorderThickness = New-Object System.Windows.Thickness(1)
    $chip.Margin = New-Object System.Windows.Thickness(2)
    $chip.Padding = New-Object System.Windows.Thickness(4)
    $ct = New-Object System.Windows.Controls.TextBlock
    $ct.Text = $t
    $chip.Child = $ct
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($chip, 'chip')
    $tagList.Children.Add($chip) | Out-Null
    $s.Clear()
    $e.Handled = $true
    Log ('chip ' + $t)
})

# ---- delayed readiness (SPA shell -> real content) ----
$loadBtn = New-Object System.Windows.Controls.Button
$loadBtn.Content = 'LOAD-READY'
$loadBtn.Height = 32
$loadBtn.Margin = New-Object System.Windows.Thickness(0, 6, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($loadBtn, 'wa-load')
$root.Children.Add($loadBtn) | Out-Null

$ready = New-Object System.Windows.Controls.TextBlock
$ready.Text = 'NOT-READY'
$ready.Height = 22
[System.Windows.Automation.AutomationProperties]::SetAutomationId($ready, 'wa-ready')
$root.Children.Add($ready) | Out-Null

$loadBtn.Add_Click({
    $ready.Text = 'NOT-READY'
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(1200)
    $timer.Add_Tick({ $ready.Text = 'READY-MARK'; $timer.Stop(); Log 'ready' })
    $timer.Start()
    Log 'load-clicked'
})

# ---- clipped text: an ancestor without ScrollPattern that really clips the child ----
# F19-4 needs a container whose scroll state cannot be measured: the ScrollViewer above always has
# ScrollPattern, so this Border (ClipToBounds, 40 px tall) holds a Canvas child pushed down 60 px.
# GroupBox (not Border) on purpose: a Border has NO automation peer, so UIA cannot see it and the
# geometric fallback has nothing to compare against (F19-4 would collapse to via:'none'). GroupBox
# has a peer (ControlType.Group), which is what a real non-scrolling clipping ancestor looks like.
$clipBorder = New-Object System.Windows.Controls.GroupBox
$clipBorder.Height = 40
$clipBorder.ClipToBounds = $true
$clipBorder.BorderBrush = [System.Windows.Media.Brushes]::Gray
$clipBorder.BorderThickness = New-Object System.Windows.Thickness(1)
$clipBorder.Margin = New-Object System.Windows.Thickness(0, 6, 0, 4)
[System.Windows.Automation.AutomationProperties]::SetAutomationId($clipBorder, 'wa-clip')
$clipCanvas = New-Object System.Windows.Controls.Canvas
$clipCanvas.Height = 40
$clipText = New-Object System.Windows.Controls.TextBlock
$clipText.Text = 'CLIPPED-TEXT'
[System.Windows.Automation.AutomationProperties]::SetAutomationId($clipText, 'wa-clipped')
[System.Windows.Controls.Canvas]::SetTop($clipText, 60)
$clipCanvas.Children.Add($clipText) | Out-Null
$clipBorder.Content = $clipCanvas
$root.Children.Add($clipBorder) | Out-Null

$win.Content = $root

$errFile = Join-Path $dir 'scrollwin-error.txt'
$win.Add_Loaded({
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper -ArgumentList $win
        $h = $helper.Handle
        $win.UpdateLayout()
        # P returns PHYSICAL pixels: PointToScreen is DPI-aware while ActualWidth/Height are DIPs
        # (150% here), so mixing them made fixture rects 1.5x smaller than the UIA rects (K72).
        # A collapsed or clipped visual must never throw: the old version called PointToScreen
        # unguarded and dumped a PowerShell error console over the window.
        function P($c) {
            try {
                $p0 = $c.PointToScreen((New-Object System.Windows.Point(0, 0)))
                $p1 = $c.PointToScreen((New-Object System.Windows.Point($c.ActualWidth, $c.ActualHeight)))
                return @{ x = [int]$p0.X; y = [int]$p0.Y; w = [int][Math]::Abs($p1.X - $p0.X); h = [int][Math]::Abs($p1.Y - $p0.Y) }
            } catch {
                return @{ x = 0; y = 0; w = 0; h = 0; err = 'not-rendered' }
            }
        }
        $obj = @{
            kind      = 'wpf'
            hwnd      = ('0x' + $h.ToInt64().ToString('x'))
            hwnd_dec  = $h.ToInt64()
            pid       = $PID
            title     = $Title
            at        = (Get-Date).ToString('o')
            rects     = @{
                sv        = (P $sv)
                opt01     = (P $script:opts['OPT-01'])
                opt28     = (P $script:opts['OPT-28'])
                openPanel = (P $panelBtn)
                panel     = (P $panel)
                panelItem = (P $script:panelItems['PANEL-18'])
                cbo       = (P $cbo)
                tagInput  = (P $tag)
                tagList   = (P $tagList)
                load      = (P $loadBtn)
                clip      = (P $clipBorder)
                clipText  = (P $clipText)
            }
            events    = $eventsFile
        }
        [IO.File]::WriteAllText($OutFile, ($obj | ConvertTo-Json -Compress -Depth 6), $utf8)
    } catch {
        $msg = ($_.Exception.Message -replace '"', "'") -replace "\r?\n", ' '
        [IO.File]::WriteAllText($errFile, $msg, $utf8)
        $bad = '{"ok":false,"code":"FIXTURE_LOAD_FAIL","msg":"' + $msg + '"}'
        [IO.File]::WriteAllText($OutFile, $bad, $utf8)
    }
})

[void]$win.ShowDialog()
