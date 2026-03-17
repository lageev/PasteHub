# PasteHub

PasteHub 是一个 macOS 状态栏剪贴板工具：自动记录复制内容，通过全局快捷键呼出浮动面板，支持一键回填到原应用。

## 主要功能

- **剪贴板历史**：自动监听文本、图片、文件三类内容
- **双模式面板**：历史记录 / 常用片段可切换
- **快速检索**：支持搜索、类型筛选（全部/文本/图片/文件）、标签筛选
- **标签体系**：历史条目与常用片段都可编辑标签
- **分词选择**：对文本条目可按字符选择后再执行键入
- **全局快捷键**：默认 `Cmd+Shift+V`，可在设置里录制修改
- **自动键入**：点击条目后尝试切回目标应用并粘贴（需辅助功能权限）
- **浮动面板布局**：支持顶部/底部/左侧/右侧弹出
- **排除应用**：可配置不记录指定应用的剪贴板内容
- **开机自启**：通过 `SMAppService` 注册 Login Item
- **设置页**：通用、快捷键诊断、排除应用、关于

## 运行要求

- 使用 Xcode 打开并运行 `PasteHub.xcodeproj`
- 最低系统版本以工程配置为准（`MACOSX_DEPLOYMENT_TARGET`）

## 快速开始

1. 打开 `PasteHub.xcodeproj`
2. 选择 `PasteHub` Scheme
3. Build & Run
4. 首次运行后在菜单栏可看到应用图标

## 使用说明

- 复制任意文本/图片/文件后，内容会自动进入历史
- 按 `Cmd+Shift+V` 呼出或隐藏面板
- 单击卡片会执行“复制并回填”
- 右键卡片可执行：重新复制、编辑标签、删除、添加到常用片段（文本）
- 切换到“常用片段”模式可新建/编辑片段

## 权限说明

- **辅助功能权限（Accessibility）**
  - 用于自动切回目标应用并执行粘贴
  - 未授权时，剪贴板记录与手动复制仍可正常使用
  - 可在设置页的“键入权限诊断”里查看状态与快速跳转系统设置

## 快捷键与菜单

- 全局快捷键：默认 `Cmd+Shift+V`（可自定义）
- 菜单快捷键：
  - 打开设置：`Cmd+,`
  - 退出应用：`Cmd+Q`

## 数据存储

应用数据默认保存在：

`~/Library/Application Support/PasteHub/`

主要文件：

- `history.json`：历史记录
- `snippets.json`：常用片段
- `Images/`：图片剪贴板缓存

## 项目结构

```text
PasteHub/
├── PasteHubApp.swift              # 应用入口
├── AppDelegate.swift              # 状态栏、浮窗、全局快捷键
├── Models/
│   ├── ClipboardItem.swift        # 剪贴板条目模型
│   └── SnippetItem.swift          # 片段模型
├── Services/
│   ├── ClipboardMonitor.swift     # 剪贴板轮询
│   ├── ClipboardStore.swift       # 存储与持久化
│   ├── PasteToAppService.swift    # 自动回填/键入
│   └── SettingsManager.swift      # 偏好设置管理
└── Views/
    ├── ClipboardListView.swift    # 主面板 UI
    ├── FloatingPanel.swift        # 浮动面板窗口
    └── SettingsView.swift         # 设置窗口
```

## License

MIT
