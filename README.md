# BtBar

BtBar 是一款专为 macOS 设计的蓝牙设备管理工具，通过状态栏图标提供直观的蓝牙设备监控和控制功能。

> **注意**：
> BtBar 理论上支持 macOS 13.0 及更高版本。
> 仅在 macOS 26 及更高版本中测试过，其他版本可能存在兼容性问题。
> 代码全由 AI 生成，可能存在错误或不完整的部分。

## 功能特性

<img width="225" height="200" alt="PixPin_2026-02-26_17-33-40" src="https://github.com/user-attachments/assets/e0a7bcaf-76b9-46af-ad6d-d87be0ff7b01" /><img width="435" height="238" alt="PixPin_2026-02-26_17-33-14" src="https://github.com/user-attachments/assets/c587c5b3-75f0-46c9-8174-8bebef6402ad" />



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

#### 方法一：使用命令行构建

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

#### 方法二：使用构建脚本

1. 克隆仓库：
   ```bash
   git clone https://github.com/luantu/BtBar.git
   cd BtBar
   ```

2. 运行构建脚本：
   ```bash
   chmod +x build_app.sh
   ./build_app.sh
   ```

   该脚本会自动构建应用并创建一个可分发的应用包。

#### 方法三：在Xcode中构建

1. 克隆仓库：
   ```bash
   git clone https://github.com/luantu/BtBar.git
   cd BtBar
   ```

2. 使用Xcode打开项目：
   ```bash
   open Package.swift
   ```

3. 在Xcode中，选择"Product" > "Build"来构建应用。

4. 选择"Product" > "Run"来运行应用。

### 安装到应用程序文件夹

构建完成后，可以将应用安装到应用程序文件夹：

1. 找到构建的应用：
   ```bash
   # 命令行构建的应用位于
   .build/release/BtBar
   ```

2. 将应用复制到应用程序文件夹：
   ```bash
   cp -r .build/release/BtBar.app /Applications/
   ```

   或者，使用构建脚本构建的应用会自动创建在项目根目录。

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
