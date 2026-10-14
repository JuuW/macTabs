# iTabs — 项目速查(给 Claude Code 看的开发笔记)

macOS 菜单栏小工具:屏幕顶部浮一条浏览器式页签栏,列出**当前前台受支持 app**的所有窗口,单击切换。原生 Swift + SwiftUI + AppKit,靠 Accessibility(AXUIElement)API 读/切窗口。无网络、无后台服务。面向用户的说明看 `README.md`,这里是改代码时的地图。

## 构建 / 运行 / 验证

- **只验证编译**:`swift build -c release`(约 5s)。链接器会报 `search path ... not found` 警告,无害可忽略。
- **打包成 .app**:`./build.sh` —— 编译 release → 组装 `iTabs.app` → 用本地证书 `iTabs-SelfSign` 签名(没有则回退 ad-hoc)。
- **看到改动必须重启进程**:改完 `build.sh` 后旧进程还在跑。重启:
  ```bash
  pkill -x iTabs; sleep 0.5; open iTabs.app
  ```
  这是最容易忘的一步 —— 重新构建 ≠ 生效。
- **无法在 Claude Code 里做视觉验证**:这是 GUI + 辅助功能权限 + 悬浮面板,只能靠用户肉眼确认。改完后交给用户看,别声称"已验证视觉效果"。
- 配置存 `~/.itabs_settings.json`(受支持 app 列表 + 标题截断长度)。

## 源码地图(`Sources/iTabs/`)

| 文件 | 职责 |
|---|---|
| `main.swift` | `AppDelegate` + app 入口。创建悬浮 `NSPanel`、菜单栏 `NSStatusItem`、监听前台 app 切换决定面板显隐、`positionPanel` 决定面板尺寸/位置。`app.setActivationPolicy(.accessory)`(不占 Dock)。 |
| `TabBarView.swift` | 页签栏全部 SwiftUI。含 `TabBarView`(根)、`TabChip`(单个页签)、`NewWindowButton`、`OverflowMenuView`(溢出下拉)、`OverflowTabsLayout`(自定义单行溢出布局)、`OverflowState`(共享状态)。 |
| `WindowManager.swift` | `ObservableObject`。枚举/聚焦/关闭/新建窗口,全部走 AXUIElement。每 1s `refresh()` 轮询。窗口身份、排序、高亮逻辑都在这。 |
| `SettingsStore.swift` | 受支持 app 集合 + 标题最大长度,持久化到 `~/.itabs_settings.json`。 |
| `SettingsView.swift` | 设置窗口 UI。 |
| `InstalledAppsScanner.swift` | 扫描系统已安装 app 供用户勾选。 |

## 关键机制(改之前先懂这些)

### 面板尺寸与位置(`main.swift` `positionPanel`)
- 面板宽度**随内容可变**:`宽度 = contentWidth + 16(左右内边距) `,**封顶 90% 屏宽**(`f.width * 0.9`),**最小 220pt**(容纳空状态/权限提示文案),**水平居中**紧贴顶部,高度固定 28。
- `contentWidth` 由 `TabBarView` 的布局层回调上报(见下)。这是为了解决"固定 90% 宽面板盖住窗口右上角红绿灯按钮"的问题 —— 页签少时面板收缩成短条。
- 屏幕参数变化(`didChangeScreenParametersNotification`)会重新 `positionPanel`。

### 内容宽度上报(`TabBarView.swift` `OverflowTabsLayout`)
- `TabBarView` 有 `onContentWidthChange: ((CGFloat) -> Void)?` 回调,`AppDelegate` 用它接收宽度并 resize 面板。
- `OverflowTabsLayout.sizeThatFits` 用**子视图固有宽度**(`sizeThatFits(.unspecified)`)算理想总宽 = 所有页签 + 「+」按钮,然后上报。
- **关键**:必须用固有宽度而非面板当前宽度,否则会形成"面板宽→可见页签→算宽→缩面板"的**循环依赖**。
- 上报经 `OverflowState.lastReportedWidth` 去重 + `DispatchQueue.main.async`,避免重复回调 / 布局期间改状态。

### 溢出布局(`OverflowTabsLayout.placeSubviews`)
- 子视图顺序:`[0..<count]` 页签,`[count]` 溢出菜单,`[count+1]` 新建「+」按钮。
- 全放得下:页签 + 「+」整体居中,溢出菜单挪到屏外(x + 2000)。
- 放不下:左对齐铺到临界点,剩余页签挪屏外,溢出菜单(`reserve=40`)+「+」贴在可见页签后。
- 可见数量经 `OverflowState.visibleCount` + 防抖 token(`updateToken`,80ms)传给 `OverflowMenuView`,它取 `windows.suffix` 填下拉菜单。

### 窗口身份 / 排序 / 高亮(`WindowManager`)
- 窗口 id = `pid-标题@位置#区分号`。位置用来区分同标题窗口;`elementDiscriminators` 给同"标题@位置"撞车的窗口按 AX 元素身份分配稳定区分号。
- 页签顺序按**首次出现序号**(`orderSeen`/`nextOrder`)稳定排列,**不随 z-order 漂移**。
- 高亮按 AX 元素身份(`CFEqual`)比对聚焦窗口,不比标题,避免同标题误高亮。
- 只保留标准文档窗口:`role==AXWindow && subrole==AXStandardWindow`,滤掉工具面板/浮窗。
- 新建窗口 = 激活 app 后发 ⌘N(`sendCommandN`,多数 app 的新建窗口都绑这)。
- 关闭 = 按窗口的 AXCloseButton。

## 环境约束 / 已知坑

- **CLT 工具链缺 SwiftUIMacros 插件**,`@State` 宏无法展开 → 悬停态/共享态改用 `ObservableObject`(见 `HoverState`、`OverflowState`)。新增视图状态时别用 `@State`,照抄这个模式。
- SwiftUI `Layout` 里**不能同步改 `@Published`** 触发重绘,会告警/循环。用非 `@Published` 字段 + `DispatchQueue.main.async` 延迟提交(`OverflowState` 两个字段都是这么做的)。
- 彩色菜单栏图标必须 `isTemplate=false`,否则被系统强制单色化(`makeStatusIcon`)。
- 面板是 `.nonactivatingPanel + .borderless`,点击不抢焦点 —— 切窗口时才用 `app.activate()`。

## 语言约定

代码注释用中文(贴合现有风格)。与用户交流用中文。
