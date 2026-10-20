#!/usr/bin/env bash
# inventory/scripts/probe-env.sh — 只读环境探测，复现 docs/02 的全部数字
# 用法: bash inventory/scripts/probe-env.sh [输出文件]
# 约束: 不改系统状态。唯一临时文件 /mnt/c/Users/Public/win-admin/tmp/probe.png，探测后立即删除。
# 注: PowerShell 侧一律走 winps 的 stdin 模式（BOM 化 ps1 -> -File），避免多层引号。
set -uo pipefail
OUT="${1:-/root/win-admin/inventory/raw/$(date +%F)-probe.txt}"
pss() { winps -t 40 - 2>&1; }   # 从 stdin 读 ps1

mkdir -p "$(dirname "$OUT")" /mnt/c/Users/Public/win-admin/tmp

{
echo "# probe-env $(date -Iseconds)"
echo
echo "## 1 WSL 侧"
echo "kernel: $(uname -r)"
echo "host:   $(hostname)"
echo "distro: $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "DISPLAY=[${DISPLAY:-}] WAYLAND=[${WAYLAND_DISPLAY:-}]"
echo "/mnt/c 挂载: $(mount | grep -c ' /mnt/c ') 条"
echo "tools: powershell.exe=$(command -v powershell.exe || echo MISSING)  winps=$(command -v winps || echo MISSING)"
echo
echo "## 2 Windows 基础"
pss <<'EOF'
Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber | ConvertTo-Json -Compress
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,UserName | ConvertTo-Json -Compress
EOF
echo
echo "## 3 显示与 DPI"
pss <<'EOF'
Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution | ConvertTo-Json -Compress
EOF
pss <<'EOF'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
  [pscustomobject]@{ Device=$_.DeviceName; Primary=$_.Primary; Bounds=("{0}x{1}@{2},{3}" -f $_.Bounds.Width,$_.Bounds.Height,$_.Bounds.X,$_.Bounds.Y) }
} | ConvertTo-Json -Compress
EOF
pss <<'EOF'
Add-Type -AssemblyName System.Windows.Forms
$v=[System.Windows.Forms.SystemInformation]::VirtualScreen
[pscustomobject]@{ VirtualScreen=("{0}x{1}" -f $v.Width,$v.Height) } | ConvertTo-Json -Compress
EOF
echo
echo "## 4 会话"
pss <<'EOF'
$me=Get-Process -Id $PID
[pscustomobject]@{ SessionId=$me.SessionId; ExplorerSession=((Get-Process explorer -ErrorAction SilentlyContinue | Select-Object -First 1).SessionId) } | ConvertTo-Json -Compress
EOF
echo
echo "## 5 截图能力（临时文件，探测后删除）"
pss <<'EOF'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$b=[System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp=New-Object System.Drawing.Bitmap $b.Width,$b.Height
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left,$b.Top,0,0,$bmp.Size)
$p='C:\Users\Public\win-admin\tmp\probe.png'
$bmp.Save($p,[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
[pscustomobject]@{ w=[int]$b.Width; h=[int]$b.Height; file=$p } | ConvertTo-Json -Compress
EOF
if [ -f /mnt/c/Users/Public/win-admin/tmp/probe.png ]; then
  echo "shot_bytes: $(stat -c%s /mnt/c/Users/Public/win-admin/tmp/probe.png)"
  rm -f /mnt/c/Users/Public/win-admin/tmp/probe.png
fi
echo
echo "## 6 UI Automation 顶层窗口"
pss <<'EOF'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$r=[System.Windows.Automation.AutomationElement]::RootElement
$c=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window)
$w=[System.Windows.Automation.TreeScope]::Children
$all=$r.FindAll($w,$c)
[pscustomobject]@{ count=$all.Count; names=@($all | ForEach-Object { $_.Current.Name }) } | ConvertTo-Json -Compress
EOF
echo
echo "## 7 Windows Python 与 PIL"
pss <<'EOF'
$py='C:\Users\ZYX\AppData\Local\Programs\Python\Python311\python.exe'
if (Test-Path $py) { & $py -c "import sys,PIL;print('py',sys.version.split()[0],'PIL',PIL.__version__)" } else { 'python.exe MISSING' }
EOF
echo
echo "## 8 完成"
echo "cwd: $(pwd)"
} > "$OUT" 2>&1
echo "written: $OUT"
