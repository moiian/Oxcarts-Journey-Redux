# Oxcarts Journey Redux

Dragon's Dogma 2 REFramework 牛车旅行模组。

## 分支

- `main`：正式版，保留牛车控制、随从座位、右侧技能栏、按键映射与保护功能，不包含调试界面或诊断脚本。
- `debug`：保留调试界面、状态导出、动作测试和导航研究工具的可测试版本。

## 安装

将 `reframework/autorun` 中的 Lua 脚本放入游戏同名目录，需要 REFramework。
正式版不要同时加载 debug 分支的 `Oxcarts Journey Diagnostics.lua`。

## 正式版行为

自动冲刺默认启用。玩家坐在牛车上、距当前目标站点及终点至少 25、牛持续移动且处于 Walk 超过 4 秒、累计转向不超过 60°时，自动进入 Dash。
冲刺时长固定为 360 秒，目标站点减速距离固定为 15。上述四个参数不在菜单中显示，也不受旧配置覆盖。

司机与牛车的非战斗覆盖默认启用。玩家距车体不超过 2.5 时，持续请求 `BattleManager.requestForceNormal(true)`，坐着与站着都生效；离开范围后停止请求。这是车体距离近似判定，站在车旁也可能触发，且 BattleManager 可能影响队伍。

游戏暂停时不累计自动冲刺的稳定时间，也不执行自动解除随从控制。到站、离车、牛车损坏或翻车时仍按对应规则处理。

左侧 Pawn Command 技能栏的文字修改功能不启用，但原有修饰键和按键操作保留。右侧坐姿技能栏保留。

## 设置

REFramework 菜单依次为 `Keybind Settings`、`Seating Position Presets`、`Other Settings`。可调整按键、座位预设与保护系数；自动冲刺和三个非战斗功能固定启用，不显示开关，旧配置也不能关闭它们。

修饰键默认为 `LShift`；修饰键配合数字键 `1/2/3/4` 分别执行冲刺、Walk、随从坐下/传送和随从起身。手柄对应 `LUp/LLeft/LRight/LDown`，修饰键为 `LTrigBottom`。独立的 Switch 功能及其键位已移除。

右侧坐姿技能栏：冲刺使用鼠标左键，Walk 使用鼠标右键，随从坐下/传送使用 `E`，起身使用 `F`。鼠标左右键沿用原有固定实现。每种车型第一次手动 Sit 使用第一个启用的座位预设；之后每次 Sit 顺序循环到下一个启用的预设，跳过停用项。自动重新固定座位不会推进预设。同一帧重叠的 Sit 输入只处理一次。

`Restore default keybinds` 恢复全部默认键位，取消正在等待的映射输入，不改座位预设或保护系数。已有自定义键位保留，需点击该按钮才能恢复新默认值。旧配置中的 Switch 键位不再加载，下一次保存配置时会移除。

设置保存到 `reframework/data/OxcartsJourneyRedux.json`，该本地配置不提交到仓库。
