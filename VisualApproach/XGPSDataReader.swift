import Foundation
import Network
import Combine

@MainActor
class XGPSDataReader: ObservableObject {
    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var altitude: Double = 0.0
    @Published var isConnected: Bool = false
    @Published var lastUpdateTime: Date = Date()
    
    private var udpListener: NWListener?
    private var udpConnection: NWConnection?
    private let queue = DispatchQueue(label: "xgps-udp-queue")
    
    var genericLocation: GenericLocation?
    
    deinit {
        udpListener?.cancel()
        udpConnection?.cancel()
        udpListener = nil
        udpConnection = nil
    }
    
    func startListening() {
        let port = NWEndpoint.Port(49002)
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        
        udpListener = try? NWListener(using: parameters, on: port)
        
        udpListener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.udpConnection = connection
            }
            self?.setupConnection(connection)
        }
        
        udpListener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isConnected = true
                case .failed(let error):
                    print("UDP listener failed: \(error)")
                    self?.isConnected = false
                case .cancelled:
                    self?.isConnected = false
                default:
                    break
                }
            }
        }
        
        udpListener?.start(queue: queue)
    }
    
    private nonisolated func setupConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.receiveData(from: connection)
                case .failed(let error):
                    print("UDP connection failed: \(error)")
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        
        connection.start(queue: queue)
    }
    
    func stopListening() {
        udpListener?.cancel()
        udpConnection?.cancel()
        udpListener = nil
        udpConnection = nil
    }
    
    private nonisolated func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    self?.processXGPSData(data)
                }
            }
            
            if error == nil {
                self?.receiveData(from: connection)
            }
        }
    }
    
    private func processXGPSData(_ data: Data) {
        guard data.count >= 41 else { return }
        
        let header = String(data: data.prefix(4), encoding: .ascii)
        guard header == "XGPS" else { return }
        
        let dataStr = String(data: data, encoding: .ascii)
        let components = dataStr?.components(separatedBy: ",")
        
        let longitude = Double(components?[1] ?? "") ?? 0
        let latitude = Double(components?[2] ?? "") ?? 0
        let altitude = (Double(components?[3] ?? "") ?? 0) * 3.2808399 // meter to feet
        
        Task { @MainActor in
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.lastUpdateTime = Date()
            
            // Update GenericLocation if available
            self.genericLocation?.latitude = latitude
            self.genericLocation?.longitude = longitude
            self.genericLocation?.altitude = altitude
        }
    }
}
