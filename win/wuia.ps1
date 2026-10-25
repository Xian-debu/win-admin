<#
  win/wuia.ps1 - UI Automation: list windows, dump a tree, find elements, probe a point, act on an element.

  v1.1 (T5/T6) closes the gap "wuia can only dump a tree": callers had to parse a large JSON blob
  themselves and then guess screen coordinates. Finding is now a first-class query, and every action
  returns the state it read back afterwards (D27: report what happened, not that we tried).
#>
param(
    [string]$Core = '',
    [string]$Version = 'unknown',
    [switch]$List,
    [long]$Hwnd = 0,
    [int]$Depth = -1,
    [int]$MaxNodes = -1,
    [string]$Filter = '',
    [string]$Title = '',
    [switch]$Value,
    # ---- T5: finding ----
    [string]$FindName = '',
    [string]$FindType = '',
    [string]$FindAid = '',
    [string]$FindClass = '',
    [switch]$EnabledOnly,
    [switch]$OnScreenOnly,
    [int]$Index = 0,
    [int]$Limit = 20,
    [int]$PointX = -1,
    [int]$PointY = -1,
    # ---- T6: acting ----
    [string]$Action = '',
    [string]$SetValue = '',
    [switch]$SetValueGiven,
    # ---- T20: tree reliability (v1.3) ----
    [switch]$NoWarm,
    [switch]$NoDeepen,
    [int]$WarmMs = 250,
    [int]$WarmPasses = 3
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:WA_VERSION = $Version
if (-not $Core) { $Core = Join-Path $PSScriptRoot 'lib/wa-core.ps1' }
. $Core
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase | Out-Null

function Get-Rect($e) {
    try {
        $r = $e.Current.BoundingRectangle
        return [ordered]@{ x = [int]$r.X; y = [int]$r.Y; w = [int]$r.Width; h = [int]$r.Height }
    } catch {
        return [ordered]@{ x = 0; y = 0; w = 0; h = 0 }
    }
}

$script:PatternDefs = @(
    @{ name = 'Value';          p = [System.Windows.Automation.ValuePattern]::Pattern },
    @{ name = 'Invoke';         p = [System.Windows.Automation.InvokePattern]::Pattern },
    @{ name = 'SelectionItem';  p = [System.Windows.Automation.SelectionItemPattern]::Pattern },
    @{ name = 'Selection';      p = [System.Windows.Automation.SelectionPattern]::Pattern },
    @{ name = 'ExpandCollapse'; p = [System.Windows.Automation.ExpandCollapsePattern]::Pattern },
    @{ name = 'Toggle';         p = [System.Windows.Automation.TogglePattern]::Pattern },
    @{ name = 'ScrollItem';     p = [System.Windows.Automation.ScrollItemPattern]::Pattern },
    @{ name = 'Text';           p = [System.Windows.Automation.TextPattern]::Pattern }
)

function Get-WaPatterns($e) {
    $names = New-Object System.Collections.ArrayList
    foreach ($d in $script:PatternDefs) {
        $obj = $null
        try { [void]$e.TryGetCurrentPattern($d.p, [ref]$obj) } catch { $obj = $null }
        if ($obj) { [void]$names.Add($d.name) }
    }
    return @($names)
}

function Get-WaPattern($e, [string]$name) {
    foreach ($d in $script:PatternDefs) {
        if ($d.name -ne $name) { continue }
        $obj = $null
        try { [void]$e.TryGetCurrentPattern($d.p, [ref]$obj) } catch { $obj = $null }
        return $obj
    }
    return $null
}

function Get-NodeView($e, [int]$depth) {
    $c = $null
    try { $c = $e.Current } catch { return $null }
    return [ordered]@{
        depth     = $depth
        name      = $c.Name
        type      = $c.ControlType.ProgrammaticName
        aid       = $c.AutomationId
        class     = $c.ClassName
        rect      = (Get-Rect $e)
        enabled   = $c.IsEnabled
        offscreen = $c.IsOffscreen
        focused   = $c.HasKeyboardFocus
        patterns  = @(Get-WaPatterns $e)
    }
}

function Test-WaMatch($view) {
    if ($FindName -and -not ($view.name -match $FindName)) { return $false }
    if ($FindType -and -not ($view.type -match $FindType)) { return $false }
    if ($FindAid -and -not ($view.aid -match $FindAid)) { return $false }
    if ($FindClass -and -not ($view.class -match $FindClass)) { return $false }
    if ($EnabledOnly -and -not $view.enabled) { return $false }
    if ($OnScreenOnly -and $view.offscreen) { return $false }
    return $true
}

function Merge-Ctx($o, $ctx) {
    foreach ($k in $ctx.Keys) { $o[$k] = $ctx[$k] }
    return $o
}

function Write-Fail2([string]$code, [string]$msg, $extra, [int]$exitCode) {
    $o = [ordered]@{ ok = $false; code = $code; msg = $msg; version = $Version }
    if ($null -ne $extra) { foreach ($k in $extra.Keys) { $o[$k] = $extra[$k] } }
    Out-WaJson $o
    exit $exitCode
}

try {
    [void](Set-WaDpi)

    if ($List) {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $children = $root.FindAll(
            [System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition)
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

    # ---- point probe (T5): what sits under this screen coordinate, and what contains it ----
    if ($PointX -ge 0 -and $PointY -ge 0) {
        $pt = New-Object System.Windows.Point($PointX, $PointY)
        $el = $null
        try { $el = [System.Windows.Automation.AutomationElement]::FromPoint($pt) } catch { $el = $null }
        if (-not $el) { Write-Fail2 'ENV_NO_ELEMENT' "no element at $PointX,$PointY" $null 3 }
        $self = Get-NodeView $el 0
        $chain = New-Object System.Collections.ArrayList
        $p = $null
        try { $p = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($el) } catch { $p = $null }
        if (-not $p) {
            try { $p = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($el) } catch { $p = $null }
        }
        $d = 1
        while ($p -and $d -le 6) {
            $v = Get-NodeView $p $d
            if ($v) { [void]$chain.Add($v) }
            $next = $null
            try { $next = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($p) } catch { $next = $null }
            if (-not $next) {
                try { $next = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($p) } catch { $next = $null }
            }
            if (-not $next -or $next -eq $p) { break }
            $p = $next
            $d = $d + 1
        }
        Out-WaJson ([ordered]@{
            ok        = $true
            mode      = 'point'
            point     = [ordered]@{ x = $PointX; y = $PointY }
            element   = $self
            ancestors = $chain
        })
        exit 0
    }

    if (-not $Hwnd -and -not $Title) {
        Write-Fail2 'ARG_NEED_TARGET' 'provide -Hwnd, -Title, -List or -PointX/-PointY' $null 2
    }

    if ($Title) {
        $target = $null
        foreach ($w in @(Get-WaTopWindows)) {
            if ($w.title -match $Title) { $target = $w; break }
        }
        if (-not $target) { Write-Fail2 'ENV_NO_WINDOW' "no window title matches: $Title" $null 3 }
        $Hwnd = [long]$target.hwnd_dec
    }

    if (-not [Wa.Native]::IsWindow([IntPtr]$Hwnd)) {
        Write-Fail2 'ENV_NO_WINDOW' "not a window handle: $Hwnd" $null 3
    }
    $rootEl = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
    if (-not $rootEl) { Write-Fail2 'ENV_NO_WINDOW' "no UIA element for hwnd $Hwnd" $null 3 }

    if ($Value) {
        $script:found = $null
        $script:val = ''
        $script:how = ''
        $script:seen = 0
        function Scan-WaValue($e, $d) {
            if ($script:found -or $script:seen -ge 2000) { return }
            $script:seen = $script:seen + 1
            $vp = Get-WaPattern $e 'Value'
            if ($vp) { $script:found = $e; $script:val = $vp.Current.Value; $script:how = 'value'; return }
            $tp = Get-WaPattern $e 'Text'
            if ($tp) {
                try {
                    $script:val = $tp.DocumentRange.GetText(-1)
                    $script:found = $e; $script:how = 'text'; return
                } catch { }
            }
            if ($d -ge 8) { return }
            $c = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetFirstChild($e)
            while ($c) {
                Scan-WaValue $c ($d + 1)
                if ($script:found) { return }
                $c = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetNextSibling($c)
            }
        }
        Scan-WaValue $rootEl 0
        if (-not $script:found) {
            Write-Fail2 'ENV_NO_VALUE_PATTERN' 'no element under the target supports ValuePattern' $null 3
        }
        $v = $script:found.Current
        Out-WaJson ([ordered]@{
            ok    = $true
            mode  = 'value'
            hwnd  = ('0x{0:x}' -f $Hwnd)
            name  = $v.Name
            type  = $v.ControlType.ProgrammaticName
            aid   = $v.AutomationId
            via   = $script:how
            value = $script:val
            len   = $script:val.Length
        })
        exit 0
    }

    # ---- bounded walk: collects (element, view) pairs; the caller decides what to do with them ----
    #
    # T20 (v1.3): Chromium builds its accessibility tree lazily and every CLI call is a fresh
    # process, so the FIRST walk returns only browser chrome (279 nodes on bilibili.com) while the
    # immediate second one returns the page (561 nodes, depth 13-25). Callers therefore saw
    # "the page DOM never enters the UIA tree". We warm the tree at most WarmPasses times and, for
    # find/action, deepen the walk once when the first pass found nothing (docs/21 F2, docs/22 T20).
    $script:cols = New-Object System.Collections.ArrayList
    $script:truncated = $false
    $re = if ($Filter) { [regex]$Filter } else { $null }
    $findMode = [bool]($FindName -or $FindType -or $FindAid -or $FindClass -or $EnabledOnly -or $OnScreenOnly -or $Action)
    if ($Depth -ge 0) { $depthGiven = $true; $baseDepth = $Depth } else { $depthGiven = $false; $baseDepth = if ($findMode) { 20 } else { 3 } }
    $script:nodeCap = if ($MaxNodes -ge 1) { $MaxNodes } elseif ($findMode) { 4000 } else { 400 }

    function Invoke-WaWalk($rootEl) {
        $script:cols = New-Object System.Collections.ArrayList
        $script:truncated = $false
        $script:emptyDoc = $false
        Walk-WaNode $rootEl 0
    }

    function Walk-WaNode($e, $d) {
        if ($script:cols.Count -ge $script:nodeCap) { $script:truncated = $true; return }
        $view = Get-NodeView $e $d
        if ($view -and (-not $re -or ($view.name -match $re))) {
            [void]$script:cols.Add(@{ el = $e; view = $view })
        }
        $child = $null
        if ($d -lt $script:walkDepth) {
            $child = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetFirstChild($e)
        }
        if ($view -and $view.type -eq 'ControlType.Document' -and -not $child) { $script:emptyDoc = $true }
        while ($child) {
            Walk-WaNode $child ($d + 1)
            if ($script:truncated) { return }
            $child = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetNextSibling($child)
        }
    }

    $warmStart = Get-Date
    $passes = 0
    $warmRetries = 0
    $deepened = $false
    $depthUsed = $baseDepth
    while ($true) {
        $passes = $passes + 1
        $script:walkDepth = $depthUsed
        Invoke-WaWalk $rootEl
        if ($findMode) {
            $hitCount = 0
            foreach ($c in $script:cols) { if (Test-WaMatch $c.view) { $hitCount = $hitCount + 1 } }
            $needMore = $hitCount -eq 0
        } else {
            $needMore = $script:emptyDoc
        }
        if (-not $needMore) { break }
        if ($findMode -and -not $deepened -and -not $NoDeepen -and $depthUsed -lt 28) {
            $depthUsed = [Math]::Max($depthUsed + 8, 28)
            if (-not $depthGiven) { $depthUsed = 28 }
            $deepened = $true
            continue
        }
        if (-not $NoWarm -and $passes -lt $WarmPasses) {
            Start-Sleep -Milliseconds $WarmMs
            $warmRetries = $warmRetries + 1
            continue
        }
        break
    }
    $warmMs = [int]((Get-Date) - $warmStart).TotalMilliseconds

    # ---- T5: find (only when no action was asked for; an action always wins) ----
    if (-not $Action -and ($FindName -or $FindType -or $FindAid -or $FindClass -or $EnabledOnly -or $OnScreenOnly)) {
        $hits = New-Object System.Collections.ArrayList
        foreach ($c in $script:cols) {
            if (Test-WaMatch $c.view) { [void]$hits.Add($c) }
        }
        $out = New-Object System.Collections.ArrayList
        $n = 0
        foreach ($h in $hits) {
            if ($n -ge $Limit) { break }
            [void]$out.Add($h.view); $n = $n + 1
        }
        Out-WaJson ([ordered]@{
            ok        = $true
            mode      = 'find'
            hwnd      = ('0x{0:x}' -f $Hwnd)
            query     = [ordered]@{ name = $FindName; type = $FindType; aid = $FindAid; class = $FindClass; enabled = [bool]$EnabledOnly; onScreen = [bool]$OnScreenOnly }
            scanned   = $script:cols.Count
            truncated = $script:truncated
            passes    = $passes
            warmMs    = $warmMs
            warmRetries = $warmRetries
            depthUsed = $depthUsed
            deepened  = $deepened
            total     = $hits.Count
            count     = $out.Count
            nodes     = $out
        })
        exit 0
    }

    # ---- no action and no find: keep the v1.0.0 tree dump ----
    if (-not $Action) {
        $nodes = New-Object System.Collections.ArrayList
        foreach ($c in $script:cols) { [void]$nodes.Add($c.view) }
        Out-WaJson ([ordered]@{
            ok        = $true
            mode      = 'tree'
            hwnd      = ('0x{0:x}' -f $Hwnd)
            depth     = $depthUsed
            depthUsed = $depthUsed
            maxNodes  = $script:nodeCap
            count     = $nodes.Count
            truncated = $script:truncated
            passes    = $passes
            warmMs    = $warmMs
            warmRetries = $warmRetries
            deepened  = $deepened
            nodes     = $nodes
        })
        exit 0
    }

    # ---- T6: act on one match ----
    if (-not ($FindName -or $FindType -or $FindAid -or $FindClass)) {
        Write-Fail2 'ARG_NEED_FIND' "action '$Action' needs at least one of -FindName/-FindType/-FindAid/-FindClass" $null 2
    }
    $hits = New-Object System.Collections.ArrayList
    foreach ($c in $script:cols) {
        if (Test-WaMatch $c.view) { [void]$hits.Add($c) }
    }
    if ($hits.Count -eq 0) {
        Write-Fail2 'ENV_NO_MATCH' 'no element matches the find criteria' ([ordered]@{
            query = [ordered]@{ name = $FindName; type = $FindType; aid = $FindAid; class = $FindClass }
            scanned = $script:cols.Count
            passes = $passes
            warmMs = $warmMs
            depthUsed = $depthUsed
            deepened = $deepened
        }) 3
    }
    if ($Index -lt 0 -or $Index -ge $hits.Count) {
        Write-Fail2 'ARG_INDEX_OUT_OF_RANGE' "index $Index but only $($hits.Count) match(es)" ([ordered]@{ total = $hits.Count }) 2
    }
    $chosen = $hits[$Index]
    $before = $chosen.view
    $ctx = [ordered]@{
        hwnd  = ('0x{0:x}' -f $Hwnd)
        total = $hits.Count
        index = $Index
        node  = $before
    }
    if ($hits.Count -gt 1) {
        $cands = New-Object System.Collections.ArrayList
        foreach ($h in $hits) {
            [void]$cands.Add([ordered]@{ name = $h.view.name; type = $h.view.type; rect = $h.view.rect })
        }
        $ctx['candidates'] = $cands
    }

    # a disabled control cannot take an injected action: fail deterministically instead of
    # letting the provider throw an opaque COM error at us (K37)
    if (-not $before.enabled -and $Action -notin @('get-value', 'get-text', 'focus')) {
        Write-Fail2 'ENV_DISABLED' "element is disabled; '$Action' would not take effect" ([ordered]@{ action = $Action; node = $before }) 3
    }

    try {
    switch ($Action) {
        'invoke' {
            $pat = Get-WaPattern $chosen.el 'Invoke'
            if (-not $pat) { Write-Fail2 'ENV_NO_PATTERN' 'element does not support Invoke' $ctx 3 }
            $pat.Invoke()
            Start-Sleep -Milliseconds 250
            $o = [ordered]@{ ok = $true; mode = 'action'; action = 'invoke'; injected = $true; state = (Get-NodeView $chosen.el $before.depth) }
            Out-WaJson (Merge-Ctx $o $ctx)
        }
        'select' {
            $pat = Get-WaPattern $chosen.el 'SelectionItem'
            if (-not $pat) { Write-Fail2 'ENV_NO_PATTERN' 'element does not support SelectionItem' $ctx 3 }
            $pat.Select()
            Start-Sleep -Milliseconds 200
            $isSel = $false
            try { $isSel = (Get-WaPattern $chosen.el 'SelectionItem').Current.IsSelected } catch { }
            $o = [ordered]@{ ok = $true; mode = 'action'; action = 'select'; injected = $true; selected = $isSel }
            Out-WaJson (Merge-Ctx $o $ctx)
        }
        'toggle' {
            $pat = Get-WaPattern $chosen.el 'Toggle'
            if (-not $pat) { Write-Fail2 'ENV_NO_PATTERN' 'element does not support Toggle' $ctx 3 }
            $pat.Toggle()
            Start-Sleep -Milliseconds 200
            $st = ''
            try { $st = (Get-WaPattern $chosen.el 'Toggle').Current.ToggleState.ToString() } catch { }
            $o = [ordered]@{ ok = $true; mode = 'action'; action = 'toggle'; injected = $true; toggleState = $st }
            Out-WaJson (Merge-Ctx $o $ctx)
        }
        'expand' {
            $pat = Get-WaPattern $chosen.el 'ExpandCollapse'
            if (-not $pat) { Write-Fail2 'ENV_NO_PATTERN' 'element does not support ExpandCollapse' $ctx 3 }
            $pat.Expand()
            Start-Sleep -Milliseconds 300
            $st = ''
            try { $st = (Get-WaPattern $chosen.el 'ExpandCollapse').Current.ExpandCollapseState.ToString() } catch { }
            $o = [ordered]@{ ok = $true; mode = 'action'; action = 'expand'; injected = $true; expandState = $st }
            Out-WaJson (Merge-Ctx $o $ctx)
        }
        'collapse' {
            $pat = Get-WaPattern $chosen.el 'ExpandCollapse'
            if (-not $pat) { Write-Fail2 'ENV_NO_PATTERN' 'element does not support ExpandCollapse' $ctx 3 }
            $pat.Collapse()
            Start-Sleep -Milliseconds 300
            $st = ''
            try { $st = (Get-WaPattern $chosen.el 'ExpandCollapse').Current.ExpandCollapseState.ToString() } catch { }
            $o = [ordered]@{ ok = $true; mode = 'action'; action = 'collapse'; injected = $true; expandState = $st }
            Out-WaJson (Merge-Ctx $o $ctx)
        }
        'focus' {
            $chosen.el.SetFocus()
            Start-Sleep -Milliseconds 150
            $after = Get-NodeView $chosen.el $before.depth
            if (-not $after.focused) {
                Write-Fail2 'ENV_STATE_UNCHANGED' 'element did not report keyboard focus after SetFocus' ([ordered]@{ node = $after }) 3
            }
            $o = [ordered]@{ ok = $true; mode = 'action'; action = 'focus'; injected = $true; state = $after }
            Out-WaJson (Merge-Ctx $o $ctx)
        }
        'set-value' {
            if (-not $SetValueGiven) { Write-Fail2 'ARG_NEED_VALUE' 'set-value needs -SetValue (pass -SetValueGiven to write an empty string)' $ctx 2 }
            $pat = Get-WaPattern $chosen.el 'Value'
            if (-not $pat) { Write-Fail2 'ENV_NO_PATTERN' 'element does not support ValuePattern' $ctx 3 }
            $pat.SetValue($SetValue)
            Start-Sleep -Milliseconds 250
            $read = ''
            try { $read = (Get-WaPattern $chosen.el 'Value').Current.Value } catch { $read = '' }
            if ($read -ne $SetValue) {
                Write-Fail2 'ENV_STATE_UNCHANGED' 'value did not stick' ([ordered]@{ wrote = $SetValue; read = $read; node = $before }) 3
            }
            $o = [ordered]@{ ok = $true; mode = 'action'; action = 'set-value'; injected = $true; value = $read }
            Out-WaJson (Merge-Ctx $o $ctx)
        }
        'get-text' {
            $tp = Get-WaPattern $chosen.el 'Text'
            if (-not $tp) {
                # WPF TextBlock (and several other providers) expose no TextPattern even though the
                # visible string is the element Name. Fall back to Name and say so in 'via' (K38).
                if ($before.name) {
                    $o = [ordered]@{ ok = $true; mode = 'action'; action = 'get-text'; via = 'name'; value = $before.name; len = $before.name.Length }
                    Out-WaJson (Merge-Ctx $o $ctx)
                }
                Write-Fail2 'ENV_NO_PATTERN' 'element supports neither TextPattern nor a non-empty Name' $ctx 3
            }
            $txt = ''
            try { $txt = $tp.DocumentRange.GetText(-1) } catch { $txt = '' }
            $o = [ordered]@{ ok = $true; mode = 'action'; action = 'get-text'; via = 'text'; value = $txt; len = $txt.Length }
            Out-WaJson (Merge-Ctx $o $ctx)
        }
        'get-value' {
            $pat = Get-WaPattern $chosen.el 'Value'
            if ($pat) {
                $o = [ordered]@{ ok = $true; mode = 'action'; action = 'get-value'; via = 'value'; value = $pat.Current.Value }
                Out-WaJson (Merge-Ctx $o $ctx)
                exit 0
            }
            $tp = Get-WaPattern $chosen.el 'Text'
            if (-not $tp) { Write-Fail2 'ENV_NO_PATTERN' 'element supports neither ValuePattern nor TextPattern' $ctx 3 }
            $txt = ''
            try { $txt = $tp.DocumentRange.GetText(-1) } catch { $txt = '' }
            $o = [ordered]@{ ok = $true; mode = 'action'; action = 'get-value'; via = 'text'; value = $txt }
            Out-WaJson (Merge-Ctx $o $ctx)
        }
        default { Write-Fail2 'ARG_BAD_ACTION' "unknown action: $Action" $ctx 2 }
    }
    } catch {
        Write-Fail2 'ENV_ACTION_FAILED' $_.Exception.Message ([ordered]@{ action = $Action; node = $before }) 3
    }
    exit 0
} catch {
    Write-WaFail 'EXEC_FAIL' $_.Exception.Message
    exit 5
}