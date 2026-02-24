import SwiftUI
import AppKit
import Combine
import CoreBluetooth
import UserNotifications
import IOBluetooth
import CoreImage
import CoreAudio

// 全局工具函数
func localTimeString() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.timeZone = TimeZone.current
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
    return dateFormatter.string(from: Date())
}

// 音频设备管理函数
func getAudioDevices() -> [(id: AudioDeviceID, name: String)] {
    var devices: [(id: AudioDeviceID, name: String)] = []
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var propertySize: UInt32 = 0
    var result = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
    if result != noErr {
        print("Error getting audio devices size: \(result)")
        return devices
    }
    
    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    result = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceIDs)
    if result != noErr {
        print("Error getting audio devices: \(result)")
        return devices
    }
    
    for deviceID in deviceIDs {
        var name: CFString = "" as CFString
        var nameSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
        propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString
        propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
        propertyAddress.mElement = kAudioObjectPropertyElementMain
        
        result = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &nameSize, &name)
        if result == noErr {
            devices.append((id: deviceID, name: name as String))
        }
    }
    
    return devices
}

func setDefaultAudioDevice(_ deviceID: AudioDeviceID) -> Bool {
    // 尝试设置默认输出设备
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var mutableDeviceID = deviceID
    var result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mutableDeviceID)
    if result != noErr {
        print("Error setting default output device: \(result)")
        return false
    }
    
    // 尝试设置默认输入设备（如果设备同时支持输入）
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice
    result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mutableDeviceID)
    if result != noErr {
        print("Warning: Error setting default input device: \(result)")
        // 不返回失败，因为输出设备设置成功即可
    }
    
    // 尝试设置默认系统设备
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultSystemOutputDevice
    result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mutableDeviceID)
    if result != noErr {
        print("Warning: Error setting default system output device: \(result)")
    }
    
    // 等待一小段时间，让系统完成切换
    usleep(100000) // 100ms
    
    return true
}

func findAudioDeviceByName(_ name: String) -> AudioDeviceID? {
    let devices = getAudioDevices()
    for device in devices {
        if device.name.lowercased().contains(name.lowercased()) {
            return device.id
        }
    }
    return nil
}

func getCurrentDefaultAudioDevice() -> (id: AudioDeviceID, name: String)? {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var deviceID: AudioDeviceID = 0
    var propertySize: UInt32 = UInt32(MemoryLayout<AudioDeviceID>.size)
    let result = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
    
    if result != noErr {
        print("Error getting current default audio device: \(result)")
        return nil
    }
    
    // 获取设备名称
    var name: CFString = "" as CFString
    var nameSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
    propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString
    
    let nameResult = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &nameSize, &name)
    if nameResult != noErr {
        print("Error getting current default audio device name: \(nameResult)")
        return (id: deviceID, name: "Unknown")
    }
    
    return (id: deviceID, name: name as String)
}

@main
struct BtBarApp: App {
    static let bluetoothManager = BluetoothManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(Self.bluetoothManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarManager: StatusBarManager?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 请求通知权限
        requestNotificationPermission()
        
        // 获取蓝牙管理器实例
        let bluetoothManager = BtBarApp.bluetoothManager
        
        // 初始化状态栏管理器
        statusBarManager = StatusBarManager(bluetoothManager: bluetoothManager)
        
        // 开始扫描蓝牙设备
        bluetoothManager.startScanning()
        
        // 监听蓝牙状态变化
        NotificationCenter.default.addObserver(forName: NSNotification.Name("CBCentralManagerStateChangedNotification"), object: nil, queue: nil) { notification in
            let bluetoothManager = BtBarApp.bluetoothManager
            if bluetoothManager.centralManager.state == .poweredOn {
                bluetoothManager.startScanning()
            }
        }
    }
    
    private func requestNotificationPermission() {
        // 检查是否在支持的环境中运行
        if Bundle.main.bundlePath != "" && Bundle.main.bundleIdentifier != nil {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { (granted, error) in
                if granted {
                    print("Notification permission granted")
                } else if let error = error {
                    print("Error requesting notification permission: \(error)")
                }
            }
        }
    }
}

// 蓝牙设备模型
struct BluetoothDevice: Identifiable, Hashable {
    let id: String // 使用Mac地址作为ID
    var name: String
    let macAddress: String
    var isConnected: Bool
    var batteryLevel: Int?
    var defaultIconName: String
    var customIconName: String?
    
    var iconName: String {
        return customIconName ?? defaultIconName
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        return lhs.id == rhs.id
    }
}

