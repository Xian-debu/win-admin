# Changelog

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循语义化版本。首个正式版在 M5 冻结为 1.0.0；此前 0.x 不承诺接口稳定。

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

### Notes
- 输入注入代码只允许存在于 `bin/winput` + `win/winput.ps1`（D14 静态守护）。
- 单次原语经 winps 桥约 600–750 ms；真实任务需要 M4 的复合操作。
## [0.1.0] - 2026-10-21

### Added
- 双包部署工程：WSL 侧 P1（`bin/ guard/ lib/ tests/`）+ Windows 侧载荷 P2（`win/`），
  P2 装到 `C:/Users/Public/win-admin/app/<version>/`，用 `current.txt` 指针切换版本。
- `scripts/bootstrap.sh`（体检 → 拷贝 → 哈希校验 → 写指针 → 冒烟）、
  `scripts/rollback.sh`、`scripts/uninstall.sh`、`scripts/build-release.sh`。
- M1 只读原语：`wdiag`、`wshot`、`wuia`、`wwin list`；共享库 `lib/common.sh`、`win/lib/wa-core.ps1`。
- `tests/check-m1.sh` 与 `tests/reports/2026-10-21-m1.md`。

### Notes
- 本版本不包含任何输入注入代码（D14）：`winput` 在 M1 验收通过后才出现。
- Windows 侧无安装器、无常驻进程、无第三方依赖，卸载 = 删目录。

## [0.0.1] - 2026-10-20

### Added
- 工程骨架与九份文档（目的、环境、插件审计、能力矩阵、架构、决策、验收、规范、路线图）。
- 环境实测探针 `inventory/scripts/probe-env.sh` 与两份原始记录。
