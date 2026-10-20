param(
    [string]$Title = 'wa-testwin',
    [int]$W = 600,
    [int]$H = 460,
    [string]$OutFile = 'C:/Users/Public/win-admin/tmp/testwin.json'
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
Add-Type -Namespace WaTest -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
'@ | Out-Null
try { [WaTest.Dpi]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null } catch { }

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$textFile = Join-Path $dir 'testwin-text.txt'
$keysFile = Join-Path $dir 'testwin-keys.txt'
$clickFile = Join-Path $dir 'testwin-clicks.txt'
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($clickFile, '', $utf8)
[IO.File]::WriteAllText($textFile, '', $utf8)

$win = New-Object System.Windows.Window
$win.Title = $Title
$win.Width = $W
$win.Height = $H
$win.WindowStartupLocation = 'CenterScreen'

$grid = New-Object System.Windows.Controls.Grid
$r1 = New-Object System.Windows.Controls.RowDefinition
$r1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$r2 = New-Object System.Windows.Controls.RowDefinition
$r2.Height = New-Object System.Windows.GridLength(56)
[void]$grid.RowDefinitions.Add($r1)
[void]$grid.RowDefinitions.Add($r2)

$tb = New-Object System.Windows.Controls.TextBox
$tb.AcceptsReturn = $true
$tb.TextWrapping = 'Wrap'
$tb.FontFamily = 'Consolas'
$tb.FontSize = 16
$tb.VerticalScrollBarVisibility = 'Auto'
[System.Windows.Controls.Grid]::SetRow($tb, 0)
$grid.Children.Add($tb) | Out-Null

$btn = New-Object System.Windows.Controls.Button
$btn.Content = 'CLICK-TARGET'
$btn.FontSize = 16
[System.Windows.Controls.Grid]::SetRow($btn, 1)
$grid.Children.Add($btn) | Out-Null
$win.Content = $grid

$script:n = 0
$btn.Add_Click({
    $script:n = $script:n + 1
    [IO.File]::AppendAllText($clickFile, ("$($script:n) " + (Get-Date).ToString('HH:mm:ss.fff') + [char]10), $utf8)
})
$tb.add_TextChanged({ [IO.File]::WriteAllText($textFile, $tb.Text, $utf8) })
$tb.Add_KeyDown({ param($s, $e) [IO.File]::AppendAllText($keysFile, ($e.Key.ToString() + '(' + [System.Windows.Input.Keyboard]::Modifiers.ToString() + ') '), $utf8) })

$win.Add_Loaded({
    $helper = New-Object System.Windows.Interop.WindowInteropHelper -ArgumentList $win
    $h = $helper.Handle
    $win.UpdateLayout()
    $ep = $tb.PointToScreen((New-Object System.Windows.Point(0, 0)))
    $bp = $btn.PointToScreen((New-Object System.Windows.Point(0, 0)))
    $obj = @{
        kind        = 'wpf'
        hwnd        = ('0x' + $h.ToInt64().ToString('x'))
        hwnd_dec    = $h.ToInt64()
        pid         = $PID
        title       = $Title
        at          = (Get-Date).ToString('o')
        at_epoch_ms = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
        edit        = @{ x = [int]$ep.X; y = [int]$ep.Y; w = [int]$tb.ActualWidth; h = [int]$tb.ActualHeight }
        button      = @{ x = [int]$bp.X; y = [int]$bp.Y; w = [int]$btn.ActualWidth; h = [int]$btn.ActualHeight }
    }
    [IO.File]::WriteAllText($OutFile, ($obj | ConvertTo-Json -Compress), $utf8)
    $tb.Focus() | Out-Null
})
$win.ShowDialog() | Out-Null
