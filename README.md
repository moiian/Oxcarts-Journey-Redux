# Oxcarts Journey Redux — unified experimental build

将 OJR 的乘客旅行模式与 Let me drive oxcart 的原生司机位、手动驾驶整合为一个 REFramework 模组。随从控制及座位预设只有一份，不再同时运行两个独立模组。

## 安装与入口

复制整个 `reframework/autorun` 内容到游戏同名目录：

```text
autorun/
  Oxcarts Journey Redux.lua          # 唯一启动入口
  Oxcarts Journey Redux/
    journey.lua                     # 乘客旅行、共用随从控制及预设菜单
    driver.lua                      # 原生司机交互、手动转向及玩家显示位置
    presets.lua                     # 单一预设库、旧配置迁移
    speed.lua                       # 共用 Wait / Walk / Run / Dash 速度档位
```

不要同时启用旧的 `Let me drive oxcart.lua` 或另一份 OJR 启动脚本。本次部署将旧 LMD 脚本保留为 `.lua.disabled`，可用于回退；不依赖该文件、debug 工具或其他 MOD。安装后执行 REFramework **Reset scripts** 或重启游戏。

## 两种模式

乘客模式沿用原生乘客位和 OJR 的车票、路线逻辑。自动冲刺及终点减速仅在此模式运行。使用速度键手动调整后，本次乘车暂停自动加速，可点击 `Resume passenger auto cruise` 恢复。

司机模式通过原生司机交互进入。热键仅在 `Signed forward from driver point` 为 **0–3** 时响应；长按超过 **0.3 秒**请求牛车 Wait，满 **1 秒**请求上车。菜单按钮仍是直接请求入口。上车后牛车等待 **8 秒**，玩家显示位置、FOV、镜头距离也延迟 **8 秒**生效。每次进入使用当前车型第一个启用预设。司机模式不会自动加速或终点减速。

已有 NPC 司机先解除原生司机交互，确认解绑后真实传送到车后 **500**；附近未上车的已识别司机也会被一次性移走。没有司机则跳过；司机退出未完成或请求失败时停止本次玩家上车，不强抢绑定。不恢复 NPC 司机，不通过冻结 NPC FSM 留住它。

## 默认按键

| 操作 | 键盘 | 手柄 |
|---|---|---|
| Let me drive（长按 1 秒） | F | B / Circle |
| Let pawns sit / 下一预设 | E | X / Square |
| Let pawns stand（仅释放同行者） | F | B / Circle |
| Let me stand（停止脚本控制及玩家预设） | X | A / Cross |
| 转向（仅司机模式） | A / D | 左摇杆 |
| 加速一级 | W | RB / R1 |
| 减速一级 | S | LB / L1 |

进入司机位与随从起身共用默认按键，由当前座位状态区分。`Let me stand` 不额外强制原生下车；A / Cross 的原生下车由游戏处理。乘客和司机模式使用同一组主要映射；旧 OJR 修饰键保留为乘客模式备用控制。

## 共用预设与同行者

每个车型预设包含独立的乘客位玩家参数、司机位玩家参数，以及共用的最多 **9 名同行者**参数。主 Pawn 优先，其他 PawnManager 队员随后，正在跟随玩家的 NPC 最后；已有成员保留槽位，新成员补空位。未做四随从 MOD 专用适配，但队伍成员顺序读取方式保留。

首次加载会保留现有 OJR 预设，并将 LMD 预设追加为名称带 `(driver import)` 的独立预设，不猜测两套不同随从布局应该覆盖哪一套。之后只保存 `OxcartsJourneyRedux.json`；原 `LetMeDriveOxcart.json` 不再写入。迁移只执行一次。两边已调好的参数仍可选择、比较，之后只需维护共用随从参数。

`Restore built-in driver layouts` 仅重置带有原 LMD 内置标识的导入布局，不改未标记的 OJR 布局或用户新增布局。预设菜单按车型、布局下拉显示，同行者编辑槽按人数动态显示。

同行者使用真实位置、`PosRotContext` 和物理控制器同步到车体 `MoveFloor`（缺失时为车体 Transform），不请求原生座椅交互，不传送到车头。首次坐下、切换预设、随机坐姿及直接 Bank/Motion 均为：**解冻 → 同帧应用位置、跌落重置、请求坐姿 → 下一次 LateUpdateBehavior 冻结**。不请求切换前 Wait，也不按秒等待；日常跟随、拍照和起身不重复重置跌落。解绑恢复接管前 FSM，不传回上车前位置。

照片模式继续显示玩家及同行者的位置；司机模式的 FOV 和镜头距离不应用到照片模式。玩家不参与同行者 FSM 冻结或物理传送。

完整互动与解除条件见 [流程审查](docs/unified-flow.md)。

## 验证与版本

运行 `tests/run-unified-tests.ps1` 验证语法、原随从回归、迁移、原生司机交互、8 秒延迟、照片模式、共用坐姿流程、退出及真实启动入口。测试使用 Lua 5.3 DLL；可用 `OXCART_TEST_LUA_DLL` 指定路径。该测试依赖不是游戏模组依赖。

合并前检查点已推送至各自远程 main：OJR `160723e`，LMD `ef28a4d`。此合并版在 OJR 的 `experimental/unified-oxcart` 本地分支，尚未替换正式 main。自动测试不等同于游戏实测通过。