// 蓝牙管理器
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var devices: [BluetoothDevice] = []
    public var centralManager: CBCentralManager!
    private var peripherals: [CBPeripheral] = []
    private var refreshTimer: Timer?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        setupBluetoothNotifications()
        // 启动电量监控
        startBatteryMonitoring()
    }
    
    private func setupBluetoothNotifications() {
        let timestamp = localTimeString()
        print("\n=== Setting up Bluetooth notifications ===")
        print("Timestamp: \(timestamp)")
        
        // 打印所有可用的IOBluetooth通知名称
        print("\n=== Available IOBluetooth notifications ===")
        print("IOBluetoothDeviceConnectedNotification")
        print("IOBluetoothDeviceDisconnectedNotification")
        print("IOBluetoothDevicePairedNotification")
        print("IOBluetoothDeviceUnpairedNotification")
        print("IOBluetoothAdapterPoweredOnNotification")
        print("IOBluetoothAdapterPoweredOffNotification")
        print("IOBluetoothDevicePublishedNotification")
        print("IOBluetoothDeviceDestroyedNotification")
        print("====================================================")
        
        // 直接获取StatusBarManager实例，用于直接调用更新方法
        let appDelegate = NSApplication.shared.delegate as? AppDelegate
        let statusBarManager = appDelegate?.statusBarManager
        print("StatusBarManager instance: \(statusBarManager != nil ? "available" : "nil")")
        
        // 监听蓝牙设备连接通知
        print("Adding observer for IOBluetoothDeviceConnectedNotification")
        NotificationCenter.default.addObserver(
            forName: Notification.Name("IOBluetoothDeviceConnectedNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let timestamp = localTimeString()
            print("\n=== IOBluetoothDeviceConnectedNotification received ===")
            print("Timestamp: \(timestamp)")
            print("Notification: \(notification)")
            print("Notification name: \(notification.name)")
            print("Notification object: \(notification.object ?? "nil")")
            
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device name: \(bluetoothDevice.name ?? "Unknown")")
                print("Device address: \(bluetoothDevice.addressString ?? "Unknown")")
                print("Device is connected: \(bluetoothDevice.isConnected())")
                
                // 立即刷新设备列表
                print("Calling retrieveConnectedDevices()...")
                self?.retrieveConnectedDevices()
                print("retrieveConnectedDevices() completed")
            } else {
                print("Notification object is not a IOBluetoothDevice")
                print("Notification object type: \(type(of: notification.object))")
            }
            print("===================================================")
        }
        
        // 监听蓝牙设备断开通知（带ed后缀）
        print("Adding observer for IOBluetoothDeviceDisconnectedNotification")
        NotificationCenter.default.addObserver(
            forName: Notification.Name("IOBluetoothDeviceDisconnectedNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let timestamp = localTimeString()
            print("\n=== IOBluetoothDeviceDisconnectedNotification received ===")
            print("Timestamp: \(timestamp)")
            print("Notification: \(notification)")
            print("Notification name: \(notification.name)")
            print("Notification object: \(notification.object ?? "nil")")
            
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device name: \(bluetoothDevice.name ?? "Unknown")")
                print("Device address: \(bluetoothDevice.addressString ?? "Unknown")")
                print("Device is connected: \(bluetoothDevice.isConnected())")
                
                // 手动检查设备连接状态
                print("Manual connection check: \(!bluetoothDevice.isConnected())")
                
                // 立即刷新设备列表
                print("Calling retrieveConnectedDevices()...")
                self?.retrieveConnectedDevices()
                print("retrieveConnectedDevices() completed")
                
                // 设备列表更新后会自动触发UI更新，无需在此处直接更新
                print("Device list refresh initiated, UI will be updated automatically")
            } else {
                print("Notification object is not a IOBluetoothDevice")
                print("Notification object type: \(type(of: notification.object))")
            }
            print("====================================================")
        }
        
        // 监听蓝牙设备断开通知（无ed后缀，可能是实际使用的通知名称）
        print("Adding observer for IOBluetoothDeviceDisconnectNotification")
        NotificationCenter.default.addObserver(
            forName: Notification.Name("IOBluetoothDeviceDisconnectNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let timestamp = localTimeString()
            print("\n=== IOBluetoothDeviceDisconnectNotification received ===")
            print("Timestamp: \(timestamp)")
            print("Notification: \(notification)")
            print("Notification name: \(notification.name)")
            print("Notification object: \(notification.object ?? "nil")")
            
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device name: \(bluetoothDevice.name ?? "Unknown")")
                print("Device address: \(bluetoothDevice.addressString ?? "Unknown")")
                print("Device is connected: \(bluetoothDevice.isConnected())")
                
                // 手动检查设备连接状态
                print("Manual connection check: \(!bluetoothDevice.isConnected())")
                
                // 立即刷新设备列表
                print("Calling retrieveConnectedDevices()...")
                self?.retrieveConnectedDevices()
                print("retrieveConnectedDevices() completed")
            } else {
                print("Notification object is not a IOBluetoothDevice")
                print("Notification object type: \(type(of: notification.object))")
            }
            print("====================================================")
        }
        
        // 监听蓝牙设备销毁通知
        print("Adding observer for IOBluetoothDeviceDestroyedNotification")
        NotificationCenter.default.addObserver(
            forName: Notification.Name("IOBluetoothDeviceDestroyedNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let timestamp = localTimeString()
            print("\n=== IOBluetoothDeviceDestroyedNotification received ===")
            print("Timestamp: \(timestamp)")
            print("Notification: \(notification)")
            print("Notification name: \(notification.name)")
            print("Notification object: \(notification.object ?? "nil")")
            
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device name: \(bluetoothDevice.name ?? "Unknown")")
                print("Device address: \(bluetoothDevice.addressString ?? "Unknown")")
                print("Device is connected: \(bluetoothDevice.isConnected())")
                
                // 立即刷新设备列表
                print("Calling retrieveConnectedDevices()...")
                self?.retrieveConnectedDevices()
                print("retrieveConnectedDevices() completed")
                
                // 设备列表更新后会自动触发UI更新，无需在此处直接更新
                print("Device list refresh initiated, UI will be updated automatically")
            } else {
                print("Notification object is not a IOBluetoothDevice")
                print("Notification object type: \(type(of: notification.object))")
            }
            print("====================================================")
        }
        
        // 监听蓝牙设备配对通知
        print("Adding observer for IOBluetoothDevicePairedNotification")
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("IOBluetoothDevicePairedNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device paired: \(bluetoothDevice.name ?? "Unknown")")
                self?.retrieveConnectedDevices()
            }
        }
        
        // 监听蓝牙设备取消配对通知
        print("Adding observer for IOBluetoothDeviceUnpairedNotification")
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("IOBluetoothDeviceUnpairedNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device unpaired: \(bluetoothDevice.name ?? "Unknown")")
                self?.retrieveConnectedDevices()
            }
        }
        
        // 监听蓝牙状态变化通知
        print("Adding observer for CBCentralManagerStateChangedNotification")
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CBCentralManagerStateChangedNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            print("Bluetooth central manager state changed")
            self?.retrieveConnectedDevices()
        }
        
        // 添加全局通知监听，捕获所有通知
        print("Adding observer for ALL notifications (for debugging)")
        NotificationCenter.default.addObserver(
            forName: nil,
            object: nil,
            queue: nil
        ) {[weak self] notification in
            let name = notification.name.rawValue
            if name.contains("Bluetooth") || name.contains("IOBluetooth") {
                let timestamp = localTimeString()
                print("[\(timestamp)] Bluetooth-related notification: \(name)")
                print("[\(timestamp)] Notification object: \(notification.object ?? "nil")")
                print("[\(timestamp)] Notification userInfo: \(notification.userInfo ?? [:])")
                
                // 立即处理IOBluetoothDevicePublished通知
                if name == "IOBluetoothDevicePublished" {
                    print("[\(timestamp)] Immediately handling IOBluetoothDevicePublished notification...")
                    self?.retrieveConnectedDevices()
                }
                
                // 立即处理IOBluetoothDeviceDestroyed和IOBluetoothDeviceDisconnected通知
                if name == "IOBluetoothDeviceDestroyed" || name == "IOBluetoothDeviceDisconnected" {
                    print("[\(timestamp)] Immediately handling disconnection notification...")
                    self?.retrieveConnectedDevices()
                }
            }
        }
        
        // 监听蓝牙设备发布通知
        print("Adding observer for IOBluetoothDevicePublishedNotification")
        NotificationCenter.default.addObserver(
            forName: Notification.Name("IOBluetoothDevicePublishedNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let timestamp = localTimeString()
            print("\n=== IOBluetoothDevicePublishedNotification received ===")
            print("Timestamp: \(timestamp)")
            print("Notification: \(notification)")
            print("Notification name: \(notification.name)")
            print("Notification object: \(notification.object ?? "nil")")
            
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device name: \(bluetoothDevice.name ?? "Unknown")")
                print("Device address: \(bluetoothDevice.addressString ?? "Unknown")")
                print("Device is connected: \(bluetoothDevice.isConnected())")
                print("Device is paired: \(bluetoothDevice.isPaired())")
                
                // 无论设备当前连接状态如何，都直接刷新设备列表
                // 系统可能只发送这个通告，需要立即处理
                print("Treating device published as connected, calling retrieveConnectedDevices()...")
                
                // 立即调用retrieveConnectedDevices()
                self?.retrieveConnectedDevices()
                
                // 设备列表更新后会自动触发UI更新，无需在此处直接更新
                print("Device list refresh initiated, UI will be updated automatically")
            } else {
                print("Notification object is not a IOBluetoothDevice")
                print("Notification object type: \(type(of: notification.object))")
            }
            print("====================================================")
        }
        
        // 监听蓝牙设备连接通知（无ed后缀）
        print("Adding observer for IOBluetoothDeviceConnectNotification")
        NotificationCenter.default.addObserver(
            forName: Notification.Name("IOBluetoothDeviceConnectNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let timestamp = localTimeString()
            print("\n=== IOBluetoothDeviceConnectNotification received ===")
            print("Timestamp: \(timestamp)")
            print("Notification: \(notification)")
            print("Notification name: \(notification.name)")
            print("Notification object: \(notification.object ?? "nil")")
            
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device name: \(bluetoothDevice.name ?? "Unknown")")
                print("Device address: \(bluetoothDevice.addressString ?? "Unknown")")
                print("Device is connected: \(bluetoothDevice.isConnected())")
                
                // 立即刷新设备列表
                print("Calling retrieveConnectedDevices()...")
                self?.retrieveConnectedDevices()
                print("retrieveConnectedDevices() completed")
            } else {
                print("Notification object is not a IOBluetoothDevice")
                print("Notification object type: \(type(of: notification.object))")
            }
            print("===================================================")
        }
        
        // 监听蓝牙设备连接通知（其他可能的格式）
        print("Adding observer for IOBluetoothDeviceConnectionNotification")
        NotificationCenter.default.addObserver(
            forName: Notification.Name("IOBluetoothDeviceConnectionNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let timestamp = localTimeString()
            print("\n=== IOBluetoothDeviceConnectionNotification received ===")
            print("Timestamp: \(timestamp)")
            print("Notification: \(notification)")
            print("Notification name: \(notification.name)")
            print("Notification object: \(notification.object ?? "nil")")
            
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device name: \(bluetoothDevice.name ?? "Unknown")")
                print("Device address: \(bluetoothDevice.addressString ?? "Unknown")")
                print("Device is connected: \(bluetoothDevice.isConnected())")
                
                // 立即刷新设备列表
                print("Calling retrieveConnectedDevices()...")
                self?.retrieveConnectedDevices()
                print("retrieveConnectedDevices() completed")
            } else {
                print("Notification object is not a IOBluetoothDevice")
                print("Notification object type: \(type(of: notification.object))")
            }
            print("===================================================")
        }
        
        // 监听蓝牙设备链接建立通知
        print("Adding observer for IOBluetoothDeviceLinkUpNotification")
        NotificationCenter.default.addObserver(
            forName: Notification.Name("IOBluetoothDeviceLinkUpNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let timestamp = localTimeString()
            print("\n=== IOBluetoothDeviceLinkUpNotification received ===")
            print("Timestamp: \(timestamp)")
            print("Notification: \(notification)")
            print("Notification name: \(notification.name)")
            print("Notification object: \(notification.object ?? "nil")")
            
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device name: \(bluetoothDevice.name ?? "Unknown")")
                print("Device address: \(bluetoothDevice.addressString ?? "Unknown")")
                print("Device is connected: \(bluetoothDevice.isConnected())")
                
                // 立即刷新设备列表
                print("Calling retrieveConnectedDevices()...")
                self?.retrieveConnectedDevices()
                print("retrieveConnectedDevices() completed")
            } else {
                print("Notification object is not a IOBluetoothDevice")
                print("Notification object type: \(type(of: notification.object))")
            }
            print("===================================================")
        }
        
        // 监听蓝牙设备就绪通知
        print("Adding observer for IOBluetoothDeviceReadyNotification")
        NotificationCenter.default.addObserver(
            forName: Notification.Name("IOBluetoothDeviceReadyNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let timestamp = localTimeString()
            print("\n=== IOBluetoothDeviceReadyNotification received ===")
            print("Timestamp: \(timestamp)")
            print("Notification: \(notification)")
            print("Notification name: \(notification.name)")
            print("Notification object: \(notification.object ?? "nil")")
            
            if let bluetoothDevice = notification.object as? IOBluetoothDevice {
                print("Device name: \(bluetoothDevice.name ?? "Unknown")")
                print("Device address: \(bluetoothDevice.addressString ?? "Unknown")")
                print("Device is connected: \(bluetoothDevice.isConnected())")
                
                // 立即刷新设备列表
                print("Calling retrieveConnectedDevices()...")
                self?.retrieveConnectedDevices()
                print("retrieveConnectedDevices() completed")
            } else {
                print("Notification object is not a IOBluetoothDevice")
                print("Notification object type: \(type(of: notification.object))")
            }
            print("===================================================")
        }
        
        print("=== Bluetooth notifications setup completed ===")
    }
    
    func startScanning() {
        if centralManager.state == .poweredOn {
            // 首先获取已连接的设备
            retrieveConnectedDevices()
            
            // 开始扫描，允许重复以获取更多设备
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            
            // 15秒后停止扫描
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                self.centralManager.stopScan()
                // 再次获取已连接的设备，确保没有遗漏
                self.retrieveConnectedDevices()
            }
            
            // 启动定期刷新定时器
            startRefreshTimer()
        }
    }
    
    private func startRefreshTimer() {
        print("\n=== Starting refresh timer ===")
        print("Current time: \(localTimeString())")
        
        // 取消现有的定时器
        if refreshTimer != nil {
            print("Cancelling existing refresh timer")
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        
        // 由于添加了完善的被动监听机制，将轮询间隔从30秒增加到60秒
        // 轮询现在仅作为备用机制
        print("Creating new refresh timer with 60-second interval")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] timer in
            print("\n=== Refresh timer fired ===")
            print("Current time: \(localTimeString())")
            print("Timer valid: \(timer.isValid)")
            self?.retrieveConnectedDevices()
            print("Refresh timer task completed")
        }
        
        print("Refresh timer started successfully")
        print("Timer valid: \(refreshTimer?.isValid ?? false)")
        print("=============================")
    }
    
    func stopRefreshTimer() {
        print("\n=== Stopping refresh timer ===")
        print("Current time: \(localTimeString())")
        
        if refreshTimer != nil {
            print("Cancelling refresh timer")
            refreshTimer?.invalidate()
            refreshTimer = nil
            print("Refresh timer stopped")
        } else {
            print("No active refresh timer to stop")
        }
        print("=============================")
    }
    
    public func retrieveConnectedDevices(completion: (() -> Void)? = nil) {
        let timestamp = localTimeString()
        print("\n=== retrieveConnectedDevices() started ===")
        print("Timestamp: \(timestamp)")
        print("Current devices count: \(devices.count)")
        
        // 方法1: 使用IOBluetooth框架获取已配对的设备
        print("Calling IOBluetoothDevice.pairedDevices()...")
        if let devicesArray = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            print("Found \(devicesArray.count) paired devices")
            
            // 保存已配对设备的ID，用于后续过滤
            var pairedDeviceIDs: Set<String> = []
            var newDevices: [BluetoothDevice] = []
            
            for (index, bluetoothDevice) in devicesArray.enumerated() {
                let deviceName = bluetoothDevice.name ?? "Unknown"
                
                // 使用设备的Mac地址作为ID
                let addressString = bluetoothDevice.addressString ?? ""
                var deviceID: String
                
                if !addressString.isEmpty {
                    // 使用地址字符串作为设备ID
                    deviceID = addressString
                } else {
                    // 如果没有地址，使用设备名称作为ID
                    deviceID = deviceName
                }
                
                pairedDeviceIDs.insert(deviceID)
                
                // 从持久化存储中读取设备的自定义图标路径
                let defaults = UserDefaults.standard
                let customIconName = defaults.string(forKey: "customIcon_\(deviceID)")
                
                // 检查设备是否已连接
                let isConnected = bluetoothDevice.isConnected()
                print("Device \(index + 1): \(deviceName)")
                print("  Address: \(addressString)")
                print("  Is connected: \(isConnected)")
                print("  Custom icon: \(customIconName ?? "nil")")
                
                // 创建蓝牙设备对象
                // 为不同类型的设备设置更合理的默认电量
                var batteryLevel: Int?
                if isConnected {
                    // 检查设备类型，为不同类型设置不同的默认电量范围
                    let lowerName = deviceName.lowercased()
                    if lowerName.contains("airpod") || lowerName.contains("headphone") || lowerName.contains("earbud") {
                        // 耳机类设备默认电量较高
                        batteryLevel = 70
                    } else if lowerName.contains("mouse") || lowerName.contains("keyboard") {
                        // 输入设备默认电量中等
                        batteryLevel = 60
                    } else if lowerName.contains("speaker") {
                        // 音箱默认电量较低
                        batteryLevel = 50
                    } else {
                        // 其他设备默认电量
                        batteryLevel = 65
                    }
                    print("  Battery level: \(batteryLevel ?? 0)%")
                } else {
                    print("  Battery level: nil (not connected)")
                }
                
                // 获取设备的默认图标名称
                let defaultIconName = self.getDeviceIconName(name: deviceName)
                
                let device = BluetoothDevice(
                    id: deviceID,
                    name: deviceName,
                    macAddress: addressString.isEmpty ? deviceID : addressString,
                    isConnected: isConnected,
                    batteryLevel: batteryLevel,
                    defaultIconName: defaultIconName,
                    customIconName: customIconName
                )
                
                newDevices.append(device)
            }
            
            // 替换设备列表，只保留已配对的设备
            print("Preparing to update devices list...")
            print("Old devices count: \(devices.count)")
            print("New devices count: \(newDevices.count)")
            
            DispatchQueue.main.async {
                let updateTimestamp = localTimeString()
                print("[\(updateTimestamp)] Updating devices list in main queue...")
                
                // 计算状态变化
                var connectedCount = 0
                var disconnectedCount = 0
                
                for device in newDevices {
                    if device.isConnected {
                        connectedCount += 1
                    } else {
                        disconnectedCount += 1
                    }
                }
                
                print("[\(updateTimestamp)] New state - Connected: \(connectedCount), Disconnected: \(disconnectedCount)")
                
                // 更新设备列表
                self.devices = newDevices
                print("[\(updateTimestamp)] Devices list updated successfully")
                print("[\(updateTimestamp)] Current devices count: \(self.devices.count)")
                
                // 发送设备列表更新通知，确保状态栏和菜单立即更新
                NotificationCenter.default.post(
                    name: Notification.Name("BluetoothDevicesUpdatedNotification"),
                    object: self,
                    userInfo: ["devices": self.devices]
                )
                print("[\(updateTimestamp)] BluetoothDevicesUpdatedNotification posted")
                
                // 立即触发StatusBarManager的updateStatusItems方法，确保状态栏图标立即更新
                DispatchQueue.main.async {
                    let appDelegate = NSApplication.shared.delegate as? AppDelegate
                    let statusBarManager = appDelegate?.statusBarManager
                    print("[\(updateTimestamp)] Directly triggering StatusBarManager update...")
                    
                    if let statusBarManager = statusBarManager {
                        print("[\(updateTimestamp)] Calling updateStatusItems with \(self.devices.count) devices...")
                        statusBarManager.updateStatusItems(devices: self.devices)
                        print("[\(updateTimestamp)] StatusBarManager update completed")
                    }
                }
                
                // 调用回调函数，通知调用者设备列表已经更新完成
                completion?()
            }
        } else {
            print("No paired devices found")
            // 没有配对设备时，清空设备列表
            DispatchQueue.main.async {
                let updateTimestamp = localTimeString()
                print("[\(updateTimestamp)] Clearing devices list - no paired devices found")
                self.devices.removeAll()
                print("[\(updateTimestamp)] Devices list cleared")
                
                // 发送设备列表更新通知，确保状态栏和菜单立即更新
                NotificationCenter.default.post(
                    name: Notification.Name("BluetoothDevicesUpdatedNotification"),
                    object: self,
                    userInfo: ["devices": self.devices]
                )
                print("[\(updateTimestamp)] BluetoothDevicesUpdatedNotification posted for empty list")
                
                // 立即触发StatusBarManager的updateStatusItems方法，确保状态栏图标立即更新
                DispatchQueue.main.async {
                    let appDelegate = NSApplication.shared.delegate as? AppDelegate
                    let statusBarManager = appDelegate?.statusBarManager
                    print("[\(updateTimestamp)] Directly triggering StatusBarManager update for empty list...")
                    
                    if let statusBarManager = statusBarManager {
                        print("[\(updateTimestamp)] Calling updateStatusItems with empty device list...")
                        statusBarManager.updateStatusItems(devices: self.devices)
                        print("[\(updateTimestamp)] StatusBarManager update completed for empty list")
                    }
                }
                
                // 调用回调函数，通知调用者设备列表已经更新完成
                completion?()
            }
        }
        print("=== retrieveConnectedDevices() completed ===")
    }
    
    // 连接尝试记录
    private var connectionAttempts: [String: Int] = [:]
    private let maxConnectionAttempts = 3
    
    func connectDevice(_ device: BluetoothDevice) {
        // 检查蓝牙状态
        guard centralManager.state == .poweredOn else {
            print("Bluetooth is not powered on, cannot connect to device: \(device.name)")
            return
        }
        
        // 检查设备是否已经连接
        if device.isConnected {
            print("Device is already connected: \(device.name)")
            return
        }
        
        // 尝试通过 IOBluetooth 框架连接
        if let bluetoothDevice = IOBluetoothDevice(addressString: device.id) {
            print("Attempting to connect to device: \(device.name) using IOBluetooth")
            
            // 记录连接尝试
            let attempts = connectionAttempts[device.id] ?? 0
            connectionAttempts[device.id] = attempts + 1
            
            // 开始连接
            let success = bluetoothDevice.openConnection()
            print("Connection attempt result: \(success)")
            
            // 设置连接超时
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self = self else { return }
                
                // 检查设备是否仍然未连接
                if let index = self.devices.firstIndex(where: { $0.id == device.id }), !self.devices[index].isConnected {
                    print("Connection timeout for device: \(device.name)")
                    
                    // 尝试重新连接
                    let currentAttempts = self.connectionAttempts[device.id] ?? 0
                    if currentAttempts < self.maxConnectionAttempts {
                        print("Retrying connection to device: \(device.name) (attempt \(currentAttempts + 1)/\(self.maxConnectionAttempts))")
                        self.connectDevice(device)
                    } else {
                        print("Max connection attempts reached for device: \(device.name)")
                        // 重置连接尝试计数
                        self.connectionAttempts[device.id] = 0
                    }
                }
            }
        } else {
            // 如果没有找到设备，尝试重新扫描
            print("Device not found: \(device.name), starting scan...")
            startScanning()
            
            // 扫描后再次尝试连接
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.connectDevice(device)
            }
        }
    }
    
    func disconnectDevice(_ device: BluetoothDevice) {
        // 检查设备是否已经断开
        if !device.isConnected {
            print("Device is already disconnected: \(device.name)")
            return
        }
        
        // 尝试通过 IOBluetooth 框架断开连接
        if let bluetoothDevice = IOBluetoothDevice(addressString: device.id) {
            print("Attempting to disconnect from device: \(device.name) using IOBluetooth")
            bluetoothDevice.closeConnection()
            
            // 重置连接尝试计数
            connectionAttempts[device.id] = 0
        } else {
            print("Device not found: \(device.name)")
        }
    }
    
    func updateDeviceCustomIcon(_ device: BluetoothDevice, iconName: String?) {
        // 更新设备的自定义图标
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].customIconName = iconName
            
            // 持久化存储设备的自定义图标路径
            let defaults = UserDefaults.standard
            if let iconName = iconName {
                defaults.set(iconName, forKey: "customIcon_\(device.id)")
            } else {
                defaults.removeObject(forKey: "customIcon_\(device.id)")
            }
            print("Persistent storage updated for device \(device.id): \(iconName ?? "no icon")")
        }
    }
    
    func updateDeviceName(_ device: BluetoothDevice, newName: String) {
        // 更新设备的名称
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].name = newName
        }
    }
    
    func updateDeviceBattery(_ device: BluetoothDevice, batteryLevel: Int) {
        // 更新设备的电量
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].batteryLevel = batteryLevel
            
            // 检查是否需要发送低电量提醒
            checkBatteryLevel(for: devices[index])
        }
    }
    
    // 尝试从设备获取真实电量
    func fetchRealBatteryLevel(for device: BluetoothDevice) -> Int? {
        // 这里是一个模拟实现，实际应用中需要根据设备类型和协议实现真实的电量获取
        // 不同设备类型可能需要不同的电量获取方法
        
        // 1. 对于支持HID协议的设备（如鼠标、键盘），可以通过IOKit获取电量
        // 2. 对于支持GATT协议的设备（如耳机），可以通过CoreBluetooth获取电量
        // 3. 对于其他设备，可以尝试通过IOBluetooth获取电量
        
        // 模拟实现：根据设备类型返回不同的电量范围
        let deviceName = device.name.lowercased()
        
        // 耳机类设备通常有较高的电量
        if deviceName.contains("airpod") || deviceName.contains("headphone") || deviceName.contains("earbud") {
            // 模拟AirPods等设备的电量，通常在40-90%之间
            return Int.random(in: 40...90)
        }
        // 输入设备（鼠标、键盘）电量通常较稳定
        else if deviceName.contains("mouse") || deviceName.contains("keyboard") {
            // 模拟输入设备电量，通常在30-80%之间
            return Int.random(in: 30...80)
        }
        // 音箱等设备电量差异较大
        else if deviceName.contains("speaker") {
            // 模拟音箱电量，通常在20-70%之间
            return Int.random(in: 20...70)
        }
        // 其他设备
        else {
            // 模拟其他设备电量，通常在25-75%之间
            return Int.random(in: 25...75)
        }
    }
    
    // 开始监听设备电量变化
    func startBatteryMonitoring() {
        // 每60秒检查一次电量
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 只检查已连接的设备
            for device in self.devices where device.isConnected {
                if let batteryLevel = self.fetchRealBatteryLevel(for: device) {
                    self.updateDeviceBattery(device, batteryLevel: batteryLevel)
                }
            }
        }
    }
    
    // 为设备设置连接状态检查
    private func setupConnectionCheckForDevice(_ device: IOBluetoothDevice) {
        let deviceName = device.name ?? "Unknown"
        let deviceAddress = device.addressString ?? "Unknown"
        
        print("Setting up connection check for device: \(deviceName), address: \(deviceAddress)")
        
        // 记录开始时间
        let startTime = Date()
        let maxCheckTime: TimeInterval = 10.0 // 最大检查时间10秒
        let checkInterval: TimeInterval = 0.5 // 每0.5秒检查一次
        
        // 创建检查连接状态的闭包
        let checkConnectionStatus: () -> Bool = {
            let currentTime = Date()
            let elapsedTime = currentTime.timeIntervalSince(startTime)
            
            // 检查是否超过最大检查时间
            if elapsedTime >= maxCheckTime {
                print("Connection check timeout for device: \(deviceName)")
                return true // 停止检查
            }
            
            // 检查设备连接状态
            let isConnected = device.isConnected()
            print("Connection check for \(deviceName): \(isConnected) (elapsed: \(elapsedTime)s)")
            
            if isConnected {
                print("Device \(deviceName) is now connected! Calling retrieveConnectedDevices()...")
                self.retrieveConnectedDevices()
                return true // 停止检查
            }
            
            return false // 继续检查
        }
        
        // 立即检查一次
        if checkConnectionStatus() {
            return
        }
        
        // 设置定时器，定期检查连接状态
        var timer: Timer?
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { _ in
            if checkConnectionStatus() {
                timer?.invalidate()
            }
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let timestamp = localTimeString()
        print("\n=== Bluetooth state changed ===")
        print("Timestamp: \(timestamp)")
        
        switch central.state {
        case .poweredOn:
            print("Bluetooth is on")
            // 当蓝牙开启时，立即开始扫描
            DispatchQueue.main.async {
                print("[\(localTimeString())] Starting Bluetooth device scan...")
                self.startScanning()
            }
        case .poweredOff:
            print("Bluetooth is off - cannot scan for devices")
        case .unauthorized:
            print("Bluetooth is unauthorized - check privacy settings")
        case .unsupported:
            print("Bluetooth is unsupported on this device")
        case .unknown:
            print("Bluetooth state is unknown")
        case .resetting:
            print("Bluetooth is resetting")
        @unknown default:
            print("Unknown Bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // 增加详细的调试信息
        // 屏蔽设备发现的详细日志
        
        // 检查是否已经添加过该设备
        if !peripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            peripherals.append(peripheral)
            // print("[\(localTimeString())] Peripheral discovered: \(peripheral.name ?? \"Unknown Device\")")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let timestamp = localTimeString()
        print("\n=== Device connected ===")
        print("Timestamp: \(timestamp)")
        print("Peripheral connected: \(peripheral.name ?? "Unknown") - \(peripheral.identifier.uuidString)")
        
        // 更新设备连接状态
        DispatchQueue.main.async {
            if let index = self.devices.firstIndex(where: { $0.id == peripheral.identifier.uuidString }) {
                print("[\(localTimeString())] Updating device state for: \(self.devices[index].name)")
                self.devices[index].isConnected = true
                // 尝试获取真实电量，失败则使用默认值
                var batteryLevel: Int
                if let realBatteryLevel = self.fetchRealBatteryLevel(for: self.devices[index]) {
                    batteryLevel = realBatteryLevel
                } else {
                    // 如果无法获取真实电量，使用基于设备类型的默认值
                    let deviceName = self.devices[index].name
                    let lowerName = deviceName.lowercased()
                    if lowerName.contains("airpod") || lowerName.contains("headphone") || lowerName.contains("earbud") {
                        // 耳机类设备默认电量较高
                        batteryLevel = 70
                    } else if lowerName.contains("mouse") || lowerName.contains("keyboard") {
                        // 输入设备默认电量中等
                        batteryLevel = 60
                    } else if lowerName.contains("speaker") {
                        // 音箱默认电量较低
                        batteryLevel = 50
                    } else {
                        // 其他设备默认电量
                        batteryLevel = 65
                    }
                }
                self.devices[index].batteryLevel = batteryLevel
                print("[\(localTimeString())] Device \(self.devices[index].name) connected with battery: \(batteryLevel)%")
                
                // 检查是否需要发送低电量提醒
                self.checkBatteryLevel(for: self.devices[index])
                
                // 设备连接后会通过状态监听自动更新状态栏
                print("[\(localTimeString())] Device connected, status bar will be updated via listener")
            } else {
                print("[\(localTimeString())] Device not found in devices list")
            }
        }
        print("========================")
    }
    
    private func checkBatteryLevel(for device: BluetoothDevice) {
        let timestamp = localTimeString()
        print("[\(timestamp)] Checking battery level for: \(device.name)")
        // 检查设备电量并发送低电量提醒
        if let batteryLevel = device.batteryLevel, batteryLevel < 20 {
            print("[\(timestamp)] Low battery detected: \(batteryLevel)%")
            sendLowBatteryNotification(for: device)
        }
    }
    
    private func sendLowBatteryNotification(for device: BluetoothDevice) {
        let timestamp = localTimeString()
        print("[\(timestamp)] Sending low battery notification for: \(device.name)")
        // 检查是否在支持的环境中运行
        if Bundle.main.bundlePath != "" && Bundle.main.bundleIdentifier != nil {
            // 创建通知内容
            let content = UNMutableNotificationContent()
            content.title = "Low Battery"
            content.body = "\(device.name) battery is running low: \(device.batteryLevel ?? 0)%"
            content.sound = UNNotificationSound.default
            
            // 创建通知触发器
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            
            // 创建通知请求
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            
            // 添加通知请求
            let center = UNUserNotificationCenter.current()
            center.add(request) { error in
                if let error = error {
                        print("[\(localTimeString())] Error sending notification: \(error)")
                    } else {
                        print("[\(localTimeString())] Notification sent successfully")
                    }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let timestamp = localTimeString()
        print("\n=== CBCentralManager didDisconnectPeripheral ===")
        print("Timestamp: \(timestamp)")
        print("Peripheral name: \(peripheral.name ?? "Unknown")")
        print("Peripheral UUID: \(peripheral.identifier.uuidString)")
        
        if let error = error {
            print("Disconnection error: \(error)")
            print("Error code: \((error as NSError).code)")
            print("Error domain: \((error as NSError).domain)")
            // 处理断开连接错误
            handleBluetoothError(error, for: peripheral)
        } else {
            print("Disconnection completed without error")
        }
        
        // 立即检查中央管理器状态
        print("Central manager state: \(central.state)")
        
        // 更新设备断开状态
        print("Updating device state in main queue...")
        DispatchQueue.main.async {
            let updateTimestamp = localTimeString()
            print("[\(updateTimestamp)] Main queue update started")
            
            if let index = self.devices.firstIndex(where: { $0.id == peripheral.identifier.uuidString }) {
                print("[\(updateTimestamp)] Found device in list: \(self.devices[index].name)")
                print("[\(updateTimestamp)] Current device state - isConnected: \(self.devices[index].isConnected)")
                
                // 更新设备状态
                self.devices[index].isConnected = false
                self.devices[index].batteryLevel = nil
                
                print("[\(updateTimestamp)] Updated device state - isConnected: \(self.devices[index].isConnected)")
                print("[\(updateTimestamp)] Battery level cleared")
                
                // 手动调用retrieveConnectedDevices确保状态同步
                print("[\(updateTimestamp)] Calling retrieveConnectedDevices() for sync...")
                self.retrieveConnectedDevices()
                print("[\(updateTimestamp)] retrieveConnectedDevices() completed")
                
                // 设备断开后会通过状态监听自动更新状态栏
                print("[\(updateTimestamp)] Device disconnected, status bar will be updated")
            } else {
                print("[\(updateTimestamp)] Device not found in devices list")
                print("[\(updateTimestamp)] Calling retrieveConnectedDevices() to refresh list...")
                self.retrieveConnectedDevices()
            }
            print("[\(updateTimestamp)] Main queue update completed")
        }
        print("=== Disconnection handling completed ===")

    }
    
    // 添加连接错误处理
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let timestamp = localTimeString()
        print("\n=== Connection failed ===")
        print("Timestamp: \(timestamp)")
        print("Failed to connect to: \(peripheral.name ?? "Unknown") - \(peripheral.identifier.uuidString)")
        
        if let error = error {
            print("Connection error: \(error)")
            handleBluetoothError(error, for: peripheral)
        }
        
        // 重置连接尝试计数
        let deviceID = peripheral.identifier.uuidString
        connectionAttempts[deviceID] = 0
    }
    
    // 处理蓝牙错误
    private func handleBluetoothError(_ error: Error, for peripheral: CBPeripheral) {
        let errorCode = (error as NSError).code
        print("Bluetooth error code: \(errorCode)")
        
        switch errorCode {
        case CBError.Code.connectionTimeout.rawValue:
            print("Connection timeout - device may be out of range or turned off")
        case CBError.Code.connectionFailed.rawValue:
            print("Connection failed - device may be busy or unavailable")
        case CBError.Code.peripheralDisconnected.rawValue:
            print("Peripheral disconnected - connection lost")
        default:
            print("Unknown Bluetooth error")
        }
    }
    
    // 根据设备名称获取图标名称
    private func getDeviceIconName(name: String) -> String {
        let lowerName = name.lowercased()
        if lowerName.contains("airpod") {
            return "airpods"
        } else if lowerName.contains("mouse") {
            return "mouse"
        } else if lowerName.contains("keyboard") {
            return "keyboard"
        } else if lowerName.contains("headphone") || lowerName.contains("headset") || lowerName.contains("bud") || lowerName.contains("earbud") {
            return "headphones"
        } else if lowerName.contains("speaker") {
            return "speaker"
        } else {
            return "bluetooth"
        }
    }
}

// 窗口代理类
class WindowDelegate: NSObject, NSWindowDelegate {
    weak var statusBarManager: StatusBarManager?
    
    func windowWillClose(_ notification: Notification) {
        statusBarManager?.cleanupSettingsWindow()
    }
}

// 状态栏管理器
class StatusBarManager {
    private var statusItems: [NSStatusItem] = []
    private var deviceStatusItems: [String: (statusItem: NSStatusItem, device: BluetoothDevice, popover: NSPopover?)] = [:] // 存储设备ID到状态栏图标、设备信息和气泡的映射
    private var bluetoothManager: BluetoothManager
    private var cancellables = Set<AnyCancellable>()
    private var showDeviceIcons: [String: Bool] = [:] // 存储设备图标显示设置
    private var lastDeviceStates: [String: (isConnected: Bool, customIconName: String?, batteryLevel: Int?)] = [:] // 存储设备的最后状态
    private var settingsWindow: NSWindow? // 存储设置窗口引用，避免被释放
    private var settingsWindowDelegate: WindowDelegate? // 存储窗口代理引用，确保生命周期与窗口一致
    private var settingsHostingController: NSViewController? // 存储设置窗口的hosting controller引用
    private var lastClickLocation: NSPoint? // 存储最后一次鼠标点击位置
    
    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        
        // 从 UserDefaults 加载设备显示设置
        loadDeviceDisplaySettings()
        
        // 监听设备显示设置变化
        NotificationCenter.default.addObserver(self, selector: #selector(reloadDisplaySettings), name: NSNotification.Name("DeviceDisplaySettingsChanged"), object: nil)
        
        // 监听设备变化
        bluetoothManager.$devices.sink {[weak self] devices in
            self?.updateStatusItems(devices: devices)
        }
        .store(in: &cancellables)
        
        // 监听设备列表更新通知，确保立即刷新状态栏图标
        NotificationCenter.default.addObserver(
            forName: Notification.Name("BluetoothDevicesUpdatedNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let timestamp = localTimeString()
            print("[\(timestamp)] BluetoothDevicesUpdatedNotification received in StatusBarManager")
            if let devices = notification.userInfo?["devices"] as? [BluetoothDevice] {
                print("[\(timestamp)] Updating status items with \(devices.count) devices")
                self?.updateStatusItems(devices: devices)
            } else {
                print("[\(timestamp)] No devices found in notification userInfo")
                // 直接使用蓝牙管理器的设备列表
                self?.updateStatusItems(devices: self?.bluetoothManager.devices ?? [])
            }
            print("[\(timestamp)] Status bar update completed")
        }
    }
    
    @objc private func reloadDisplaySettings() {
        loadDeviceDisplaySettings()
        updateStatusItems(devices: bluetoothManager.devices)
        print("Display settings reloaded")
    }
    
    private func loadDeviceDisplaySettings() {
        let defaults = UserDefaults.standard
        if let savedSettings = defaults.dictionary(forKey: "deviceDisplaySettings") as? [String: Bool] {
            showDeviceIcons = savedSettings
            print("Loaded device display settings: \(showDeviceIcons)")
        }
    }
    
    private func saveDeviceDisplaySettings() {
        let defaults = UserDefaults.standard
        defaults.set(showDeviceIcons, forKey: "deviceDisplaySettings")
        defaults.synchronize()
        print("Saved device display settings: \(showDeviceIcons)")
    }
    
    internal func updateStatusItems(devices: [BluetoothDevice]) {
        // 确保在主队列中执行
        DispatchQueue.main.async {
            let timestamp = localTimeString()
            print("[\(timestamp)] === 更新状态栏图标 ===")
            print("[\(timestamp)] 当前设备数量: \(devices.count)")
            print("[\(timestamp)] 当前状态栏图标数量: \(self.statusItems.count)")
            print("[\(timestamp)] 当前设备状态栏图标数量: \(self.deviceStatusItems.count)")
            
            // 保留应用图标，只处理设备图标
            var appStatusItem: NSStatusItem?
            if !self.statusItems.isEmpty {
                // 保存第一个状态项（应用图标）
                appStatusItem = self.statusItems.first
                print("[\(timestamp)] 应用图标已存在")
            }
            
            // 如果没有应用图标，创建一个
            if appStatusItem == nil {
                appStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                if let button = appStatusItem?.button {
                    // 使用自定义应用图标
                    if let customImage = self.getCustomIcon() {
                        // 确保自定义图标不使用模板模式，保持原始白色
                        customImage.isTemplate = false
                        button.image = customImage
                        print("[\(timestamp)] 使用自定义应用图标")
                    } else {
                        // 如果自定义图标不可用，使用系统图标
                        if let image = NSImage(systemSymbolName: "bluetooth", accessibilityDescription: "Bluetooth") {
                            // 确保系统图标不使用模板模式，保持原始白色
                            image.isTemplate = false
                            button.image = image
                            print("[\(timestamp)] 使用系统应用图标")
                        } else {
                            // 如果系统图标也不可用，使用随机图标
                            let randomIcon = self.generateRandomIcon()
                            // 确保随机图标不使用模板模式，保持原始颜色
                            randomIcon.isTemplate = false
                            button.image = randomIcon
                            print("[\(timestamp)] 使用随机应用图标")
                        }
                    }
                    button.action = #selector(self.showDeviceMenu)
                    button.target = self
                    button.toolTip = "BtBar - Bluetooth Device Manager"
                }
                self.statusItems.append(appStatusItem!)
                print("[\(timestamp)] 创建新的应用图标")
            }
            
            // 收集当前需要显示的设备
            var devicesToShow: [BluetoothDevice] = []
            for device in devices {
                // 检查条件：设备已连接 + 配置了显示图标
                let shouldShowIcon = device.isConnected && (self.showDeviceIcons[device.id] ?? true)
                print("[\(timestamp)] 设备: \(device.name), 已连接: \(device.isConnected), 显示图标: \(shouldShowIcon), ID: \(device.id)")
                if shouldShowIcon {
                    devicesToShow.append(device)
                    print("[\(timestamp)] 添加到显示列表: \(device.name), ID: \(device.id)")
                }
            }
            print("[\(timestamp)] 需要显示的设备数量: \(devicesToShow.count)")
            print("[\(timestamp)] Total devices: \(devices.count), Connected devices: \(devices.filter { $0.isConnected }.count)")
            
            // 移除不再需要显示的设备图标
            var devicesToRemove: [String] = []
            for (deviceID, deviceInfo) in self.deviceStatusItems {
                if !devicesToShow.contains(where: { $0.id == deviceID }) {
                    devicesToRemove.append(deviceID)
                    print("[\(timestamp)] 移除设备图标: \(deviceID)")
                    // 从状态栏中移除
                    deviceInfo.statusItem.button?.removeFromSuperview()
                    // 从statusItems中移除
                    if let index = self.statusItems.firstIndex(where: { $0 == deviceInfo.statusItem }) {
                        self.statusItems.remove(at: index)
                        print("[\(timestamp)] 从statusItems中移除索引: \(index)")
                    }
                }
            }
            for deviceID in devicesToRemove {
                self.deviceStatusItems.removeValue(forKey: deviceID)
                self.lastDeviceStates.removeValue(forKey: deviceID)
                print("[\(timestamp)] 移除设备图标映射: \(deviceID)")
            }
            
            // 更新或添加需要显示的设备图标
            for device in devicesToShow {
                print("[\(timestamp)] 处理设备: \(device.name), ID: \(device.id)")
                
                // 检查设备状态是否发生变化
                let currentState = (isConnected: device.isConnected, customIconName: device.customIconName, batteryLevel: device.batteryLevel)
                let lastState = self.lastDeviceStates[device.id]
                
                // 检查是否是从断开变为连接状态
                let wasDisconnected = lastState == nil || !lastState!.isConnected
                let isNowConnected = device.isConnected
                let justConnected = wasDisconnected && isNowConnected
                
                // 如果设备状态没有变化，跳过更新
                if let lastState = lastState, lastState == currentState {
                    print("[\(timestamp)] 设备状态未变化，跳过更新: \(device.name)")
                    continue
                }
                
                // 更新设备状态
                self.lastDeviceStates[device.id] = currentState
                print("[\(timestamp)] 更新设备状态: \(device.name), 自定义图标: \(device.customIconName ?? "无")")
                print("[\(timestamp)] 设备连接状态变化: 之前=\(wasDisconnected ? "断开" : "连接"), 现在=\(isNowConnected ? "连接" : "断开"), 刚刚连接=\(justConnected)")
                
                // 获取或创建状态栏图标
                let deviceStatusItem: NSStatusItem
                if let existingItem = self.deviceStatusItems[device.id] {
                    // 使用现有的状态栏图标
                    deviceStatusItem = existingItem.statusItem
                    print("[\(timestamp)] 使用现有状态栏图标: \(device.name)")
                } else {
                    // 创建一个新的状态栏图标
                    deviceStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                    self.statusItems.append(deviceStatusItem)
                    print("[\(timestamp)] 创建新的状态栏图标: \(device.name)")
                }
                
                if let button = deviceStatusItem.button {
                    // 确保按钮大小正确
                    button.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
                    
                    // 使用可复用的方法获取设备图标
                    if let deviceIcon = self.getDeviceIcon(for: device, size: NSSize(width: 16, height: 16), applyTemplateForDisconnected: false) {
                        // 确保图片大小正确
                        deviceIcon.size = NSSize(width: 16, height: 16)
                        // 确保图标不使用模板模式，保持原始白色
                        deviceIcon.isTemplate = false
                        button.image = deviceIcon
                        // 确保图片显示模式正确
                        button.imageScaling = .scaleProportionallyUpOrDown
                        print("[\(timestamp)] 在状态栏显示设备图标: \(device.name)")
                    } else {
                        // 如果所有图标都不可用，使用随机图标
                        let randomIcon = self.generateRandomIcon()
                        // 确保随机图标不使用模板模式，保持原始颜色
                        randomIcon.isTemplate = false
                        button.image = randomIcon
                        print("[\(timestamp)] 使用随机图标为设备: \(device.name)")
                    }
                    
                    // 为设备图标设置不同的action，点击时显示设备详情信息
                    button.action = #selector(self.showDeviceDetails)
                    button.target = self
                    // 为设备图标设置toolTip，鼠标移动时显示设备名称
                    button.toolTip = device.name
                    // 确保按钮可见
                    button.isHidden = false
                    print("[\(timestamp)] 更新状态栏图标完成: \(device.name)")
                }
                
                // 更新设备状态栏图标映射，存储设备信息和气泡
                self.deviceStatusItems[device.id] = (statusItem: deviceStatusItem, device: device, popover: nil)
                
                // 如果设备刚刚连接，自动弹出气泡详情
                if justConnected {
                    print("[\(timestamp)] 设备刚刚连接，自动弹出气泡详情: \(device.name)")
                    // 延迟一点时间，确保图标已经完全创建
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // 模拟点击状态栏图标，触发气泡显示，并设置5秒后自动关闭
                        self.showDeviceDetailsForDevice(device, autoClose: true)
                    }
                    
                    // 尝试将系统默认声音设备切换为当前连接的蓝牙设备
                    print("[\(timestamp)] 尝试切换系统默认声音设备为: \(device.name)")
                    
                    // 延迟2秒，确保音频设备完全初始化
                    print("[\(timestamp)] 等待2秒，确保音频设备完全初始化...")
                    usleep(2000000) // 2000ms
                    
                    // 打印当前所有可用的音频设备
                    let allAudioDevices = getAudioDevices()
                    print("[\(timestamp)] 可用音频设备列表:")
                    for audioDevice in allAudioDevices {
                        print("[\(timestamp)]   - \(audioDevice.name) (ID: \(audioDevice.id))")
                    }
                    
                    // 获取切换前的默认音频设备
                    if let beforeDevice = getCurrentDefaultAudioDevice() {
                        print("[\(timestamp)] 切换前默认音频设备: \(beforeDevice.name) (ID: \(beforeDevice.id))")
                    }
                    
                    // 收集所有匹配的音频设备
                    let lowerDeviceName = device.name.lowercased()
                    let matchingDevices = allAudioDevices.filter { $0.name.lowercased().contains(lowerDeviceName) }
                    print("[\(timestamp)] 找到 \(matchingDevices.count) 个匹配的音频设备")
                    
                    // 尝试切换到每个匹配的设备
                    for (index, audioDevice) in matchingDevices.enumerated() {
                        print("[\(timestamp)] 尝试切换到匹配设备 \(index + 1)/\(matchingDevices.count): \(audioDevice.name) (ID: \(audioDevice.id))")
                        
                        // 尝试切换默认音频设备
                        let success = setDefaultAudioDevice(audioDevice.id)
                        print("[\(timestamp)] 切换默认音频设备结果: \(success ? "成功" : "失败")")
                        
                        // 再次获取当前默认音频设备，确认切换是否成功
                        if success {
                            // 等待1秒，让系统完成切换
                            usleep(1000000) // 1000ms
                            
                            print("[\(timestamp)] 切换后验证默认音频设备...")
                            if let afterDevice = getCurrentDefaultAudioDevice() {
                                print("[\(timestamp)] 切换后默认音频设备: \(afterDevice.name) (ID: \(afterDevice.id))")
                                if afterDevice.id == audioDevice.id {
                                    print("[\(timestamp)] ✅ 音频设备切换成功!")
                                    // 切换成功，退出循环
                                    break
                                } else {
                                    print("[\(timestamp)] ❌ 音频设备切换失败，当前默认设备与目标设备不匹配")
                                    // 继续尝试下一个设备
                                }
                            }
                        }
                    }
                    
                    print("[\(timestamp)] 音频设备切换流程完成")
                }
            }
            print("[\(timestamp)] 状态栏图标更新完成，当前状态栏图标数量: \(self.statusItems.count)")
            print("[\(timestamp)] =====================")
            
            // 清除菜单缓存，确保下次打开菜单时显示最新的设备状态
            self.cachedMenu = nil
            print("[\(timestamp)] Menu cache cleared due to device status changes")
        }
    }
    
    private func getCustomIcon() -> NSImage? {
        // 从Resources目录获取自定义图标
        let bundle = Bundle.main
        
        // 尝试不同的路径和尺寸，优先使用原始的btbar.png
        let iconNames = ["btbar", "btbar_32", "btbar_16"]
        
        for iconName in iconNames {
            // 尝试从应用bundle获取
            if let path = bundle.path(forResource: iconName, ofType: "png") {
                let image = NSImage(contentsOfFile: path)
                // 设置图标尺寸
                if let image = image {
                    // 使用原始图片进行缩放，设置为16x16像素
                    image.size = NSSize(width: 16, height: 16)
                    return image
                }
            }
            
            // 尝试直接从项目根目录的Resources文件夹获取
            let currentDir = FileManager.default.currentDirectoryPath
            let resourcesPath = currentDir + "/Resources/" + iconName + ".png"
            if FileManager.default.fileExists(atPath: resourcesPath) {
                let image = NSImage(contentsOfFile: resourcesPath)
                // 设置图标尺寸
                if let image = image {
                    // 使用原始图片进行缩放，设置为16x16像素
                    image.size = NSSize(width: 16, height: 16)
                    return image
                }
            }
            
            // 尝试从可执行文件所在目录的Resources文件夹获取
            if let executablePath = Bundle.main.executablePath {
                let executableDir = (executablePath as NSString).deletingLastPathComponent
                let resourcesPath = executableDir + "/Resources/" + iconName + ".png"
                if FileManager.default.fileExists(atPath: resourcesPath) {
                    let image = NSImage(contentsOfFile: resourcesPath)
                    // 设置图标尺寸
                    if let image = image {
                        // 使用原始图片进行缩放，设置为16x16像素
                        image.size = NSSize(width: 16, height: 16)
                        return image
                    }
                }
            }
        }
        
        return nil
    }
    
    // 获取设备图标，可复用的方法
    private func getDeviceIcon(for device: BluetoothDevice, size: NSSize, applyTemplateForDisconnected: Bool = true) -> NSImage? {
        // 尝试使用设备的自定义图标
        if let customIconPath = device.customIconName {
            // 尝试使用用户选择的图片文件
            if let image = NSImage(contentsOfFile: customIconPath) {
                // 缩放图片到指定大小
                let scaledImage = scaleImage(image, toSize: size)
                // 始终设置为模板图片，确保在深色模式下正确显示
                scaledImage.isTemplate = true
                return scaledImage
            } else {
                print("无法读取用户选择的图片文件: \(customIconPath)")
            }
        }
        
        // 如果没有自定义图标或自定义图标不可用，使用系统图标
        let systemIconName = getSystemIconName(for: device.defaultIconName)
        if let image = NSImage(systemSymbolName: systemIconName, accessibilityDescription: device.name) {
            // 缩放系统图标到指定大小
            let scaledImage = scaleImage(image, toSize: size)
            // 始终设置为模板图片，确保在深色模式下正确显示
            scaledImage.isTemplate = true
            return scaledImage
        }
        
        // 如果系统图标也不可用，使用应用图标
        if let customImage = getCustomIcon() {
            let scaledImage = scaleImage(customImage, toSize: size)
            // 始终设置为模板图片，确保在深色模式下正确显示
            scaledImage.isTemplate = true
            return scaledImage
        }
        
        // 如果所有图标都不可用，返回nil
        return nil
    }
    
    // 优化菜单显示，避免卡顿
    private var cachedMenu: NSMenu?
    private var lastMenuUpdate: Date = Date.distantPast
    private var lastDeviceIcons: [String: String?] = [:]
    
    private func generateRandomIcon() -> NSImage {
        // 首先尝试使用自定义图标
        if let customImage = getCustomIcon() {
            return customImage
        }
        
        // 如果自定义图标不可用，使用系统图标
        let icons = ["bluetooth", "circle", "star", "heart", "square", "triangle"]
        let randomIcon = icons.randomElement() ?? "bluetooth"
        
        if let image = NSImage(systemSymbolName: randomIcon, accessibilityDescription: "Random Icon") {
            return image
        }
        
        // 如果所有图标都不可用，创建一个简单的红色方块图标
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 20).fill()
        image.unlockFocus()
        return image
    }
    
    private func getSystemIconName(for deviceIconName: String) -> String {
        switch deviceIconName {
        case "airpods":
            return "headphones"
        case "mouse":
            return "mouse"
        case "keyboard":
            return "keyboard"
        case "headphones":
            return "headphones"
        case "speaker":
            return "speaker"
        default:
            return "bluetooth"
        }
    }
    
    private func scaleImage(_ image: NSImage, toSize size: NSSize) -> NSImage {
        let scaledImage = NSImage(size: size)
        scaledImage.lockFocus()
        defer { scaledImage.unlockFocus() }
        
        // 使用高质量插值以获得平滑效果
        if let context = NSGraphicsContext.current?.cgContext {
            context.interpolationQuality = .high
        }
        
        // 计算等比例缩放的尺寸
        let imageSize = image.size
        let widthRatio = size.width / imageSize.width
        let heightRatio = size.height / imageSize.height
        let scaleFactor = min(widthRatio, heightRatio)
        
        // 确保坐标和尺寸是整数，避免浮点数坐标导致的模糊和锯齿
        let scaledWidth = round(imageSize.width * scaleFactor)
        let scaledHeight = round(imageSize.height * scaleFactor)
        let originX = round((size.width - scaledWidth) / 2)
        let originY = round((size.height - scaledHeight) / 2)
        
        // 绘制缩放后的图片
        let rect = NSRect(x: originX, y: originY, width: scaledWidth, height: scaledHeight)
        image.draw(in: rect, from: NSRect(origin: .zero, size: imageSize), operation: .sourceOver, fraction: 1.0)
        
        return scaledImage
    }
    
    @objc private func showDeviceMenu() {
        // 强制更新菜单，确保显示最新的设备状态
        // 移除缓存，每次都创建新菜单
        cachedMenu = nil
        
        // 首先同步获取最新的设备状态，然后再创建菜单
        print("[\(localTimeString())] showDeviceMenu - Started, refreshing device status...")
        
        // 直接使用IOBluetoothDevice的isConnected()方法来检查设备的实时连接状态
        // 这样可以确保获取到最新的设备连接状态，而不依赖于bluetoothManager.devices中的缓存状态
        if let devicesArray = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            print("[\(localTimeString())] Found \(devicesArray.count) paired devices")
            
            // 创建新菜单
            let menu = NSMenu()
            // 设置菜单外观为暗色，确保与气泡背景一致
            menu.appearance = NSAppearance(named: .darkAqua)
            
            // 移除背景修改代码，确保菜单能够正常弹出
            
            // 分离已连接和未连接的设备
            var connectedDevices: [BluetoothDevice] = []
            var disconnectedDevices: [BluetoothDevice] = []
            
            for bluetoothDevice in devicesArray {
                let deviceName = bluetoothDevice.name ?? "Unknown"
                
                // 使用设备的Mac地址作为ID
                let addressString = bluetoothDevice.addressString ?? ""
                var deviceID: String
                
                if !addressString.isEmpty {
                    // 使用地址字符串作为设备ID
                    deviceID = addressString
                } else {
                    // 如果没有地址，使用设备名称作为ID
                    deviceID = deviceName
                }
                
                // 从持久化存储中读取设备的自定义图标路径
                let defaults = UserDefaults.standard
                let customIconName = defaults.string(forKey: "customIcon_\(deviceID)")
                
                // 检查设备是否已连接（使用实时状态）
                let isConnected = bluetoothDevice.isConnected()
                
                // 创建蓝牙设备对象
                var batteryLevel: Int?
                if isConnected {
                    // 检查设备类型，为不同类型设置不同的默认电量范围
                    let lowerName = deviceName.lowercased()
                    if lowerName.contains("airpod") || lowerName.contains("headphone") || lowerName.contains("earbud") {
                        // 耳机类设备默认电量较高
                        batteryLevel = 70
                    } else if lowerName.contains("mouse") || lowerName.contains("keyboard") {
                        // 输入设备默认电量中等
                        batteryLevel = 60
                    } else if lowerName.contains("speaker") {
                        // 音箱默认电量较低
                        batteryLevel = 50
                    } else {
                        // 其他设备默认电量
                        batteryLevel = 65
                    }
                }
                
                let device = BluetoothDevice(
                    id: deviceID,
                    name: deviceName,
                    macAddress: addressString.isEmpty ? deviceID : addressString,
                    isConnected: isConnected,
                    batteryLevel: batteryLevel,
                    defaultIconName: getDeviceIconName(for: deviceName),
                    customIconName: customIconName
                )
                
                if isConnected {
                    connectedDevices.append(device)
                } else {
                    disconnectedDevices.append(device)
                }
            }
            
            print("[\(localTimeString())] Menu creation - Connected devices: \(connectedDevices.count), Disconnected devices: \(disconnectedDevices.count)")
            for device in connectedDevices {
                print("[\(localTimeString())] Connected device: \(device.name), ID: \(device.id)")
            }
            for device in disconnectedDevices {
                print("[\(localTimeString())] Disconnected device: \(device.name), ID: \(device.id)")
            }
            
            // 先添加已连接的设备
            if !connectedDevices.isEmpty {
                for device in connectedDevices {
                    self.addDeviceMenuItem(to: menu, device: device)
                }
            }
            
            // 再添加未连接的设备
            if !disconnectedDevices.isEmpty {
                // 直接添加未连接设备，不添加分隔线
                for device in disconnectedDevices {
                    self.addDeviceMenuItem(to: menu, device: device)
                }
            }
            
            // 添加分隔线和设置项
            if !devicesArray.isEmpty {
                menu.addItem(createVisualEffectSeparator())
            } else {
                // 添加无设备提示
                let noDevicesItem = NSMenuItem(title: "No paired Bluetooth devices found", action: nil, keyEquivalent: "")
                noDevicesItem.isEnabled = false
                menu.addItem(noDevicesItem)
                menu.addItem(createVisualEffectSeparator())
            }
            
            // 添加设置项
            // 暂时屏蔽设置菜单以避免崩溃
            // if let settingsImage = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings") {
            //     let settingsItem = createMenuItemWithVisualEffect(title: "Settings", action: #selector(self.openSettings), keyEquivalent: "", image: settingsImage, target: self)
            //     menu.addItem(settingsItem)
            // }
            
            // 添加退出项
            if let quitImage = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit") {
                let quitItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                quitItem.target = nil
                quitItem.image = nil
                quitItem.isEnabled = true
                // 创建自定义视图来控制图标的位置
                let quitView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
                quitView.wantsLayer = true
                quitView.layer?.backgroundColor = NSColor.clear.cgColor
                
                // 创建图标按钮
                let quitButton = HoverableButton(frame: NSRect(x: 170, y: 4, width: 24, height: 24))
                quitButton.setButtonType(.momentaryPushIn)
                quitButton.bezelStyle = .texturedRounded
                quitButton.image = quitImage
                quitButton.target = self
                quitButton.action = #selector(self.quitApp)
                quitButton.isBordered = false
                quitButton.wantsLayer = true
                quitButton.layer?.backgroundColor = NSColor.clear.cgColor
                // 设置statusBarManager引用
                quitButton.statusBarManager = self
                // 添加鼠标跟踪区域
                let trackingArea = NSTrackingArea(
                    rect: quitButton.bounds,
                    options: [.mouseEnteredAndExited, .activeAlways],
                    owner: quitButton,
                    userInfo: nil
                )
                quitButton.addTrackingArea(trackingArea)
                quitView.addSubview(quitButton)
                
                quitItem.view = quitView
                menu.addItem(quitItem)
            }
            
            // 添加带有毛玻璃效果的空白菜单项，覆盖菜单底部边缘
            // menu.addItem(createVisualEffectSpacer())
            
            // 缓存菜单
            self.cachedMenu = menu
            self.lastMenuUpdate = Date()
            
            // 显示菜单
            if let statusItem = self.statusItems.first, let button = statusItem.button {
                // 直接弹出菜单，不设置statusItem.menu属性，避免系统缓存菜单对象
                // 向左移动20个像素，向下移动10个像素
                menu.popUp(positioning: nil, at: NSPoint(x: -20, y: button.bounds.height + 10), in: button)
            } else {
                // 如果按钮不可用，使用默认位置
                menu.popUp(positioning: nil, at: NSPoint(x: -20, y: 10), in: nil)
            }
            
            // 同时更新bluetoothManager.devices，确保其他地方也能获取到最新的设备状态
            bluetoothManager.retrieveConnectedDevices()
            
            print("[\(localTimeString())] showDeviceMenu - Completed")
        } else {
            // 没有配对设备时
            print("[\(localTimeString())] No paired devices found")
            
            // 创建新菜单
            let menu = NSMenu()
            // 设置菜单外观为暗色，确保与气泡背景一致
            menu.appearance = NSAppearance(named: .darkAqua)
            
            // 移除背景修改代码，确保菜单能够正常弹出
            
            // 添加无设备提示
            let noDevicesItem = NSMenuItem(title: "No paired Bluetooth devices found", action: nil, keyEquivalent: "")
            noDevicesItem.isEnabled = false
            menu.addItem(noDevicesItem)
            menu.addItem(createVisualEffectSeparator())
            
            // 添加设置项
            // 暂时屏蔽设置菜单以避免崩溃
            // if let settingsImage = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings") {
            //     let settingsItem = createMenuItemWithVisualEffect(title: "Settings", action: #selector(self.openSettings), keyEquivalent: "", image: settingsImage, target: self)
            //     menu.addItem(settingsItem)
            // }
            
            // 添加退出项
            if let quitImage = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit") {
                let quitItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                quitItem.target = nil
                quitItem.image = nil
                quitItem.isEnabled = true
                // 创建自定义视图来控制图标的位置
                let quitView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
                quitView.wantsLayer = true
                quitView.layer?.backgroundColor = NSColor.clear.cgColor
                
                // 创建图标按钮
                let quitButton = HoverableButton(frame: NSRect(x: 170, y: 4, width: 24, height: 24))
                quitButton.setButtonType(.momentaryPushIn)
                quitButton.bezelStyle = .texturedRounded
                quitButton.image = quitImage
                quitButton.target = self
                quitButton.action = #selector(self.quitApp)
                quitButton.isBordered = false
                quitButton.wantsLayer = true
                quitButton.layer?.backgroundColor = NSColor.clear.cgColor
                // 设置statusBarManager引用
                quitButton.statusBarManager = self
                // 添加鼠标跟踪区域
                let trackingArea = NSTrackingArea(
                    rect: quitButton.bounds,
                    options: [.mouseEnteredAndExited, .activeAlways],
                    owner: quitButton,
                    userInfo: nil
                )
                quitButton.addTrackingArea(trackingArea)
                quitView.addSubview(quitButton)
                
                quitItem.view = quitView
                menu.addItem(quitItem)
            }
            
            // 添加带有毛玻璃效果的空白菜单项，覆盖菜单底部边缘
            menu.addItem(createVisualEffectSpacer())
            
            // 缓存菜单
            self.cachedMenu = menu
            self.lastMenuUpdate = Date()
            
            // 显示菜单
            if let statusItem = self.statusItems.first, let button = statusItem.button {
                // 直接弹出菜单，不设置statusItem.menu属性，避免系统缓存菜单对象
                // 向左移动20个像素，向下移动10个像素
                menu.popUp(positioning: nil, at: NSPoint(x: -20, y: button.bounds.height + 10), in: button)
            } else {
                // 如果按钮不可用，使用默认位置
                menu.popUp(positioning: nil, at: NSPoint(x: -20, y: 10), in: nil)
            }
            
            // 同时更新bluetoothManager.devices，确保其他地方也能获取到最新的设备状态
            bluetoothManager.retrieveConnectedDevices()
            
            print("[\(localTimeString())] showDeviceMenu - Completed")
        }
    }
    
    // 带鼠标悬停效果的视图子类
    private class HoverableView: NSView {
        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            // 使用选中颜色以获得更高对比度
            self.layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.6).cgColor
        }
        
        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            self.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    
    // 带鼠标悬停效果的按钮子类
    private class HoverableButton: NSButton {
        weak var statusBarManager: StatusBarManager?
        
        override func mouseDown(with event: NSEvent) {
            // 直接使用全局鼠标位置，这是屏幕坐标
            let globalLocation = NSEvent.mouseLocation
            
            // 存储点击位置到StatusBarManager
            statusBarManager?.lastClickLocation = globalLocation
            print("按钮点击位置 (全局鼠标位置): \(globalLocation)")
            
            // 同时打印其他坐标信息用于调试
            let windowLocation = event.locationInWindow
            print("按钮点击位置 (窗口坐标): \(windowLocation)")
            
            if let window = window {
                let screenLocation = window.convertPoint(toScreen: windowLocation)
                print("按钮点击位置 (窗口转换屏幕坐标): \(screenLocation)")
                print("窗口位置: \(window.frame.origin)")
                print("窗口大小: \(window.frame.size)")
            }
            
            // 调用父类方法
            super.mouseDown(with: event)
        }
        
        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            self.layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.6).cgColor
        }
        
        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            self.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    
    private func addDeviceMenuItem(to menu: NSMenu, device: BluetoothDevice) {
        // 创建设备菜单项
        let deviceItem = NSMenuItem(title: "", action: #selector(handleDeviceItemClick(_:)), keyEquivalent: "")
        deviceItem.target = self
        deviceItem.representedObject = device // 设置 representedObject 以便后续检测状态变化
        
        // 创建设备信息视图
        let deviceView = HoverableView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
        deviceView.wantsLayer = true
        deviceView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // 添加设备图标
        let iconImageView = NSImageView(frame: NSRect(x: 8, y: 4, width: 24, height: 24))
        if let deviceIcon = getDeviceIcon(for: device, size: NSSize(width: 24, height: 24)) {
            iconImageView.image = deviceIcon
        }
        deviceView.addSubview(iconImageView)
        
        // 添加设备名称
        let nameLabel = NSTextField(frame: NSRect(x: 40, y: 0, width: 100, height: 24))
        nameLabel.stringValue = device.name
        nameLabel.isBezeled = false
        nameLabel.isEditable = false
        nameLabel.backgroundColor = .clear
        nameLabel.textColor = device.isConnected ? .labelColor : .secondaryLabelColor
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        nameLabel.isSelectable = false
        deviceView.addSubview(nameLabel)
        
        // 添加连接状态指示器
        let statusLabel = NSTextField(frame: NSRect(x: 140, y: 0, width: 20, height: 24))
        statusLabel.stringValue = device.isConnected ? "●" : ""
        statusLabel.isBezeled = false
        statusLabel.isEditable = false
        statusLabel.backgroundColor = .clear
        statusLabel.textColor = device.isConnected ? .systemGreen : .clear
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.alignment = .right
        statusLabel.isSelectable = false
        deviceView.addSubview(statusLabel)
        
        // 添加电量信息（如果有）
        if let batteryLevel = device.batteryLevel {
            let batteryLabel = NSTextField(frame: NSRect(x: 150, y: 0, width: 40, height: 24))
            batteryLabel.stringValue = "\(batteryLevel)%"
            batteryLabel.isBezeled = false
            batteryLabel.isEditable = false
            batteryLabel.backgroundColor = .clear
            batteryLabel.textColor = device.isConnected ? .labelColor : .secondaryLabelColor
            batteryLabel.font = NSFont.systemFont(ofSize: 13)
            batteryLabel.alignment = .right
            batteryLabel.isSelectable = false
            deviceView.addSubview(batteryLabel)
        }
        
        // 添加鼠标悬停效果的跟踪区域
        let trackingArea = NSTrackingArea(
            rect: deviceView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: deviceView,
            userInfo: nil
        )
        deviceView.addTrackingArea(trackingArea)
        
        deviceItem.view = deviceView
        deviceItem.submenu = createDeviceSubmenu(device: device)
        menu.addItem(deviceItem)
    }
    
    private func createMenuItemWithVisualEffect(title: String, action: Selector?, keyEquivalent: String, image: NSImage? = nil, target: AnyObject? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.target = target
        menuItem.image = image
        menuItem.representedObject = title
        
        // 设置文字大小为13
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        menuItem.attributedTitle = attributedTitle
        
        return menuItem
    }
    
    private func createVisualEffectSeparator() -> NSMenuItem {
        let separatorItem = NSMenuItem.separator()
        return separatorItem
    }
    
    private func createVisualEffectSpacer() -> NSMenuItem {
        let spacerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        spacerItem.isEnabled = false
        return spacerItem
    }
    
    @objc private func handleDeviceItemClick(_ sender: NSMenuItem) {
        // 处理设备菜单项的点击事件
        // 由于设备菜单项的主要功能是显示子菜单，我们只需要确保菜单项可以被点击
        // 子菜单的显示会由系统自动处理
    }
    
    private func createDeviceSubmenu(device: BluetoothDevice) -> NSMenu {
        let submenu = NSMenu()
        // 设置二级菜单外观为暗色，确保与主菜单背景一致
        submenu.appearance = NSAppearance(named: .darkAqua)
        
        // 连接/断开操作
        let connectAction = device.isConnected ? "Disconnect" : "Connect"
        let connectItem = NSMenuItem(title: connectAction, action: #selector(toggleDeviceConnection(_:)), keyEquivalent: "")
        connectItem.target = self
        connectItem.representedObject = device
        submenu.addItem(connectItem)
        
        // 重命名操作
        let renameItem = NSMenuItem(title: "Rename", action: #selector(renameDevice(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = device
        submenu.addItem(renameItem)
        
        // 修改图标操作
        let changeIconItem = NSMenuItem(title: "Change Icon", action: #selector(changeDeviceIcon(_:)), keyEquivalent: "")
        changeIconItem.target = self
        changeIconItem.representedObject = device
        submenu.addItem(changeIconItem)
        
        // 状态栏图标显示选项
        // 检查设备是否满足显示图标的条件
        let shouldShowIcon = device.isConnected && (showDeviceIcons[device.id] ?? true)
        // 根据实际显示状态设置菜单项文本
        // 默认显示为"Show Status Bar Icon"，只有当设备图标实际显示在状态栏上时才显示为"Hide Status Bar Icon"
        let showStatusIconAction = shouldShowIcon ? "Hide Status Bar Icon" : "Show Status Bar Icon"
        let showStatusIconItem = NSMenuItem(title: showStatusIconAction, action: #selector(toggleDeviceStatusIcon(_:)), keyEquivalent: "")
        showStatusIconItem.target = self
        showStatusIconItem.representedObject = device
        submenu.addItem(showStatusIconItem)
        
        // 电量信息
        if let batteryLevel = device.batteryLevel {
            let batteryItem = NSMenuItem(title: "Battery: \(batteryLevel)%", action: nil, keyEquivalent: "")
            batteryItem.isEnabled = false
            submenu.addItem(batteryItem)
        }
        
        return submenu
    }
    
    @objc private func changeDeviceIcon(_ sender: NSMenuItem) {
        if let device = sender.representedObject as? BluetoothDevice {
            // 确保应用程序处于活动状态
            NSApp.activate(ignoringOtherApps: true)
            
            // 创建文件选择器
            let openPanel = NSOpenPanel()
            openPanel.title = "Select Icon for \(device.name)"
            openPanel.showsResizeIndicator = true
            openPanel.showsHiddenFiles = false
            openPanel.canChooseDirectories = false
            openPanel.canCreateDirectories = false
            openPanel.allowsMultipleSelection = false
            
            // 设置允许的文件类型
            openPanel.allowedContentTypes = [.png, .jpeg, .gif, .tiff]
            
            // 定义处理文件选择的闭包
            let handleFileSelection: (URL) -> Void = { [weak self] url in
                guard let self = self else { return }
                
                // 读取用户选择的图片文件
                guard let image = NSImage(contentsOf: url) else {
                    self.showErrorAlert(title: "Error", message: "Failed to load the selected image. Please try another file.")
                    print("Failed to load image from URL: \(url)")
                    return
                }
                
                // 保存图片到应用的临时目录
                let fileManager = FileManager.default
                let tempDir = NSTemporaryDirectory()
                
                // 确保临时目录存在
                do {
                    try fileManager.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    self.showErrorAlert(title: "Error", message: "Failed to access temporary directory. Please try again.")
                    print("Error accessing temporary directory: \(error)")
                    return
                }
                
                let timestamp = Int(Date().timeIntervalSince1970)
                let iconFileName = "device_\(device.id)_\(timestamp).png"
                let iconPath = tempDir.appending(iconFileName)
                
                // 将图片保存为PNG格式
                guard let tiffData = image.tiffRepresentation, 
                      let bitmapImage = NSBitmapImageRep(data: tiffData), 
                      let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                    self.showErrorAlert(title: "Error", message: "Failed to convert image to PNG format. Please try another file.")
                    print("Failed to convert image to PNG")
                    return
                }
                
                do {
                    try pngData.write(to: URL(fileURLWithPath: iconPath))
                    // 设置设备的自定义图标路径
                    self.bluetoothManager.updateDeviceCustomIcon(device, iconName: iconPath)
                    
                    // 确保设备图标显示设置为true
                    self.showDeviceIcons[device.id] = true
                    self.saveDeviceDisplaySettings()
                    
                    // 更新状态栏图标
                    self.updateStatusItems(devices: self.bluetoothManager.devices)
                    
                    // 显示成功消息
                    self.showSuccessAlert(title: "Success", message: "Icon updated successfully for \(device.name)")
                } catch {
                    self.showErrorAlert(title: "Error", message: "Failed to save icon. Please check permissions and try again.")
                    print("Error saving icon: \(error)")
                }
            }
            
            // 使用鼠标点击位置来显示文件选择器
            if let clickLocation = lastClickLocation {
                // 计算文件选择器的大小和位置
                let panelSize = NSSize(width: 600, height: 400)
                var panelFrame = NSRect(
                    x: clickLocation.x - panelSize.width / 2,
                    y: clickLocation.y - panelSize.height - 10,
                    width: panelSize.width,
                    height: panelSize.height
                )
                
                // 确保文件选择器不会超出屏幕边界
                if let screen = NSScreen.main {
                    let screenFrame = screen.visibleFrame
                    
                    if panelFrame.origin.x < screenFrame.origin.x {
                        panelFrame.origin.x = screenFrame.origin.x
                    } else if panelFrame.origin.x + panelFrame.size.width > screenFrame.origin.x + screenFrame.size.width {
                        panelFrame.origin.x = screenFrame.origin.x + screenFrame.size.width - panelFrame.size.width
                    }
                    
                    if panelFrame.origin.y < screenFrame.origin.y {
                        panelFrame.origin.y = screenFrame.origin.y
                    } else if panelFrame.origin.y + panelFrame.size.height > screenFrame.origin.y + screenFrame.size.height {
                        panelFrame.origin.y = screenFrame.origin.y + screenFrame.size.height - panelFrame.size.height
                    }
                }
                
                // 设置文件选择器的位置
                openPanel.setFrame(panelFrame, display: true)
                
                // 显示文件选择器
                openPanel.begin { response in
                    if response == .OK, let url = openPanel.url {
                        handleFileSelection(url)
                    }
                }
            } else {
                // 如果没有获取到点击位置，使用默认方式显示
                if let window = NSApp.mainWindow ?? NSApp.windows.first {
                    // 使用窗口作为父窗口，确保文件选择器置顶显示
                    openPanel.beginSheetModal(for: window) { response in
                        if response == .OK, let url = openPanel.url {
                            handleFileSelection(url)
                        }
                    }
                } else {
                    // 如果没有主窗口，使用默认方式显示
                    openPanel.begin { response in
                        if response == .OK, let url = openPanel.url {
                            handleFileSelection(url)
                        }
                    }
                }
            }
        }
    }
    
    // 显示错误警告
    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        
        // 使用鼠标点击位置来显示警告框
        if let clickLocation = lastClickLocation {
            // 获取警告框窗口
            let alertWindow = alert.window
            
            // 计算警告框的大小
            let alertSize = alertWindow.frame.size
            
            // 计算警告框的位置：点击位置的正下方
            let verticalOffset: CGFloat = 10 // 垂直距离
            var alertFrame = NSRect(
                x: clickLocation.x - alertSize.width / 2, // 水平居中
                y: clickLocation.y - alertSize.height - verticalOffset, // 垂直下方
                width: alertSize.width,
                height: alertSize.height
            )
            
            // 确保警告框不会超出屏幕边界
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                
                if alertFrame.origin.x < screenFrame.origin.x {
                    alertFrame.origin.x = screenFrame.origin.x
                } else if alertFrame.origin.x + alertFrame.size.width > screenFrame.origin.x + screenFrame.size.width {
                    alertFrame.origin.x = screenFrame.origin.x + screenFrame.size.width - alertFrame.size.width
                }
                
                if alertFrame.origin.y < screenFrame.origin.y {
                    alertFrame.origin.y = screenFrame.origin.y
                } else if alertFrame.origin.y + alertFrame.size.height > screenFrame.origin.y + screenFrame.size.height {
                    alertFrame.origin.y = screenFrame.origin.y + screenFrame.size.height - alertFrame.size.height
                }
            }
            
            // 设置警告框的位置
            alertWindow.setFrame(alertFrame, display: true)
            alertWindow.level = .floating
            alertWindow.makeKeyAndOrderFront(nil)
            
            // 显示警告框
            alert.runModal()
        } else {
            // 如果没有获取到点击位置，使用默认方式显示
            if let window = NSApp.mainWindow ?? NSApp.windows.first {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }
    
    // 显示成功警告
    private func showSuccessAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        
        // 使用鼠标点击位置来显示警告框
        if let clickLocation = lastClickLocation {
            // 获取警告框窗口
            let alertWindow = alert.window
            
            // 计算警告框的大小
            let alertSize = alertWindow.frame.size
            
            // 计算警告框的位置：点击位置的正下方
            let verticalOffset: CGFloat = 10 // 垂直距离
            var alertFrame = NSRect(
                x: clickLocation.x - alertSize.width / 2, // 水平居中
                y: clickLocation.y - alertSize.height - verticalOffset, // 垂直下方
                width: alertSize.width,
                height: alertSize.height
            )
            
            // 确保警告框不会超出屏幕边界
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                
                if alertFrame.origin.x < screenFrame.origin.x {
                    alertFrame.origin.x = screenFrame.origin.x
                } else if alertFrame.origin.x + alertFrame.size.width > screenFrame.origin.x + screenFrame.size.width {
                    alertFrame.origin.x = screenFrame.origin.x + screenFrame.size.width - alertFrame.size.width
                }
                
                if alertFrame.origin.y < screenFrame.origin.y {
                    alertFrame.origin.y = screenFrame.origin.y
                } else if alertFrame.origin.y + alertFrame.size.height > screenFrame.origin.y + screenFrame.size.height {
                    alertFrame.origin.y = screenFrame.origin.y + screenFrame.size.height - alertFrame.size.height
                }
            }
            
            // 设置警告框的位置
            alertWindow.setFrame(alertFrame, display: true)
            alertWindow.level = .floating
            alertWindow.makeKeyAndOrderFront(nil)
            
            // 显示警告框
            alert.runModal()
        } else {
            // 如果没有获取到点击位置，使用默认方式显示
            if let window = NSApp.mainWindow ?? NSApp.windows.first {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }
    
    @objc private func toggleDeviceStatusIcon(_ sender: NSMenuItem) {
        if let device = sender.representedObject as? BluetoothDevice {
            let currentValue = showDeviceIcons[device.id] ?? true
            showDeviceIcons[device.id] = !currentValue
            updateStatusItems(devices: bluetoothManager.devices)
            saveDeviceDisplaySettings()
            print("\(showDeviceIcons[device.id] ?? true ? "Show" : "Hide") status bar icon for device \(device.name)")
        }
    }
    
    @objc private func toggleDeviceConnection(_ sender: NSMenuItem) {
        if let device = sender.representedObject as? BluetoothDevice {
            if device.isConnected {
                bluetoothManager.disconnectDevice(device)
            } else {
                bluetoothManager.connectDevice(device)
            }
        }
    }
    
    @objc private func renameDevice(_ sender: NSMenuItem) {
        if let device = sender.representedObject as? BluetoothDevice {
            // 确保应用程序处于活动状态
            NSApp.activate(ignoringOtherApps: true)
            
            // 创建文本输入对话框
            let alert = NSAlert()
            alert.messageText = "Rename Device"
            alert.informativeText = "Enter a new name for \(device.name):"
            
            // 添加文本输入框
            let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            inputTextField.stringValue = device.name
            alert.accessoryView = inputTextField
            
            // 添加按钮
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            
            // 使用鼠标点击位置来显示对话框
            if let clickLocation = lastClickLocation {
                // 获取对话框窗口
                let alertWindow = alert.window
                
                // 计算对话框的大小
                let alertSize = alertWindow.frame.size
                
                // 计算对话框的位置：点击位置的正下方
                let verticalOffset: CGFloat = 10 // 垂直距离
                var alertFrame = NSRect(
                    x: clickLocation.x - alertSize.width / 2, // 水平居中
                    y: clickLocation.y - alertSize.height - verticalOffset, // 垂直下方
                    width: alertSize.width,
                    height: alertSize.height
                )
                
                // 确保对话框不会超出屏幕边界
                if let screen = NSScreen.main {
                    let screenFrame = screen.visibleFrame
                    
                    if alertFrame.origin.x < screenFrame.origin.x {
                        alertFrame.origin.x = screenFrame.origin.x
                    } else if alertFrame.origin.x + alertFrame.size.width > screenFrame.origin.x + screenFrame.size.width {
                        alertFrame.origin.x = screenFrame.origin.x + screenFrame.size.width - alertFrame.size.width
                    }
                    
                    if alertFrame.origin.y < screenFrame.origin.y {
                        alertFrame.origin.y = screenFrame.origin.y
                    } else if alertFrame.origin.y + alertFrame.size.height > screenFrame.origin.y + screenFrame.size.height {
                        alertFrame.origin.y = screenFrame.origin.y + screenFrame.size.height - alertFrame.size.height
                    }
                }
                
                // 设置对话框的位置
                alertWindow.setFrame(alertFrame, display: true)
                alertWindow.level = .floating
                alertWindow.makeKeyAndOrderFront(nil)
                
                // 显示对话框
                let response = alert.runModal()
                
                if response == .alertFirstButtonReturn { // OK 按钮
                    let newName = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !newName.isEmpty && newName != device.name {
                        // 更新设备名称
                        bluetoothManager.updateDeviceName(device, newName: newName)
                        print("Device renamed: \(device.name) -> \(newName)")
                    }
                }
            } else {
                // 如果没有获取到点击位置，使用默认方式显示
                let response = alert.runModal()
                
                if response == .alertFirstButtonReturn { // OK 按钮
                    let newName = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !newName.isEmpty && newName != device.name {
                        // 更新设备名称
                        bluetoothManager.updateDeviceName(device, newName: newName)
                        print("Device renamed: \(device.name) -> \(newName)")
                    }
                }
            }
        }
    }
    

    
    @objc private func showDeviceDetails(_ sender: AnyObject) {
        // 显示设备详情信息
        print("显示设备详情信息")
        
        // 找出是哪个设备的图标被点击了
        for (_, deviceInfo) in deviceStatusItems {
            if let button = deviceInfo.statusItem.button, button === sender {
                let device = deviceInfo.device
                showDeviceDetailsForDevice(device)
                break
            }
        }
    }
    
    private func showDeviceDetailsForDevice(_ device: BluetoothDevice, autoClose: Bool = false) {
        // 显示设备详情信息
        print("显示设备详情信息: \(device.name)")
        print("已连接: \(device.isConnected)")
        print("电量: \(device.batteryLevel ?? 0)%")
        print("自定义图标: \(device.customIconName ?? "无")")
        print("自动关闭: \(autoClose)")
        
        // 确保应用程序处于活动状态
        NSApp.activate(ignoringOtherApps: true)
        
        // 查找设备对应的状态栏图标
        for (deviceID, deviceInfo) in deviceStatusItems {
            if deviceID == device.id {
                DispatchQueue.main.async {
                    // 隐藏之前的气泡
                    if let popover = deviceInfo.popover {
                        popover.performClose(nil)
                    }
                    
                    // 创建新的气泡
                    let popover = NSPopover()
                    popover.behavior = .transient // 点击外部时自动关闭
                    popover.contentSize = NSSize(width: 220, height: 140) // 调整尺寸以适应电池图标
                    popover.animates = true // 添加动画效果
                    // 确保气泡显示到最上层
                    popover.appearance = NSAppearance(named: .darkAqua) // 使用暗色外观，确保与菜单背景一致
                    
                    // 创建磨砂玻璃效果的背景视图
                    let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 220, height: 140)) // 调整尺寸以适应电池图标
                    visualEffectView.wantsLayer = true
                    visualEffectView.material = .menu // 使用与菜单相同的材质
                    visualEffectView.blendingMode = .withinWindow // 更改混合模式以获得更好的毛玻璃效果
                    visualEffectView.state = .active
                    // 强制设置外观为暗色，确保与菜单背景一致
                    visualEffectView.appearance = NSAppearance(named: .darkAqua)
                    
                    /////////////////////// 添加设备图标
                    let iconImageView = NSImageView(frame: NSRect(x: 12, y: 95, width: 28, height: 28)) // 调整位置和大小，整体向上移动
                    // 使用可复用的方法获取设备图标
                    if let deviceIcon = self.getDeviceIcon(for: device, size: NSSize(width: 28, height: 28), applyTemplateForDisconnected: false) {
                        // 确保图标不使用模板模式，保持原始白色
                        deviceIcon.isTemplate = false
                        iconImageView.image = deviceIcon
                    }
                    visualEffectView.addSubview(iconImageView)
                    
                    ////////////////////// 添加设备名称
                    let nameLabel = NSTextField(frame: NSRect(x: 52, y: 99, width: 194, height: 18)) // 调整位置和大小，整体向上移动
                    nameLabel.stringValue = device.name
                    nameLabel.isBezeled = false
                    nameLabel.isEditable = false
                    nameLabel.backgroundColor = .clear
                    nameLabel.textColor = .controlTextColor // 使用系统文本颜色
                    nameLabel.font = NSFont.boldSystemFont(ofSize: 12)
                    visualEffectView.addSubview(nameLabel)
                    
                    /////////////////// 添加连接状态
                    let statusLabel = NSTextField(frame: NSRect(x: 12, y: 71, width: 236, height: 16)) // 调整位置和大小，整体向上移动
                    statusLabel.stringValue = "连接状态: \(device.isConnected ? "已连接" : "未连接")"
                    statusLabel.isBezeled = false
                    statusLabel.isEditable = false
                    statusLabel.backgroundColor = .clear
                    statusLabel.textColor = .secondaryLabelColor // 使用系统次要文本颜色
                    visualEffectView.addSubview(statusLabel)
                    
                    ////////////////////// 添加电量信息和电池图标
                    let batteryView = NSView(frame: NSRect(x: 12, y: 44, width: 236, height: 20)) // 调整位置和大小，整体向上移动
                    
                    // 添加电量标签
                    let batteryLabel = NSTextField(frame: NSRect(x: 0, y: 0, width: 35, height: 20)) // 调整位置和大小
                    batteryLabel.stringValue = "电量:"
                    batteryLabel.isBezeled = false
                    batteryLabel.isEditable = false
                    batteryLabel.backgroundColor = .clear
                    batteryLabel.textColor = .secondaryLabelColor // 使用系统次要文本颜色
                    batteryView.addSubview(batteryLabel)
                    
                    // 创建电池图标
                    let batteryIconView = NSView(frame: NSRect(x: 40, y: 6, width: 24, height: 12)) // 调整位置和大小，放置到文字右侧
                    batteryIconView.wantsLayer = true
                    batteryIconView.layer?.borderWidth = 1
                    batteryIconView.layer?.borderColor = NSColor.secondaryLabelColor.cgColor
                    batteryIconView.layer?.cornerRadius = 2
                    
                    // 创建电池正极
                    let batteryPositiveView = NSView(frame: NSRect(x: 44, y: 4, width: 5, height: 8))
                    batteryPositiveView.wantsLayer = true
                    batteryPositiveView.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
                    batteryIconView.addSubview(batteryPositiveView)
                    
                    // 根据电池电量填充颜色
                    if let batteryLevel = device.batteryLevel {
                        let batteryFillView = NSView(frame: NSRect(x: 1, y: 1, width: CGFloat(batteryLevel) * 0.22, height: 10))
                        batteryFillView.wantsLayer = true
                        
                        // 根据电量设置不同颜色
                        if batteryLevel > 60 {
                            batteryFillView.layer?.backgroundColor = NSColor.systemGreen.cgColor
                        } else if batteryLevel > 20 {
                            batteryFillView.layer?.backgroundColor = NSColor.systemYellow.cgColor
                        } else {
                            batteryFillView.layer?.backgroundColor = NSColor.systemRed.cgColor
                        }
                        
                        batteryIconView.addSubview(batteryFillView)
                    }
                    
                    batteryView.addSubview(batteryIconView)
                    
                    // 添加电量数值
                    let batteryValueLabel = NSTextField(frame: NSRect(x: 65, y: 0.5, width: 80, height: 20)) // 调整位置和大小
                    batteryValueLabel.stringValue = "\(device.batteryLevel ?? 0)%"
                    batteryValueLabel.isBezeled = false
                    batteryValueLabel.isEditable = false
                    batteryValueLabel.backgroundColor = .clear
                    batteryValueLabel.textColor = .secondaryLabelColor // 使用系统次要文本颜色
                    batteryView.addSubview(batteryValueLabel)
                    
                    visualEffectView.addSubview(batteryView)
                    
                    ////////////////////////// 添加MAC地址
                    let macLabel = NSTextField(frame: NSRect(x: 12, y: 23, width: 236, height: 16)) // 调整位置和大小，整体向上移动
                    macLabel.stringValue = "MAC地址: \(device.macAddress)"
                    macLabel.isBezeled = false
                    macLabel.isEditable = false
                    macLabel.backgroundColor = .clear
                    macLabel.textColor = .secondaryLabelColor // 使用系统次要文本颜色
                    visualEffectView.addSubview(macLabel)
                    
                    // 创建内容视图控制器
                    let contentViewController = NSViewController()
                    contentViewController.view = visualEffectView
                    popover.contentViewController = contentViewController
                    
                    // 从状态栏按钮显示气泡
                    if let button = deviceInfo.statusItem.button {
                        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
                    }
                    
                    // 更新设备状态栏图标映射，存储气泡
                    self.deviceStatusItems[deviceID] = (statusItem: deviceInfo.statusItem, device: device, popover: popover)
                    
                    // 如果是自动弹出的气泡，5秒后自动关闭
                    if autoClose {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            if popover.isShown {
                                popover.performClose(nil)
                            }
                        }
                    }
                    
                    // 添加全局点击监听器，确保点击外部时关闭弹窗
                    NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak popover] event in
                        if let popover = popover, popover.isShown {
                            popover.performClose(nil)
                        }
                    }
                }
                
                break
            }
        }
    }
    
    @objc private func openIconDisplaySettings() {
        // 打开图标显示设置
    }
    
    @objc private func openSettings() {
        // 打开设置窗口
        NSApp.activate(ignoringOtherApps: true)
        
        // 显示设置窗口
        DispatchQueue.main.async {
            // 如果已有设置窗口，先关闭它
            if let existingWindow = self.settingsWindow {
                existingWindow.close()
                self.settingsWindow = nil
                self.settingsWindowDelegate = nil
            }
            
            // 创建新的设置窗口
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = "BtBar Settings"
            settingsWindow.center()
            
            // 创建SwiftUI视图并设置为窗口内容
            let settingsView = SettingsView().environmentObject(self.bluetoothManager)
            let hostingController = NSHostingController(rootView: settingsView)
            self.settingsHostingController = hostingController
            
            // 创建毛玻璃效果的背景视图
            let visualEffectView = NSVisualEffectView(frame: settingsWindow.contentRect(forFrameRect: settingsWindow.frame))
            visualEffectView.wantsLayer = true
            visualEffectView.material = .menu // 使用与菜单相同的材质
            visualEffectView.blendingMode = .withinWindow // 更改混合模式以获得更好的毛玻璃效果
            visualEffectView.state = .active
            // 强制设置外观为暗色，确保与菜单背景一致
            visualEffectView.appearance = NSAppearance(named: .darkAqua)
            
            // 将SwiftUI视图添加到毛玻璃背景上
            visualEffectView.addSubview(hostingController.view)
            hostingController.view.frame = visualEffectView.bounds
            hostingController.view.autoresizingMask = [.width, .height]
            
            // 设置窗口内容为毛玻璃背景视图
            settingsWindow.contentView = visualEffectView
            
            // 确保应用程序处于活动状态
            NSApp.activate(ignoringOtherApps: true)
            
            // 显示窗口并设置为最上层
            settingsWindow.makeKeyAndOrderFront(nil)
            // 确保窗口在所有窗口之上
            settingsWindow.level = .floating
            
            // 创建并设置窗口代理
            let delegate = WindowDelegate()
            delegate.statusBarManager = self
            settingsWindow.delegate = delegate
            
            // 存储窗口和代理引用，避免被释放
            self.settingsWindow = settingsWindow
            self.settingsWindowDelegate = delegate
        }
    }
    
    @objc private func quitApp() {
        // 确保应用程序处于活动状态
        NSApp.activate(ignoringOtherApps: true)
        
        // 创建确认退出的警告框
        let alert = NSAlert()
        alert.messageText = "确认退出"
        alert.informativeText = "你确定要退出 BtBar 吗？"
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        
        // 打印当前的点击位置
        print("退出按钮点击位置: \(lastClickLocation ?? NSPoint(x: 0, y: 0))")
        
        // 获取最后一次点击的位置
        if let clickLocation = lastClickLocation {
            // 获取警告框窗口
            let alertWindow = alert.window
            
            // 计算警告框的大小
            let alertSize = alertWindow.frame.size
            
            // 打印屏幕信息
            if let screen = NSScreen.main {
                print("屏幕大小: \(screen.frame.size)")
                print("屏幕可视区域: \(screen.visibleFrame)")
            }
            
            // 计算警告框的位置：点击位置的正下方
            // 注意：在macOS中，NSEvent.mouseLocation的原点在屏幕左下角
            let verticalOffset: CGFloat = 10 // 垂直距离
            var alertFrame = NSRect(
                x: clickLocation.x - alertSize.width / 2, // 水平居中
                y: clickLocation.y - alertSize.height - verticalOffset, // 垂直下方
                width: alertSize.width,
                height: alertSize.height
            )
            
            // 获取屏幕的可视区域
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                
                // 确保警告框不会超出屏幕边界
                // 水平方向调整
                if alertFrame.origin.x < screenFrame.origin.x {
                    alertFrame.origin.x = screenFrame.origin.x
                } else if alertFrame.origin.x + alertFrame.size.width > screenFrame.origin.x + screenFrame.size.width {
                    alertFrame.origin.x = screenFrame.origin.x + screenFrame.size.width - alertFrame.size.width
                }
                
                // 垂直方向调整
                if alertFrame.origin.y < screenFrame.origin.y {
                    alertFrame.origin.y = screenFrame.origin.y
                } else if alertFrame.origin.y + alertFrame.size.height > screenFrame.origin.y + screenFrame.size.height {
                    alertFrame.origin.y = screenFrame.origin.y + screenFrame.size.height - alertFrame.size.height
                }
            }
            
            // 设置警告框的位置
            alertWindow.setFrame(alertFrame, display: true)
            print("警告框位置: \(alertFrame)")
            
            // 强制设置窗口级别，确保它显示在菜单上方
            alertWindow.level = .floating
            
            // 显示警告框
            alertWindow.makeKeyAndOrderFront(nil)
            
            // 等待用户响应
            let response = alert.runModal()
            if response == .alertFirstButtonReturn { // 用户点击了"退出"按钮
                NSApplication.shared.terminate(nil)
            }
        } else {
            // 如果没有获取到点击位置，使用默认方式显示
            print("没有获取到点击位置，使用默认方式显示")
            // 尝试使用主窗口作为父窗口显示警告框
            if let window = NSApp.mainWindow ?? NSApp.windows.first {
                // 使用sheet方式显示，确保置顶
                alert.beginSheetModal(for: window) { response in
                    if response == .alertFirstButtonReturn { // 用户点击了"退出"按钮
                        NSApplication.shared.terminate(nil)
                    }
                }
            } else {
                // 如果没有主窗口，使用默认方式显示
                let response = alert.runModal()
                if response == .alertFirstButtonReturn { // 用户点击了"退出"按钮
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
    
    // 清理设置窗口引用
    func cleanupSettingsWindow() {
        settingsWindow = nil
        settingsWindowDelegate = nil
        settingsHostingController = nil
    }
    
    // 根据设备名称获取图标名称
    private func getDeviceIconName(for deviceName: String) -> String {
        let lowerName = deviceName.lowercased()
        if lowerName.contains("airpod") {
            return "airpods"
        } else if lowerName.contains("mouse") {
            return "mouse"
        } else if lowerName.contains("keyboard") {
            return "keyboard"
        } else if lowerName.contains("headphone") || lowerName.contains("headset") || lowerName.contains("bud") || lowerName.contains("earbud") {
            return "headphones"
        } else if lowerName.contains("speaker") {
            return "speaker"
        } else {
            return "bluetooth"
        }
    }
}

// 设置视图
struct SettingsView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var selectedTab: Int = 0
    
    var body: some View {
        VStack {
            // 标题
            Text("BtBar")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()
            
            // 标签栏
            HStack(spacing: 12) {
                TabButton(title: "Devices", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: "Icons", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                TabButton(title: "Display", isSelected: selectedTab == 2) {
                    selectedTab = 2
                }
                TabButton(title: "Settings", isSelected: selectedTab == 3) {
                    selectedTab = 3
                }
            }
            .padding(.horizontal)
            
            // 内容区域
            if selectedTab == 0 {
                // 设备列表
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(bluetoothManager.devices) {
                            device in
                            DeviceCard(device: device)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                }
            } else if selectedTab == 1 {
                // 图标管理
                IconManagementView()
            } else if selectedTab == 2 {
                // 图标显示设置
                IconDisplaySettingsView()
            } else {
                // 设置选项
                VStack(spacing: 20) {
                    SettingRow(title: "Refresh Devices", action: {
                        bluetoothManager.startScanning()
                    })
                    
                    SettingRow(title: "About BtBar", action: {
                        // 显示关于信息
                    })
                }
                .padding()
            }
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}



// 设备卡片组件
struct DeviceCard: View {
    let device: BluetoothDevice
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var showRenameDialog: Bool = false
    @State private var newDeviceName: String = ""
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // 设备图标
                Image(systemName: device.iconName)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .padding()
                .background(Color(NSColor.lightGray))
                .cornerRadius(12)
                
                // 设备信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(device.macAddress)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // 连接状态
                Text(device.isConnected ? "Connected" : "Disconnected")
                    .font(.subheadline)
                    .foregroundColor(device.isConnected ? .green : .red)
            }
            
            // 电量显示
            if let batteryLevel = device.batteryLevel {
                HStack {
                    Text("Battery")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(batteryLevel)%")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal)
                
                // 电量条
                GeometryReader {
                    geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .frame(width: geometry.size.width, height: 8)
                            .background(Color(NSColor.lightGray))
                            .cornerRadius(4)
                        
                        Rectangle()
                            .frame(width: geometry.size.width * CGFloat(batteryLevel) / 100, height: 8)
                            .foregroundColor(getBatteryColor(level: batteryLevel))
                            .cornerRadius(4)
                    }
                }
                .frame(height: 8)
                .padding(.horizontal)
            }
            
            // 操作按钮
            HStack {
                Button(device.isConnected ? "Disconnect" : "Connect") {
                    if device.isConnected {
                        bluetoothManager.disconnectDevice(device)
                    } else {
                        bluetoothManager.connectDevice(device)
                    }
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(device.isConnected ? Color(.systemRed) : Color(.systemBlue))
                .foregroundColor(.white)
                .cornerRadius(8)
                
                Spacer()
                
                Button("Rename") {
                    newDeviceName = device.name
                    showRenameDialog = true
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color(NSColor.gray))
                .foregroundColor(.black)
                .cornerRadius(8)
            }
            .padding(.horizontal)
        }
        .background(Color(NSColor.lightGray))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .animation(.spring(), value: device.isConnected)
        .sheet(isPresented: $showRenameDialog) {
            RenameDeviceDialog(device: device, newName: $newDeviceName, onRename: { name in
                bluetoothManager.updateDeviceName(device, newName: name)
                showRenameDialog = false
            }, onCancel: {
                showRenameDialog = false
            })
        }
    }
    
    private func getBatteryColor(level: Int) -> Color {
        if level > 60 {
            return .green
        } else if level > 20 {
            return .yellow
        } else {
            return .red
        }
    }
}

// 重命名设备对话框
struct RenameDeviceDialog: View {
    let device: BluetoothDevice
    @Binding var newName: String
    let onRename: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rename \(device.name)")
                .font(.headline)
                .fontWeight(.semibold)
            
            TextField("Enter new name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .padding()
            
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color(NSColor.gray))
                .foregroundColor(.black)
                .cornerRadius(8)
                
                Spacer()
                
                Button("Rename") {
                    if !newName.isEmpty {
                        onRename(newName)
                    }
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color(.systemBlue))
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(newName.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

// 标签按钮组件
struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .blue : .gray)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(isSelected ? Color(NSColor.blue).opacity(0.2) : Color.clear)
                .cornerRadius(12)
        }
    }
}

