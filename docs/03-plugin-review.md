# 03 · 网上那个"管理员插件"的审计结论（为什么不采纳）

> 对象：`@local/dsh-admin-mode` 1.0.0（自称"自制 DSH 管理员插件"）
> 来源：Lanzou 分享，人肉穿三层反爬取得（arg1 JS 挑战 → `apifile.woozooo.com` downprocess → `developer4.lanrar.com` 二次校验）
> 原件：`/root/quarantine/dsh-admin-plugin/dsh-admin-mode-1.0.0.zip`
> SHA256：`f56d4b768b3cec1cc30db031780981940f814ba7bbb1be77e54eef261113688c`，1,264,344 B
> 审计方式：**纯静态，逐行读完，一行未执行**

## 1. 内容构成（11 个文件，无二进制）

| 文件 | 大小 | 作用 | 判定 |
|---|---|---|---|
| `package.json` | 972 B | 清单：依赖 2 个官方包、bundle patch、客户端入口 | 干净 |
| `index.js` | 2,958 B | 拉起 HUD（`pythonw` detached），监听 `cua_driver_native__*` 工具事件写 cmd 文件；注入一条系统提示 | 无网络、无 shell、只写 tmp |
| `client.js` | 34,392 B | 接管权限菜单槽位（自绘 4 档 + 两次勾选警告 + 滤掉 `auto`），加 ↻ 迭代按钮 | 逻辑完整，无隐藏能力 |
| `cordis.patch.yml` | 1,547 B | 插入官方 computer-use 两包；**整表重写**权限预设；插入自身客户端插件 | ⚠️ 覆盖式 |
| `hud/cua_hud.py` | 9,821 B | 纯 Win32 分层窗口：辉光边框 + 毛玻璃标题块 | 无网络，见 §3 |
| `README/LICENSE/locale/icon/preview.png` | 1.3 MB | 文档与素材（其中 preview.png 占 1,243,628 B） | 干净 |

危险模式扫描（全树）：`fetch(` / `XMLHttpRequest` / `WebSocket` / `eval(` / `new Function` /
`atob` / `btoa` / `localStorage` / `document.cookie` / `ipc` / `innerHTML` / `https://` **命中数均为 0**。
唯一 `http://` 出现在 `icon.svg` 的 SVG 命名空间。

**结论：不是恶意软件。** 作者水平不差，代码组织清晰，注释带日期，是"AI 给主人写的工具"那一类。

## 2. 关键发现一：它的"管理员档"= DSH 内置的"完全权限档"

官方 `@deepseek-ai/dsh-permission-presets@0.2.1-rc.2` 的 `lib/index.js:151-155`：

```js
"danger-full-access": {
  sandbox: "danger-full-access",
  approval: "never",
  name: "danger-full-access",
  description: "Full file access without approval prompts."
}
```

插件 admin 档给的是**同样的两个参数**，换了个名字、加了红徽章和两次弹窗。

本会话运行时已是 `danger-full-access` + `approvals disabled`。
**⇒ 装这个插件，权限层新增能力 = 0。**

## 3. 关键发现二：真正的增量（computer use）在本机跑不起来

- 两个依赖是**真官方包**：`@deepseek-ai/dsh-computer-use@0.2.1-rc.2`、
  `@deepseek-ai/dsh-experimental-computer-use-cua-driver-native@0.2.1-rc.2`，
  npm registry 可查，版本与本机 DSH `0.2.1-rc.2` 精确对齐，**不存在供应链替换**。
- 但 `cua-driver-native` 依赖第三方 Rust 原生驱动 `@trycua/cua-driver@0.28.0`，
  其平台包只有：`darwin-x64/arm64`、`linux-x64-gnu/arm64-gnu`、`win32-x64-msvc/arm64-msvc`。
- 本机 `DISPLAY` 为空（`docs/02` §2）。Linux 版驱动没有可绘制的屏，
  **看不到 Windows 桌面**；要驱动 Windows 桌面，DSH 必须以 Electron 桌面端跑在 Windows 侧。
- HUD 同理：`ctypes.windll` + `C:/Windows/Fonts/msyh.ttc` + `pythonw.exe`，WSL 里直接 import 失败（优雅降级，不崩），等于没有。

## 4. 关键发现三：「按 ESC 取消」是假的急停

`hud/cua_hud.py:256-259`：

```python
if user32.GetAsyncKeyState(VK_ESCAPE) & 0x8000:
    print("ESC_PRESSED", flush=True)
    break          # ← 只 break 掉 HUD 自己的渲染循环
```

它只让提示层消失，**不中断 agent 的任何动作**。README §安全提示 自己也写「HUD 只是视觉提示，
不改变权限行为」。在真实接管场景里，这制造的是"我有刹车"的错觉——比没有刹车更危险。

## 5. 残余风险清单（即便要用也得知道）

| # | 风险 | 严重度 |
|---|---|---|
| R1 | 无上游仓库：`package.json` 无自身 repository，只在 Lanzou 发布，无签名、无校验链；1.0.0 干净不代表 1.0.1 干净 | 中 |
| R2 | `cordis.patch.yml` **整表覆盖**权限预设：将来 DSH 升级新增的档位（含 `auto` 审查档）会被静默顶掉；配置漂移后"完全权限"的实际语义可能改变 | 中 |
| R3 | 原生驱动 **in-process**（官方标注 experimental），Rust 崩溃带崩整个 DSH | 中 |
| R4 | 往 systemPrompt 注入「优先用 computer use 而非脚本」的长期偏置 | 低 |
| R5 | 权限面 = 用户会话全权，且"永不询问" | 高（但等价于内置档，非插件新增） |

## 6. 采纳判定

**不采纳，理由三条：**

1. **零增益**：它最重要的"管理员档"与内置 `danger-full-access` 完全等价；
2. **不可用**：它的原始增量（computer use）需要 Windows 侧 Electron DSH，而我们不走那条路
   （`docs/06-decisions.md` D2 说明为什么）；
3. **负安全**：假急停 + 覆盖式 patch，把一个本来清晰的边界弄模糊了。

**保留价值（我们照抄的部分）：**

- 两次严重警告的 UX 分档思路（一次确认给"完全权限"，两次给"接管"）→ 采纳进 `docs/07` 的授权流程；
- HUD 的视觉提示设计（"正在控制"的常驻可见性）→ 采纳为 S 类验收项（不过状态证明，而是用我们的审计行 + 可选中控条）；
- `cua_hud.py` 的 Win32 分层窗口写法本身干净，若将来要做中控条，可作为参考实现。

原件保留在隔离区不动，随时可供复核；需要清理时说一声。
