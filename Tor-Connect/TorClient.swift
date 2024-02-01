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
        let proxyPort = findFreePort()
        let dnsPort = findFreePort()
        
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
    
    
    private func findFreePort() -> UInt16 {
        var port: UInt16 = 8000;

        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if socketFD == -1 {
          //print("Error creating socket: \(errno)")
          return port;
        }

        var hints = addrinfo(
          ai_flags: AI_PASSIVE,
          ai_family: AF_INET,
          ai_socktype: SOCK_STREAM,
          ai_protocol: 0,
          ai_addrlen: 0,
          ai_canonname: nil,
          ai_addr: nil,
          ai_next: nil
        );

        var addressInfo: UnsafeMutablePointer<addrinfo>? = nil;
        var result = getaddrinfo(nil, "0", &hints, &addressInfo);
        if result != 0 {
          //print("Error getting address info: \(errno)")
          close(socketFD);

          return port;
        }

        result = Darwin.bind(socketFD, addressInfo!.pointee.ai_addr, socklen_t(addressInfo!.pointee.ai_addrlen));
        if result == -1 {
          //print("Error binding socket to an address: \(errno)")
          close(socketFD);

          return port;
        }

        result = Darwin.listen(socketFD, 1);
        if result == -1 {
          //print("Error setting socket to listen: \(errno)")
          close(socketFD);

          return port;
        }

        var addr_in = sockaddr_in();
        addr_in.sin_len = UInt8(MemoryLayout.size(ofValue: addr_in));
        addr_in.sin_family = sa_family_t(AF_INET);

        var len = socklen_t(addr_in.sin_len);
        result = withUnsafeMutablePointer(to: &addr_in, {
          $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            return Darwin.getsockname(socketFD, $0, &len);
          }
        });

        if result == 0 {
          port = addr_in.sin_port;
        }

        Darwin.shutdown(socketFD, SHUT_RDWR);
        close(socketFD);

        return port;
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
