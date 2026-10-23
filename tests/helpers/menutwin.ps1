param(
    [string]$Title = 'wa-menutwin',
    [string]$OutFile = 'C:/Users/Public/win-admin/tmp/menutwin.json'
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
Add-Type -Namespace WaTest2 -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
'@ | Out-Null
try { [WaTest2.Dpi]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null } catch { }

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$menuFile = Join-Path $dir 'menutwin-menu.txt'
$scrollFile = Join-Path $dir 'menutwin-scroll.txt'
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($menuFile, '', $utf8)
[IO.File]::WriteAllText($scrollFile, '0 0', $utf8)

$win = New-Object System.Windows.Window
$win.Title = $Title
$win.Width = 640
$win.Height = 560
$win.WindowStartupLocation = 'CenterScreen'

$root = New-Object System.Windows.Controls.StackPanel
$root.Margin = New-Object System.Windows.Thickness(8)

# Hover menu: nothing appears until the pointer enters MENU-ROOT (the c0 "分区分级菜单" shape).
$btnMenu = New-Object System.Windows.Controls.Button
$btnMenu.Content = 'MENU-ROOT'
$btnMenu.Width = 200
$btnMenu.Height = 40
$btnMenu.HorizontalAlignment = 'Left'
$root.Children.Add($btnMenu) | Out-Null

$sub = New-Object System.Windows.Controls.StackPanel
$sub.Visibility = 'Collapsed'
$sub.Margin = New-Object System.Windows.Thickness(20, 2, 0, 6)
$s1 = New-Object System.Windows.Controls.Button
$s1.Content = 'SUB-ONE'
$s1.Width = 180
$s1.Height = 32
$s2 = New-Object System.Windows.Controls.Button
$s2.Content = 'SUB-TWO'
$s2.Width = 180
$s2.Height = 32
$sub.Children.Add($s1) | Out-Null
$sub.Children.Add($s2) | Out-Null
$root.Children.Add($sub) | Out-Null

$scroll = New-Object System.Windows.Controls.ScrollViewer
$scroll.Height = 300
$scroll.VerticalScrollBarVisibility = 'Auto'
$inner = New-Object System.Windows.Controls.StackPanel
for ($i = 1; $i -le 30; $i++) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = "item $i"
    $tb.Height = 22
    $inner.Children.Add($tb) | Out-Null
}
$deep = New-Object System.Windows.Controls.Button
$deep.Content = 'DEEP-TARGET'
$deep.Width = 200
$deep.Height = 34
$inner.Children.Add($deep) | Out-Null
$scroll.Content = $inner
$root.Children.Add($scroll) | Out-Null
$win.Content = $root

# The submenu rects are only meaningful once the submenu is visible, so the info JSON is
# re-written on every reveal (tests read the refreshed file).
function Write-Info {
    $win.UpdateLayout()
    $helper = New-Object System.Windows.Interop.WindowInteropHelper -ArgumentList $win
    $h = $helper.Handle
    function Get-Rect($el) {
        $p = $el.PointToScreen((New-Object System.Windows.Point(0, 0)))
        @{ x = [int]$p.X; y = [int]$p.Y; w = [int]$el.ActualWidth; h = [int]$el.ActualHeight }
    }
    $obj = @{
        kind     = 'menutwin'
        hwnd     = ('0x' + $h.ToInt64().ToString('x'))
        hwnd_dec = $h.ToInt64()
        pid      = $PID
        title    = $Title
        at       = (Get-Date).ToString('o')
        menu     = @{ root = (Get-Rect $btnMenu); sub1 = (Get-Rect $s1); sub2 = (Get-Rect $s2); visible = ($sub.Visibility -eq 'Visible') }
        scroll   = (Get-Rect $scroll)
        deep     = (Get-Rect $deep)
    }
    [IO.File]::WriteAllText($OutFile, ($obj | ConvertTo-Json -Compress), $utf8)
}

$btnMenu.Add_MouseEnter({
    [IO.File]::AppendAllText($menuFile, ("shown " + (Get-Date).ToString('HH:mm:ss.fff') + [char]10), $utf8)
    $sub.Visibility = 'Visible'
    Write-Info
})
$scroll.Add_ScrollChanged({
    [IO.File]::WriteAllText($scrollFile, ("{0} {1}" -f [int]$scroll.VerticalOffset, [int]$scroll.HorizontalOffset), $utf8)
})

$win.Add_Loaded({ Write-Info })
$win.ShowDialog() | Out-Null