# BtBar

BtBar 是一款专为 macOS 设计的蓝牙设备管理工具，通过状态栏图标提供直观的蓝牙设备监控和控制功能。

## 功能特性

- **设备管理**：自动扫描并列出已配对的蓝牙设备
- **连接控制**：支持设备的连接和断开操作
- **状态监控**：实时监控设备连接状态和电量
- **图标自定义**：支持为每个设备设置自定义图标
- **电量提醒**：低电量时发送通知提醒
- **状态栏集成**：在状态栏显示设备图标，方便快速访问

## 系统要求

- macOS 13.0 或更高版本
- Swift 5.9 或更高版本
- Xcode 14.0 或更高版本

## 安装方法

### 从源代码构建

1. 克隆仓库：
   ```bash
   git clone https://github.com/luantu/BtBar.git
   cd BtBar
   ```

2. 构建应用：
   ```bash
   swift build -c release
   ```

3. 运行应用：
   ```bash
   swift run
   ```

## 使用方法

1. 启动 BtBar 应用后，会在状态栏显示蓝牙图标
2. 点击图标可以查看已配对的蓝牙设备列表
3. 已连接的设备会显示绿色圆点和电量信息
4. 点击设备名称可以展开子菜单，进行连接/断开、重命名、修改图标等操作
5. 已连接的设备会在状态栏显示单独的图标（可在设置中关闭）

## 开发说明

### 项目结构

```
BtBar/
├── Sources/
│   └── BtBar/
│       └── main.swift        # 主源代码文件
├── Resources/                # 应用图标和资源
├── Package.swift             # 项目配置
└── README.md                 # 项目说明
```

### 核心功能模块

- **BluetoothManager**：蓝牙设备管理，负责设备扫描、连接控制和状态监控
- **StatusBarManager**：状态栏管理，负责在状态栏显示设备图标和处理用户交互
- **SettingsView**：设置界面，提供设备管理和显示设置选项

## 贡献

欢迎提交 Issue 和 Pull Request 来改进 BtBar！

## 许可证

BtBar 使用 MIT 许可证。详见 LICENSE 文件。

## 联系方式

- GitHub: [https://github.com/luantu/BtBar](https://github.com/luantu/BtBar)
