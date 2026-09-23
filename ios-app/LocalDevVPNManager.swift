import Combine
import Foundation
import NetworkExtension

struct AirCardTunnelAddresses {
    var interfaceIP: String = "10.7.1.1/32"
    var peerIP: String = "10.7.0.1/32"
}

@MainActor
final class LocalDevVPNManager: ObservableObject {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case error

        var title: String {
            switch self {
            case .disconnected: return "未连接"
            case .connecting: return "正在连接"
            case .connected: return "已连接"
            case .disconnecting: return "正在断开"
            case .error: return "连接错误"
            }
        }
    }

    static let shared = LocalDevVPNManager()

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var isConfigured = false
    @Published private(set) var lastError: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var addresses = AirCardTunnelAddresses()

    private init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let connection = notification.object as? NEVPNConnection else { return }
            guard self.manager?.connection === connection else { return }
            self.updateStatus(from: connection.status)
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

    var isActive: Bool {
        status == .connected || status == .connecting
    }

    func refresh() async {
        do {
            manager = try await loadMatchingManager()
            isConfigured = manager != nil
            if let manager {
                updateStatus(from: manager.connection.status)
            } else {
                status = .disconnected
            }
            lastError = nil
        } catch {
            isConfigured = false
            status = .error
            lastError = error.localizedDescription
        }
    }

    func start(peerIP: String? = nil) async {
        if let peerIP, !peerIP.isEmpty {
            addresses.peerIP = peerIP.contains("/") ? peerIP : "\(peerIP)/32"
        }

        do {
            let vpnManager = try await configuredManager()
            manager = vpnManager
            try await vpnManager.saveToPreferences()
            try await vpnManager.loadFromPreferences()
            try vpnManager.connection.startVPNTunnel(options: [
                "TunnelIfaceIP": addresses.interfaceIP,
                "TunnelPeerIP": addresses.peerIP
            ])
            isConfigured = true
            status = .connecting
            lastError = nil
        } catch {
            status = .error
            lastError = error.localizedDescription
        }
    }

    func stop() {
        guard let manager else { return }
        manager.connection.stopVPNTunnel()
        status = .disconnecting
    }

    func toggle(peerIP: String? = nil) async {
        if isActive {
            stop()
        } else {
            await start(peerIP: peerIP)
        }
    }

    private func loadMatchingManager() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first { manager in
            let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
            return proto?.providerBundleIdentifier == extensionBundleIdentifier
        }
    }

    private func configuredManager() async throws -> NETunnelProviderManager {
        let vpnManager = try await loadMatchingManager() ?? NETunnelProviderManager()
        vpnManager.localizedDescription = "AirCard 本地回环"

        let proto = (vpnManager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = extensionBundleIdentifier
        proto.serverAddress = "AirCard Local Loopback"
        proto.providerConfiguration = [
            "TunnelIfaceIP": addresses.interfaceIP as NSString,
            "TunnelPeerIP": addresses.peerIP as NSString
        ]
        vpnManager.protocolConfiguration = proto
        vpnManager.isEnabled = true
        vpnManager.isOnDemandEnabled = false
        return vpnManager
    }

    private var extensionBundleIdentifier: String {
        let appID = Bundle.main.bundleIdentifier ?? "com.mutually.wallpaper"
        return "\(appID).LocalDevVPN"
    }

    private func updateStatus(from connectionStatus: NEVPNStatus) {
        switch connectionStatus {
        case .invalid, .disconnected:
            status = .disconnected
        case .connecting, .reasserting:
            status = .connecting
        case .connected:
            status = .connected
        case .disconnecting:
            status = .disconnecting
        @unknown default:
            status = .error
        }
    }
}
