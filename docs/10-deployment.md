# 10 · 部署包与运维

> 目标：**克隆即得、一条命令装好、可复现、可回滚、可卸载**。
> 本文件只描述“怎么装、怎么验、怎么退”，设计理由见 `docs/06`（D3/D13），已知坑见 `docs/11`。

## 1. 为什么是两个包

WSL 与 Windows 是隔离的执行环境。仓库在 WSL 的 ext4 上（`/root/win-admin`），
**Windows 的 `powershell.exe` 读不到这个路径**，只能读 `/mnt/c` 及 Windows 盘符。
因此拆成两个可独立发布、独立安装的包：

| 包 | 目录 | 安装位置 | 由谁执行 | 卸载 |
|---|---|---|---|---|
| **P1 `win-admin`**（WSL 侧 CLI） | `bin/ guard/ lib/ tests/ scripts/ docs/` | 任意 WSL 路径（当前 `/root/win-admin`） | DSH agent 在 WSL 里 | `rm -rf` 仓库目录 |
| **P2 `win-admin-win`**（Windows 载荷） | `win/` | `C:/Users/Public/win-admin/app/<version>/` | `winps` → `powershell.exe` | `scripts/uninstall.sh` |

P2 的硬约束（D3）：**无常驻、无安装器、无第三方依赖、只在被调用的瞬间存在**。
因此它不会在开机项、服务、注册表里留下任何东西。

## 2. 安装布局

```
C:/Users/Public/win-admin/          <- 唯一写入点（D3）
├── app/
│   ├── 0.1.0/                      <- 每个版本一个目录，升级不覆盖
│   │   ├── wdiag.ps1 wshot.ps1 wuia.ps1 wwin.ps1
│   │   ├── lib/wa-core.ps1
│   │   └── MANIFEST.sha256         <- 安装后校验用
│   └── 0.1.1/
├── current.txt                     <- 活动版本号，回滚 = 改这一行
├── tmp/                            <- winps 的临时目录（WINPS_TMPDIR）
├── shots/                          <- 截图默认输出
└── logs/                           <- 安装/卸载日志
```

WSL 侧不保存 Windows 副本，`bin/*` 每次启动都通过 `lib/common.sh` 解析：

```
WINADMIN_APP_DIR=/mnt/c/Users/Public/win-admin
→ 读 current.txt → $WINADMIN_APP_DIR/app/<ver>/
```

找不到时报 `{"ok":false,"code":"ENV_NOT_INSTALLED"}`（退出码 3），并提示执行 `scripts/bootstrap.sh`，
不静默降级。

## 3. 版本号

- 单一真源：仓库根 `VERSION`（`MAJOR.MINOR.PATCH`）。
- `CHANGELOG.md` 首条必须与 `VERSION` 一致（`scripts/check-release.sh` 强制）。
- 0.x = 开发期，接口可变；M5 冻结 1.0.0。
- P2 目录名 = 版本号，因此“同一台机器上同时存在多个版本”是常态，回滚不需要重新拷贝。

## 4. 命令

| 场景 | 命令 | 说明 |
|---|---|---|
| 体检（不改任何东西） | `bash scripts/bootstrap.sh --check` | 检查 winps / powershell / `/mnt/c` 可写 / 磁盘余量 |
| 安装 / 升级 | `bash scripts/bootstrap.sh` | 拷贝载荷 → 逐文件校验 sha256 → 写 `current.txt` → 冒烟 `wdiag` |
| 回滚到上一版 | `bash scripts/rollback.sh --previous` | 只改 `current.txt`，不删当前版本 |
| 回滚到指定版 | `bash scripts/rollback.sh 0.1.0` | 版本目录不存在则报错，不猜 |
| 卸载 | `bash scripts/uninstall.sh --yes` | 删 `C:/Users/Public/win-admin` 整个目录；审计与授权记录在 `~/.dsh/win-admin/`，另行确认 |
| 构建发布物 | `bash scripts/build-release.sh` | 产出 `dist/` 两包 + `SHA256SUMS` |
| 校验发布文件 | `bash scripts/check-release.sh` | 版本/C 文档/禁用词/敏感关键字静态检查 |

