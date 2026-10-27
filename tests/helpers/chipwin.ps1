param(
    [string]$Title = 'wa-chips',
    [string]$OutFile = 'C:/Users/Public/win-admin/tmp/chipwin.json',
    [string]$EventsFile = 'C:/Users/Public/win-admin/tmp/chipwin-events.txt',
    [switch]$SwallowFirst,
    [switch]$SwallowAll,
    [int]$ReadyAfterMs = 1200
)
# tests/helpers/chipwin.ps1 - serial-entry fixture for T31 (v1.4).
# Three things that only show up on real editors, reproduced without a browser:
#   * chip input: type a tag, press Enter -> a ListBox item named exactly the tag appears;
#     -SwallowFirst drops the first Enter (the "keystroke eaten" case ops/chip-add must retry),
#     -SwallowAll drops every Enter (the case that must fail loudly, never silently);
#   * rich editor: a RichTextBox with TextPattern, so ops/rich-write can prove the paste landed;
#   * readiness: a READY-MARK element appears after ReadyAfterMs - before that only WAITING-MARK
#     exists, which is exactly what ops/wait-ready has to poll for.
# Observable state: the title reads 'chipwin chips=<n> ready=<0|1> swallow=<none|first|all>',
# each event is appended to the events file, and the loaded JSON reports the chosen modes.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
Add-Type -Namespace WaTest6 -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
'@ | Out-Null
try { [WaTest6.Dpi]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null } catch { }

$mode = 'none'
if ($SwallowAll) { $mode = 'all' } elseif ($SwallowFirst) { $mode = 'first' }

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($EventsFile, '', $utf8)
function Log([string]$line) { [IO.File]::AppendAllText($EventsFile, ($line + [char]10), $utf8) }

# GetNewClosure() snapshots variables into the closure, so a scalar written inside an event
# handler would never be visible again. A hashtable is a reference: every handler sees the same
# state object (K: fixture state that outlives one event must not be a script-scope scalar).
$st = @{ ready = 0; swallowFirst = [bool]$SwallowFirst; swallowAll = [bool]$SwallowAll; swallowedOnce = $false }

$win = New-Object System.Windows.Window
$win.Width = 640
$win.Height = 780
$win.WindowStartupLocation = 'CenterScreen'

$root = New-Object System.Windows.Controls.StackPanel
$root.Margin = New-Object System.Windows.Thickness(12)

$hdr = New-Object System.Windows.Controls.TextBlock
$hdr.Text = 'CHIP-TITLE'
$hdr.Height = 24
$root.Children.Add($hdr) | Out-Null

$lb = New-Object System.Windows.Controls.ListBox
$lb.Height = 132
[System.Windows.Automation.AutomationProperties]::SetName($lb, 'chip-list')
[System.Windows.Automation.AutomationProperties]::SetAutomationId($lb, 'chip-list')
foreach ($c in @('TAG-00', 'TAG-01')) { [void]$lb.Items.Add($c) }
$root.Children.Add($lb) | Out-Null

$tb = New-Object System.Windows.Controls.TextBox
$tb.Height = 30
$tb.Margin = New-Object System.Windows.Thickness(0, 6, 0, 6)
[System.Windows.Automation.AutomationProperties]::SetName($tb, 'CHIP-INPUT')
[System.Windows.Automation.AutomationProperties]::SetAutomationId($tb, 'chip-input')
$root.Children.Add($tb) | Out-Null

$rtb = New-Object System.Windows.Controls.RichTextBox
$rtb.Height = 150
$rtb.Margin = New-Object System.Windows.Thickness(0, 6, 0, 6)
[System.Windows.Automation.AutomationProperties]::SetName($rtb, 'RICH-BODY')
[System.Windows.Automation.AutomationProperties]::SetAutomationId($rtb, 'rich-editor')
$rtb.Document.Blocks.Clear()
$para = New-Object System.Windows.Documents.Paragraph
$para.Inlines.Add((New-Object System.Windows.Documents.Run('body:initial line')))
$rtb.Document.Blocks.Add($para) | Out-Null
$root.Children.Add($rtb) | Out-Null

$waiting = New-Object System.Windows.Controls.TextBlock
$waiting.Text = 'WAITING-MARK'
$waiting.Height = 24
[System.Windows.Automation.AutomationProperties]::SetName($waiting, 'WAITING-MARK')
[System.Windows.Automation.AutomationProperties]::SetAutomationId($waiting, 'waiting-mark')
$root.Children.Add($waiting) | Out-Null

$readyLbl = New-Object System.Windows.Controls.TextBlock
$readyLbl.Text = 'READY-MARK'
$readyLbl.Height = 24
$readyLbl.Visibility = 'Collapsed'
[System.Windows.Automation.AutomationProperties]::SetName($readyLbl, 'READY-MARK')
[System.Windows.Automation.AutomationProperties]::SetAutomationId($readyLbl, 'ready-mark')
$root.Children.Add($readyLbl) | Out-Null

$win.Content = $root

function Update-Title {
    $win.Title = ('chipwin chips={0} ready={1} swallow={2}' -f $lb.Items.Count, $st.ready, $mode)
}
Update-Title

$tb.Add_KeyDown({
    param($s, $e)
    if ($e.Key -ne 'Enter') { return }
    $e.Handled = $true
    if ($st.swallowAll) { Log 'enter-swallowed-all'; return }
    if ($st.swallowFirst -and -not $st.swallowedOnce) {
        $st.swallowedOnce = $true
        Log 'enter-swallowed-first'
        return
    }
    $t = $tb.Text.Trim()
    if (-not $t) { Log 'enter-empty'; return }
    [void]$lb.Items.Add($t)
    $tb.Text = ''
    Update-Title
    Log ('chip-add ' + $t)
}.GetNewClosure())

$script:timer = New-Object System.Windows.Threading.DispatcherTimer
$script:timer.Interval = [TimeSpan]::FromMilliseconds($ReadyAfterMs)
$script:timer.Add_Tick({
    $script:timer.Stop()
    $waiting.Visibility = 'Collapsed'
    $readyLbl.Visibility = 'Visible'
    $st.ready = 1
    Update-Title
    Log 'ready'
}.GetNewClosure())

$script:hwnd = [IntPtr]::Zero
$win.Add_Loaded({
    $script:hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
    $chips = @()
    foreach ($it in $lb.Items) { $chips += [string]$it }
    $o = [ordered]@{
        ok = $true
        pid = $PID
        hwnd = ('0x{0:x}' -f [int64]$script:hwnd)
        hwnd_dec = [int64]$script:hwnd
        title = $win.Title
        swallow = $mode
        readyAfterMs = $ReadyAfterMs
        chips = $chips
        rect = @{ x = [int]$win.Left; y = [int]$win.Top; w = [int]$win.Width; h = [int]$win.Height }
    }
    [IO.File]::WriteAllText($OutFile, ($o | ConvertTo-Json -Compress -Depth 5), $utf8)
    Log 'loaded'
    $script:timer.Start()
}.GetNewClosure())

[void]$win.ShowDialog()