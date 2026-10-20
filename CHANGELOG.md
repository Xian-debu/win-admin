# Changelog

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循语义化版本。首个正式版在 M5 冻结为 1.0.0；此前 0.x 不承诺接口稳定。

## [0.3.0] - 2026-10-21

### Added
- 复合操作层 `ops/`：`open`（启动并等窗口）、`find-and-click`（UIA 语义定位 + 点击中心）、
  `fill`（点击 + 全选 + 粘贴 + UIA 读回校验）、`wait-for`（等窗口或等 UIA 控件）。
  全部默认 dry-run，`--yes` 才注入；全部过 guard 并写审计。
- `win/waopen.ps1`：启动程序并等窗口（进程 pid 或标题匹配），单次桥调用完成。
- `wwin focus`（双线程 attach 抢前台，不产生合成输入）/ `wwin close`（PostMessage WM_CLOSE，脏文档交给应用）。
- `SKILL.md`（L4 技能：红线 / 授权 / 原语表 / 五步配方 / 坑表 / 拒绝条件）+ `scripts/install-skill.sh`。
- 验收 `tests/check-m4.sh`（13 项：N1-N6 阴性 + C8-1…C8-6 + E8 三连跑），报告 `tests/reports/2026-10-21-m4.md`。

### Fixed
- `jq --argjson` 不接受 `0x` hwnd（K25）；`$(op_resolve_hwnd)` 吞掉错误 JSON（K26）；
  `waopen.ps1` 缺 `Fail` 导致无 JSON 输出（补本地 Fail + trap，坏程序现在 `ENV_NO_EXE` rc3）。

### Measured
- `ops/open` 564 ms 返回 hwnd；`ops/wait-for --uia-name` 606 ms 命中；
- `ops/fill` 48 字节中文+emoji 读回逐字节一致；端到端（含落盘与关窗）8.2–9.0 s，3/3 连过。

## [0.2.0] - 2026-10-21

### Added
- M2 输入原语：`winput`（move/click/dclick/drag/key/type，默认 dry-run，真实注入需 `--yes`）、
  `wclip`（get/set/clear，写后回读校验）、`wwait`（窗口出现轮询）、`wuia --value`（回读控件内容）、`wwin info`。
- M3 守卫层：`guard/grant.sh`（issue/status/revoke/pause/resume）、`guard/check.sh`（scope/过期/撤销/pause/验签）、
  `lib/audit.sh`（一行一动作，写失败 fail closed）、`grant.json` 签名（`GUARD_TAMPERED`）。
- 拒绝码：`SESSION_LOCKED`、`UAC_SECURE_DESKTOP`；只能更严格的桌面测试钩子（SG-0002）。
- 验收：`tests/check-m2.sh`（11 项）、`tests/check-m3.sh`（20 项）、自带 WPF 测试窗、`pixdiff.py`。

### Fixed
- `Out-Plan | Out-Null` 吞掉 dry-run JSON（K15）；`-split '+'` 的正则转义错误；
- 事件处理器看不到外层局部变量（改 `$script:`，K16）；`$env:WA_VERSION` 设置顺序导致错误 JSON 报 unknown；
- guard 拒绝路径绕过审计（K20）。
