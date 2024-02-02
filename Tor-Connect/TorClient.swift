//
//  TorClient.swift
//  Tor-Connect
//
//  Created by Peter Denton on 1/18/24.
//

import Foundation
import Tor

protocol OnionManagerDelegate: AnyObject {
    func torConnProgress(_ progress: Int)
    func torConnFinished()
    func torConnDifficulties()
}

class TorClient: NSObject, URLSessionDelegate {
    
    enum TorState {
        case none
        case started
        case connected
        case stopped
        case refreshing
    }
    
    public var state: TorState = .none
    public var cert:Data?
    
    static let sharedInstance = TorClient()
    private var config: TorConfiguration = TorConfiguration()
    private var thread: TorThread?
    private var controller: TorController?
    private var authDirPath = ""
    var isRefreshing = false
    
    // The tor url session configuration.
    // Start with default config as fallback.
    private lazy var sessionConfiguration: URLSessionConfiguration = .default
    
    // The tor client url session including the tor configuration.
    lazy var session = URLSession(configuration: sessionConfiguration)
    
    // Start the tor client.
    func start(delegate: OnionManagerDelegate?) {
        weak var weakDelegate = delegate
        state = .started
        guard let proxyPort = try? reservePort() else { return }
        guard let dnsPort = try? reservePort() else { return }
        
        sessionConfiguration.connectionProxyDictionary = [kCFProxyTypeKey: kCFProxyTypeSOCKS,
                                          kCFStreamPropertySOCKSProxyHost: "localhost",
                                          kCFStreamPropertySOCKSProxyPort: proxyPort]
        
        session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: .main)
        
        addTorrc()
        createTorDirectory()
        
        
        self.thread = nil
        
        self.config.options = [
            "DNSPort": "\(dnsPort)",
            "AutomapHostsOnResolve": "1",
            "SocksPort": "\(proxyPort) OnionTrafficOnly",
            "AvoidDiskWrites": "1",
            "LearnCircuitBuildTimeout": "1",
            "NumEntryGuards": "8",
            "SafeSocks": "1",
            "LongLivedPorts": "80,443",
            "NumCPUs": "2",
            "DisableDebuggerAttachment": "1",
            "SafeLogging": "1",
            "ExcludeExitNodes": "1",
            "StrictNodes": "1"
        ]
        
        
        self.config.cookieAuthentication = true
        self.config.dataDirectory = URL(fileURLWithPath: self.torPath())
        self.config.controlSocket = self.config.dataDirectory?.appendingPathComponent("cp")
        self.thread = TorThread(configuration: self.config)
        
        // Initiate the controller.
        if self.controller == nil {
            self.controller = TorController(socketURL: self.config.controlSocket!)
        }
        
