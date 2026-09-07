# mGBA FoMT Mine X-Ray

《牧场物语：矿石镇的伙伴们》男孩版（GBA，A4NJ）的矿场透视工具。

它从 mGBA Lua API **只读**矿场内存，并提供两种显示方式：

- mGBA 脚本窗口中的 28×28 坐标地图与完整中文物品清单。
- Windows 高清透明浮层：在游戏窗口上显示平滑的矢量中文标签，并自动跟随窗口、缩放和全屏。

> 本仓库不提供 ROM、BIOS、模拟器二进制文件或游戏存档。请使用自己合法取得的游戏副本。

## 已验证版本

- ROM 标头代码：`A4NJ`
- 已验证 ROM SHA-256：`608481C713B89B6D8859DBB161C9CC59341701E6EBFE634271568CD89387010A`
- 模拟器：支持 Canvas 与启动脚本的 mGBA 0.11 开发版
- 系统：Windows 10/11，.NET Framework 4.8

其他语言或修订版的内存地址可能不同。

## 功能

- 泉边矿场与湖中矿场，0～255层。
- 显示矿石、钱袋、黑色草、楼梯候选、力之果实、菜谱和诅咒工具。
- 标记粉红钻石、亚历山大石、贤者之石、女神之玉、河童之玉和转移石。
- 浮层鼠标穿透；切换到其他程序时自动隐藏。
- 不写游戏内存，不修改 ROM 或存档。
- 只在系统临时目录写入 `mgba_mine_xray_state.txt`，供浮层读取。

## 构建

在 Windows PowerShell 中运行：

```powershell
.\build.ps1
```

生成：

- `MineXRayHDOverlay.exe`
- `OpenGbaWithLatestSave.exe`

也可以在 GitHub 的 **Actions** 页面运行 `build` 工作流并下载构建产物。

## 目录结构

构建完成后，在仓库根目录放置以下文件。`game/`、`emulator/` 和所有 ROM/存档都已被 `.gitignore` 排除。

```text
mgba-fomt-mine-xray/
├─ MineXRayHDOverlay.exe
├─ OpenGbaWithLatestSave.exe
├─ mine_xray_mgba.lua
├─ emulator/
│  ├─ mGBA.exe
│  ├─ portable.ini
│  └─ ...mGBA 发行包的其他文件
└─ game/
   ├─ game.gba
   ├─ game.sav       （可选）
   └─ game.ss1       （可选）
```

## 使用方法

### 高清透明浮层

运行 `MineXRayHDOverlay.exe`。程序会启动 `emulator/mGBA.exe`、载入 `game/game.gba` 和 Lua 脚本。进入矿场后，标签自动出现。

### 只使用 mGBA 脚本窗口

1. 用 mGBA 打开 ROM。
2. 选择 **Tools → Scripting… → Load Script…**。
3. 载入 `mine_xray_mgba.lua`。
4. 查看 `Mine Map 坐标地图` 与 `Item Names 物品名称`。

### 不使用透视启动 ROM

把 ROM 路径作为参数传给 `OpenGbaWithLatestSave.exe`。它会优先载入同目录最新的 `.ss1`～`.ss9`；按住 Shift 启动可跳过即时存档，改用游戏内 `.sav`。

## 标签说明

矿石：`转`转移石、`废`废矿石、`铜`、`银`、`金`、`秘`秘银、`奥`奥利哈钢、`刚`金刚石、`月`月亮石、`玫`沙漠玫瑰石、`粉`粉红钻石、`亚`亚历山大石、`贤`贤者之石、`钻`钻石、`绿`祖母绿、`红`红宝石、`黄`黄玉、`橄`橄榄石、`萤`萤石、`玛`玛瑙、`紫`紫水晶、`女`女神之玉、`河`河童之玉。

地下物：`梯`楼梯候选、`钱`钱袋、`果`力之果实、`镰/锄/斧/锤/水/竿`诅咒工具、`草`黑色草、`谱`菜谱。

- 右下橙色 L 角：楼梯候选。
- 右下黄色点：钱袋。
- 右下浅绿色点：黑色草。
- 左上彩色点：该格在重要地下物之外还含有矿石。

## 内存地址

| 内容 | 地址 |
|---|---:|
| 28×28 矿格数据 | `0x02007C68` |
| 当前矿层地图 ID | `0x02039064` |
| 镜头 X / Y | `0x030077BC` / `0x030077BE` |
| 体力 / 疲劳 | `0x02006A29` / `0x02006A2A` |

## 许可

代码采用 [MIT License](LICENSE)。游戏名称及相关商标归各自权利人所有。

