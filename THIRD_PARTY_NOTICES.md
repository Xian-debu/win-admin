# Third-party notices

本仓库自身代码以 MIT 发布（见 `LICENSE`）。运行期依赖**仅限操作系统自带组件**，不打包、不分发任何第三方二进制。

| 组件 | 来源 | 用途 | 许可证 / 说明 |
|---|---|---|---|
| Windows PowerShell 5.1 | 微软，操作系统自带 | 执行 `win/` 载荷 | 随 Windows 提供，不随本仓库分发 |
| .NET Framework 程序集（`System.Windows.Forms`、`System.Drawing`、`UIAutomationClient`、`UIAutomationTypes`） | 微软，操作系统自带 | 截图、UI Automation | 随 Windows 提供，不随本仓库分发 |
| `winps`（WSL ↔ PowerShell 桥） | 用户本机既有脚本，不在本仓库内 | 把 `/mnt/c` 下的 `.ps1` 交给 `powershell.exe` | 本仓库只**调用**它，不分发；接口见 `docs/02` §4 |
| Pillow（可选） | Python 包索引 | 仅测试期做像素比对（M2 起） | MIT-CMU；**不进 Windows 侧载荷**（D12） |

> 若未来引入任何第三方二进制或 npm/pip 依赖，必须在此登记版本号、许可证和分发方式，并在 `docs/10` 说明安装步骤。