        // Start a tor thread.
        self.thread?.start()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Connect Tor controller.
            do {
                if !(self.controller?.isConnected ?? false) {
                    do {
                        try self.controller?.connect()
                    } catch {
                        print("error=\(error)")
                    }
                }
                
                let cookie = try Data(
                    contentsOf: self.config.dataDirectory!.appendingPathComponent("control_auth_cookie"),
                    options: NSData.ReadingOptions(rawValue: 0)
                )
                
                
                self.controller?.authenticate(with: cookie) { (success, error) in
                    if let error = error {
                        print("error = \(error.localizedDescription)")
                        return
                    }
                    
                    var progressObs: Any? = nil
                    progressObs = self.controller?.addObserver(forStatusEvents: {
                        (type: String, severity: String, action: String, arguments: [String : String]?) -> Bool in
                        if arguments != nil {
                            if arguments!["PROGRESS"] != nil {
                                let progress = Int(arguments!["PROGRESS"]!)!
                                weakDelegate?.torConnProgress(progress)
                                if progress >= 100 {
                                    self.controller?.removeObserver(progressObs)
                                }
                                return true
                            }
                        }
                        return false
                    })
                    
                    var observer: Any? = nil
                    observer = self.controller?.addObserver(forCircuitEstablished: { established in
                        if established {
                            self.state = .connected
                            weakDelegate?.torConnFinished()
                            self.controller?.removeObserver(observer)
                            
                        } else if self.state == .refreshing {
                            self.state = .connected
                            weakDelegate?.torConnFinished()
                            self.controller?.removeObserver(observer)
                        }
                    })
                }
            } catch {
                weakDelegate?.torConnDifficulties()
                self.state = .none
            }
        }
    }
    
    // reservePort() copied from https://stackoverflow.com/a/77897502
    /// Reserve an ephemeral port from the system
    ///
    /// First we `bind` to port 0 in order to allocate an ephemeral port.
    /// Next, we `connect` to that port to establish a connection.
    /// Finally, we close the port and put it into the `TIME_WAIT` state.
    ///
    /// This allows another process to `bind` the port with `SO_REUSEADDR` specified.
    /// However, for the next ~120 seconds, the system will not re-use this port.
    /// - Returns: A port number that is valid for ~120 seconds.
    func reservePort() throws -> UInt16 {
        let serverSock = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSock >= 0 else {
            throw ServerError.cannotReservePort
        }
        defer {
            close(serverSock)
        }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = 0 // request an ephemeral port

        var len = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let res = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                let res1 = Darwin.bind(serverSock, $0, len)
                let res2 = getsockname(serverSock, $0, &len)
                return (res1, res2)
            }
        }
        guard res.0 == 0 && res.1 == 0 else {
            throw ServerError.cannotReservePort
        }

        guard listen(serverSock, 1) == 0 else {
            throw ServerError.cannotReservePort
        }

        let clientSock = socket(AF_INET, SOCK_STREAM, 0)
        guard clientSock >= 0 else {
            throw ServerError.cannotReservePort
        }
        defer {
            close(clientSock)
        }
        let res3 = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(clientSock, $0, len)
            }
        }
        guard res3 == 0 else {
            throw ServerError.cannotReservePort
        }

        let acceptSock = accept(serverSock, nil, nil)
        guard acceptSock >= 0 else {
            throw ServerError.cannotReservePort
        }
        defer {
            close(acceptSock)
        }
        return addr.sin_port.byteSwapped
    }

    enum ServerError: Error {
        case cannotReservePort
    }
    
    
    func resign() {
        controller?.disconnect()
        controller = nil
        thread?.cancel()
        thread = nil
        state = .stopped
    }
    
    private func createTorDirectory() {
        do {
            try FileManager.default.createDirectory(atPath: self.torPath(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [FileAttributeKey.posixPermissions: 0o700])
        } catch {
            print("Directory previously created.")
        }
    }
    
    private func torPath() -> String {
        return "\(NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? "")/tor"
    }
    
    private func addTorrc() {
        createHiddenServiceDirectory()
        let torrcUrl = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Containers/com.dentonllc.Tor-Connect/Data/.torrc")
        let torrc = Data(Torrc.torrc.utf8)
        do {
            try torrc.write(to: torrcUrl)
        } catch {
            print("an error happened while creating the file")
        }
    }
    
    private func createHiddenServiceDirectory() {
        let jmHostDir = "\(torPath())/host/joinmarket/"
        let btcMainDir = "\(torPath())/host/bitcoin/rpc/main/"
        let btcTestDir = "\(torPath())/host/bitcoin/rpc/test/"
        let btcRegtestDir = "\(torPath())/host/bitcoin/rpc/regtest/"
        let btcSignetDir = "\(torPath())/host/bitcoin/rpc/signet/"
        
        let hsDirs = [jmHostDir, btcMainDir, btcTestDir, btcRegtestDir, btcSignetDir]
        for hsDir in hsDirs {
            do {
                try FileManager.default.createDirectory(atPath: hsDir,
                                                        withIntermediateDirectories: true,
                                                        attributes: [FileAttributeKey.posixPermissions: 0o700])
            } catch {
                print("Directory previously created.")
            }
        }
    }
    
    func hostnames() -> [String]? {
        //let jmHost = "\(torPath())/host/joinmarket/hostname"
        let btcMain = "\(torPath())/host/bitcoin/rpc/main/hostname"
        let btcTest = "\(torPath())/host/bitcoin/rpc/test/hostname"
        let btcRegtest = "\(torPath())/host/bitcoin/rpc/regtest/hostname"
        let btcSignet = "\(torPath())/host/bitcoin/rpc/signet/hostname"
        
        let hosts = [btcMain, btcTest, btcSignet, btcRegtest]
        var hostnames: [String] = []
        
        for host in hosts {
            let path = URL(fileURLWithPath: host)
            guard let hs = try? String(contentsOf: path, encoding: .utf8) else { return nil }
            let trimmed = hs.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)

            hostnames.append(trimmed)
        }
        
        return hostnames
    }
    

}
