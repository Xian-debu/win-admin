param(
    [string]$Core = '',
    [string]$Version = 'unknown',
    [switch]$List,
    [long]$Hwnd = 0,
    [int]$Depth = 3,
    [int]$MaxNodes = 400,
    [string]$Filter = '',
    [string]$Title = ''
)
$env:WA_VERSION = $Version
if (-not $Core) { $Core = Join-Path $PSScriptRoot 'lib/wa-core.ps1' }
. $Core

try {
    [void](Set-WaDpi)
    if ($List) {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $cond = [System.Windows.Automation.Condition]::TrueCondition
        $children = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
        $items = New-Object System.Collections.ArrayList
        foreach ($c in $children) {
            try {
                $r = $c.Current.BoundingRectangle
                [void]$items.Add([ordered]@{
                    hwnd  = ('0x{0:x}' -f $c.Current.NativeWindowHandle)
                    name  = $c.Current.Name
                    class = $c.Current.ClassName
                    pid   = $c.Current.ProcessId
                    rect  = [ordered]@{ x = [int]$r.X; y = [int]$r.Y; w = [int]$r.Width; h = [int]$r.Height }
                    offscreen = $c.Current.IsOffscreen
                })
            } catch { }
        }
        Out-WaJson ([ordered]@{ ok = $true; mode = 'list'; count = $items.Count; windows = $items })
        exit 0
    }

    if (-not $Hwnd -and -not $Title) {
        Write-WaFail 'ARG_NEED_TARGET' 'provide -Hwnd, -Title or -List'
        exit 2
    }

    if ($Title) {
        $target = $null
        $wins = @(Get-WaTopWindows)
        foreach ($w in $wins) {
            if ($w.title -match $Title) { $target = $w; break }
        }
        if (-not $target) {
            Write-WaFail 'ENV_NO_WINDOW' "no window title matches: $Title"
            exit 3
        }
        $Hwnd = [long]$target.hwnd_dec
    }

    if (-not [Wa.Native]::IsWindow([IntPtr]$Hwnd)) {
        Write-WaFail 'ENV_NO_WINDOW' "not a window handle: $Hwnd"
        exit 3
    }
    $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
    if (-not $el) {
        Write-WaFail 'ENV_NO_WINDOW' "no UIA element for hwnd $Hwnd"
        exit 3
    }
    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
    $script:nodes = New-Object System.Collections.ArrayList
    $script:truncated = $false
    $re = if ($Filter) { [regex]$Filter } else { $null }

    function Add-WaNode($e, $d) {
        if ($script:nodes.Count -ge $MaxNodes) { $script:truncated = $true; return }
        try {
            $r = $e.Current.BoundingRectangle
            $name = $e.Current.Name
            $emit = $true
            if ($re -and -not ($name -match $re)) { $emit = $false }
            if ($emit) {
                [void]$script:nodes.Add([ordered]@{
                    depth = $d
                    name  = $name
                    type  = $e.Current.ControlType.ProgrammaticName
                    aid   = $e.Current.AutomationId
                    class = $e.Current.ClassName
                    rect  = [ordered]@{ x = [int]$r.X; y = [int]$r.Y; w = [int]$r.Width; h = [int]$r.Height }
                    enabled = $e.Current.IsEnabled
                    offscreen = $e.Current.IsOffscreen
                })
            }
        } catch { return }
        if ($d -ge $Depth) { return }
        $child = $walker.GetFirstChild($e)
        while ($child) {
            Add-WaNode $child ($d + 1)
            if ($script:truncated) { return }
            $child = $walker.GetNextSibling($child)
        }
    }

    Add-WaNode $el 0
    Out-WaJson ([ordered]@{
        ok        = $true
        mode      = 'tree'
        hwnd      = ('0x{0:x}' -f $Hwnd)
        depth     = $Depth
        maxNodes  = $MaxNodes
        count     = $script:nodes.Count
        truncated = $script:truncated
        nodes     = $script:nodes
    })
    exit 0
} catch {
    Write-WaFail 'EXEC_FAIL' $_.Exception.Message
    exit 5
}
