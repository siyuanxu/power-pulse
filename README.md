# Power Pulse

<p align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" width="128" alt="Power Pulse app icon">
</p>

Power Pulse 是一个 macOS 原生供电监控工具，包含真正的 WidgetKit 桌面小组件和实时菜单栏读数。桌面组件使用系统网格占位，Finder 桌面文件不会与它重叠；菜单栏通过 IOKit 每 5 秒读取一次本机功率。

## 界面

<p align="center">
  <img src="docs/power-pulse-widget.png" width="360" alt="Power Pulse desktop widget showing live Mac power telemetry">
</p>

截图由 Power Pulse 使用当前机器的真实 IOKit 遥测生成；功率、电量、电压和电流会随机器状态变化。

## 最终方案

- WidgetKit 提供真正的桌面占位、拖放和系统编辑体验，但刷新频率由 macOS 调度，不能保证秒级更新。
- 菜单栏由宿主 App 每 5 秒读取一次 IOKit，继续承担实时瓦数显示。
- 不再使用自定义桌面窗口，因此不会置顶，也不会与 Finder 文件争抢位置。
- 运行时不需要 Homebrew、Node、sudo 或网络。

## 构建与启动

```sh
cd power-pulse
./build.sh
open "dist/Power Pulse.app"
```

启动后，在桌面空白处右键，选择“编辑小组件”，搜索 `Power Pulse`，把小号组件拖到桌面。点击菜单栏实时瓦数可查看添加说明、暂停刷新或退出。重启 Mac 后需要再次打开 App。

## 指标边界

- “Mac 侧实时输入”来自私有 IOKit 字段 `PowerTelemetryData.SystemPowerIn`，单位由 `V × A` 与功率值交叉校验。
- “电池净功率”来自私有遥测 `BatteryPower`，并用同一批样本的 `SystemPowerIn − SystemLoad` 做一致性检查；正值表示净充入、负值表示电池正在补充系统负载，不一致时显示为不可用。它是 Mac 内部遥测，不等同于外置电池分析仪的计量值。
- 额定功率优先来自公开 API `IOPSCopyExternalPowerAdapterDetails()`。
- 协议只显示本机能可靠确认的 `USB-C PD` 与当前合约档位，不臆测具体 PD 修订版。
- Mac 读到的是适配器到电脑的直流侧输入，并非插座交流侧电表实测值；若需要真正的“墙端功率”，仍需智能插座或外置功率计。

## License

[MIT](LICENSE)
