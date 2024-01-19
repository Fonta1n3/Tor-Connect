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
        
        let proxyPort = 19057
        let dnsPort = 12348
        
        sessionConfiguration.connectionProxyDictionary = [kCFProxyTypeKey: kCFProxyTypeSOCKS,
                                          kCFStreamPropertySOCKSProxyHost: "localhost",
                                          kCFStreamPropertySOCKSProxyPort: proxyPort]
        
        session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: .main)
        
        addTorrc()
        createTorDirectory()
        authDirPath = createAuthDirectory()
        
        
        self.thread = nil
        
        self.config.options = [
            "DNSPort": "\(dnsPort)",
            "AutomapHostsOnResolve": "1",
            "SocksPort": "\(proxyPort) OnionTrafficOnly",
            "AvoidDiskWrites": "1",
            "ClientOnionAuthDir": "\(self.authDirPath)",
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
    
    func hostnames() -> String? {
        // MARK - WIP!
        let jmHost = "\(torPath())/host/joinmarket/hostname"
        let btcMain = "\(torPath())/host/bitcoin/rpc/main/hostname"
        let btcTest = "\(torPath())/host/bitcoin/rpc/test/hostname"
        let btcRegtest = "\(torPath())/host/bitcoin/rpc/regtest/hostname"
        let btcSignet = "\(torPath())/host/bitcoin/rpc/signet/hostname"
        
        let hosts = [jmHost, btcMain, btcTest, btcRegtest, btcSignet]
        
//        for host in hosts {
//            let path = URL(fileURLWithPath: host)
//            print(try? String(contentsOf: path, encoding: .utf8))
//            
//        }
        
        let path = URL(fileURLWithPath: btcMain)
        return try? String(contentsOf: path, encoding: .utf8)
        
        
    }
    
    private func createAuthDirectory() -> String {
        // Create tor v3 auth directory if it does not yet exist
        let authPath = URL(fileURLWithPath: self.torPath(), isDirectory: true).appendingPathComponent("onion_auth", isDirectory: true).path
        
        do {
            try FileManager.default.createDirectory(atPath: authPath,
                                                    withIntermediateDirectories: true,
                                                    attributes: [FileAttributeKey.posixPermissions: 0o700])
        } catch {
            print("Auth directory previously created.")
        }
        
        return authPath
    }
    
    
    func turnedOff() -> Bool {
        return false
    }
}