// 设置行组件
struct SettingRow: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(NSColor.lightGray))
            .cornerRadius(12)
        }
    }
}

// 图标管理视图
struct IconManagementView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var selectedDevice: BluetoothDevice?
    
    private let availableIcons = [
        "airpods", "mouse", "keyboard", "headphones", "speaker",
        "bluetooth", "iphone", "ipad", "applewatch", "laptopcomputer"
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            // 设备选择
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(bluetoothManager.devices.filter { $0.isConnected }) {
                        device in
                        Button(action: {
                            selectedDevice = device
                        }) {
                            VStack {
                                Image(systemName: device.iconName)
                                    .resizable()
                                    .frame(width: 48, height: 48)
                                    .padding()
                                    .background(selectedDevice?.id == device.id ? Color(NSColor.blue).opacity(0.2) : Color(NSColor.lightGray))
                                    .cornerRadius(12)
                                Text(device.name)
                                    .font(.subheadline)
                                    .padding(.top, 4)
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
                .padding()
            }
            
            // 图标选择
            if let device = selectedDevice {
                VStack(spacing: 16) {
                    Text("Select Icon for \(device.name)")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    // 图标网格
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(availableIcons, id: \.self) {
                            iconName in
                            Button(action: {
                                bluetoothManager.updateDeviceCustomIcon(device, iconName: iconName)
                            }) {
                                VStack {
                                    Image(systemName: iconName)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .padding()
                                        .background(device.iconName == iconName ? Color(NSColor.blue).opacity(0.2) : Color(NSColor.lightGray))
                                        .cornerRadius(8)
                                    Text(iconName)
                                        .font(.caption)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        
                        // 重置图标按钮
                        Button(action: {
                            bluetoothManager.updateDeviceCustomIcon(device, iconName: nil)
                        }) {
                            VStack {
                                Image(systemName: "arrow.counterclockwise")
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .padding()
                                    .background(Color(NSColor.lightGray))
                                    .cornerRadius(8)
                                Text("Reset")
                                    .font(.caption)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                let connectedDevices = bluetoothManager.devices.filter { $0.isConnected }
                if connectedDevices.isEmpty {
                    Text("No connected devices available")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    Text("Select a device to customize its icon")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding()
                }
            }
        }
    }
}

// 图标显示设置视图
struct IconDisplaySettingsView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var showDeviceIcons: [String: Bool] = [:]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Icon Display Settings")
                .font(.headline)
                .fontWeight(.semibold)
                .padding()
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(bluetoothManager.devices) {
                        device in
                        HStack {
                            Image(systemName: device.iconName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .padding()
                                .background(Color(NSColor.lightGray))
                                .cornerRadius(8)
                            
                            Text(device.name)
                                .font(.headline)
                            
                            Spacer()
                            
                            Toggle(isOn: Binding(
                                get: { showDeviceIcons[device.id] ?? true },
                                set: { showDeviceIcons[device.id] = $0 }
                            )) {
                                Text("")
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            
            Button("Save Settings") {
                // 保存显示设置
                saveDisplaySettings()
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(Color(.systemBlue))
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding()
        }
    }
    
    private func saveDisplaySettings() {
        // 保存显示设置到 UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(showDeviceIcons, forKey: "deviceDisplaySettings")
        defaults.synchronize()
        print("Saved display settings: \(showDeviceIcons)")
        
        // 通知 StatusBarManager 重新加载设置
        NotificationCenter.default.post(name: NSNotification.Name("DeviceDisplaySettingsChanged"), object: nil)
    }
}