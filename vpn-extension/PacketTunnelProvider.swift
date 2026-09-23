import NetworkExtension

private enum AirCardTunnelConstants {
    static let ifaceIPKey = "TunnelIfaceIP"
    static let peerIPKey = "TunnelPeerIP"
    static let defaultIfaceIP = "10.7.1.1/32"
    static let defaultPeerIP = "10.7.0.1/32"
}

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var interfaceIP = AirCardTunnelConstants.defaultIfaceIP
    private var peerIP = AirCardTunnelConstants.defaultPeerIP

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let configuration = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        interfaceIP = options?[AirCardTunnelConstants.ifaceIPKey] as? String
            ?? configuration?[AirCardTunnelConstants.ifaceIPKey] as? String
            ?? interfaceIP
        peerIP = options?[AirCardTunnelConstants.peerIPKey] as? String
            ?? configuration?[AirCardTunnelConstants.peerIPKey] as? String
            ?? peerIP

        let iface = CIDREndpoint(interfaceIP)
        let peer = CIDREndpoint(peerIP)
        let ipv4 = NEIPv4Settings(
            addresses: [iface.ip],
            subnetMasks: [iface.subnetMask]
        )
        ipv4.includedRoutes = [
            NEIPv4Route(destinationAddress: peer.ip, subnetMask: peer.subnetMask)
        ]
        ipv4.excludedRoutes = [.default()]

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: peer.ip)
        settings.ipv4Settings = ipv4
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                completionHandler(error)
                return
            }
            guard error == nil else {
                completionHandler(error)
                return
            }
            self.readAndReflectPackets()
            completionHandler(nil)
        }
    }

    private func readAndReflectPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            var reflected = packets
            for index in reflected.indices where protocols[index].int32Value == AF_INET && reflected[index].count >= 20 {
                reflected[index].withUnsafeMutableBytes { bytes in
                    guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
                    let source = base[3]
                    base[3] = base[4]
                    base[4] = source
                }
            }
            self.packetFlow.writePackets(reflected, withProtocols: protocols)
            self.readAndReflectPackets()
        }
    }
}

private struct CIDREndpoint {
    let ip: String
    let prefix: Int
    let subnetMask: String

    init(_ raw: String) {
        let parts = raw.split(separator: "/", maxSplits: 1).map(String.init)
        ip = parts.first ?? "10.7.0.1"
        prefix = Int(parts.dropFirst().first ?? "32") ?? 32
        let safePrefix = max(0, min(32, prefix))
        let mask: UInt32
        if safePrefix == 0 {
            mask = 0
        } else if safePrefix == 32 {
            mask = UInt32.max
        } else {
            mask = UInt32.max << (32 - safePrefix)
        }
        subnetMask = "\((mask >> 24) & 255).\((mask >> 16) & 255).\((mask >> 8) & 255).\(mask & 255)"
    }
}