## 5. 安装时的完整性校验

`bootstrap.sh` 在拷贝后**逐文件**比对仓库内计算出的 sha256 与落盘文件的 sha256，
结果写入 `app/<ver>/MANIFEST.sha256` 并进入 `logs/install-<ts>.log`。
任何一条不匹配 → 立即退出码 5，**不写 `current.txt`**（保证“装坏不生效”，仍可用旧版本）。

## 6. 可复现构建

`build-release.sh` 的两条原则：

1. 归档内文件顺序固定（按路径排序），mtime 固定为 `SOURCE_DATE_EPOCH`（缺省为 `VERSION` 的提交时间），
   因此同一提交连续构建两次，`SHA256SUMS` 逐行一致（E12）。
2. 只打包**入库文件**（`git ls-files`），临时截图、`dist/`、`*.log` 一律排除。

产物：

```
dist/
├── win-admin-<ver>.tar.gz         # P1
├── win-admin-win-<ver>.zip        # P2（Windows 用户可直接解压到 app/<ver>/）
└── SHA256SUMS
```

## 7. 迁移到另一台机器（或重装系统）

1. `git clone <repo> && cd win-admin`
2. 确认 `winps` 与 `powershell.exe` 可用（`bash scripts/bootstrap.sh --check`）。
3. `bash scripts/bootstrap.sh` → 自动把 P2 部署到新机器的 `C:/Users/Public/win-admin/`。
4. `bash tests/check-m1.sh` 复验；判据不绿不得当“装好了”。

> P2 **不入库、不进备份**：它随时可以由 P1 重建。备份只需备份仓库 + 审计/授权目录 `~/.dsh/win-admin/`。

## 8. 发布清单（v1.0.0 实测记录 2026-10-21）

- [x] 全部判据全绿：`bash tests/check-m5.sh` → m1 17/0、m2 11/0、m3 20/0、m4 13/0、release yes、E8 10/10
- [x] `scripts/check-release.sh` 退出 0（`SUMMARY pass=yes`）
- [x] `VERSION` = `CHANGELOG` 首条 = `v1.0.0`（check-release 第 1 项守护）
- [x] 干净目录复演（**用发布物本身，不用仓库**）：
      `tar -xzf dist/win-admin-1.0.0.tar.gz -C /tmp/pkg-verify` → `bootstrap.sh --force`（SMOKE PASS，version=1.0.0）
      → `tests/check-m1.sh` **17/0**（skip 14）→ `check-release.sh` **pass=yes**，共 73 个文件
- [x] 报告：`tests/reports/2026-10-21-m5.md`

### 本次发布物

```
dist/win-admin-1.0.0.tar.gz        120,742 B  61f03ed3e95edbbf3ea8697c413766a217539591b73326670e30315d7fa6e968
dist/win-admin-win-1.0.0.zip        13,901 B  a1efc2cb76c22878d5b37262597cbdc884f3be81048f0825e07633bc3da93724
```

> 2026-10-21T01:38 重冻结：K34/K35 两个测试缺陷修复后重新 `build-release`（P1 由 117,729 B 变为 120,742 B，P2 未变——载荷一行没动），`v1.0.0` 标签随之指到新 HEAD。
> 版本号不变：能力面零改动，改的是验收脚本与文档。`dist/` 不入库，SHA256 以本节为准。

P1 是完整仓库快照（文档 + bash 原语 + 测试）；P2 是 Windows 侧 9 个 `.ps1` 载荷，供不想跑
`bootstrap.sh` 的人手工铺到 `C:/Users/Public/win-admin/app/1.0.0/` 并把 `current.txt` 指过去。
