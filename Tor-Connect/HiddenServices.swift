//
//  HiddenServices.swift
//  Tor-Connect
//
//  Created by Peter Denton on 1/23/24.
//

import Cocoa

class HiddenServices: NSViewController {
    
    let chain = UserDefaults.standard.object(forKey: "chain") as? String ?? "main"
    let mainPort = UserDefaults.standard.object(forKey: "mainPort") as? String ?? "8332"
    let testPort = UserDefaults.standard.object(forKey: "testPort") as? String ?? "18332"
    let sigPort = UserDefaults.standard.object(forKey: "sigPort") as? String ?? "38332"
    let regPort = UserDefaults.standard.object(forKey: "regPort") as? String ?? "18443"
    
    @IBOutlet weak var switchNetworkOutlet: NSPopUpButton!
    @IBOutlet weak var authField: NSTextField!
    @IBOutlet weak var addressLabel: NSTextField!
    @IBOutlet weak var shareButton: NSButton!
    @IBOutlet weak var authorizedClients: NSTextField!
    @IBOutlet weak var deleteAuthHeader: NSTextField!
    @IBOutlet weak var deleteAuthButton: NSButton!
    
    
    weak var torMgr = TorClient.sharedInstance
    

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        deleteAuthButton.alphaValue = 0
        deleteAuthHeader.alphaValue = 0
        load()
    }
    
    @IBAction func torAuthHelpAction(_ sender: Any) {
        DispatchQueue.main.async {
            guard let url = URL(string: "https://community.torproject.org/onion-services/advanced/client-auth/") else { return }
            NSWorkspace.shared.open(url)
        }
    }
    
    @IBAction func deleteAuthClients(_ sender: Any) {
        var authClientPath = ""
        let btcMain = "\(torPath())/host/bitcoin/rpc/main/authorized_clients"
        let btcTest = "\(torPath())/host/bitcoin/rpc/test/authorized_clients"
        let btcRegtest = "\(torPath())/host/bitcoin/rpc/regtest/authorized_clients"
        let btcSignet = "\(torPath())/host/bitcoin/rpc/signet/authorized_clients"
        
        switch switchNetworkOutlet.indexOfSelectedItem {
        case 0:
            authClientPath = btcMain
        case 1:
            authClientPath = btcTest
        case 2:
            authClientPath = btcSignet
        case 3:
            authClientPath = btcRegtest
        default:
            break
        }
        
        let fileManager = FileManager.default
        
        do {
            let paths = try fileManager.contentsOfDirectory(atPath: authClientPath)
            for path in paths
            {
                try fileManager.removeItem(atPath: "\(authClientPath)/\(path)")
            }
        } catch let error as NSError {
            print(error.localizedDescription)
        }
        
        load()
        restartTorAlert()
    }
    
    
    
    func load() {
        guard let hiddenServices = torMgr?.hostnames() else { return }
        switch chain {
        case "main":
            self.switchNetworkOutlet.selectItem(at: 0)
            addressLabel.stringValue = hiddenServices[0] + ":" + mainPort
        case "test":
            self.switchNetworkOutlet.selectItem(at: 1)
            addressLabel.stringValue = hiddenServices[1] + ":" + testPort
        case "signet":
            self.switchNetworkOutlet.selectItem(at: 2)
            addressLabel.stringValue = hiddenServices[2] + ":" + sigPort
        case "regtest":
            self.switchNetworkOutlet.selectItem(at: 3)
            addressLabel.stringValue = hiddenServices[3] + ":" + regPort
        default:
            break
        }
        getAuthoizedClients()
    }
    
    @IBAction func saveAuthAction(_ sender: Any) {
        // descriptor:x25519:WVATZT4ZLOESCWQLE26CMNUB5RL255UJB5QCNDZW3BP5O5ZX2QWQ
        var authClientPath = ""
        let btcMain = "\(torPath())/host/bitcoin/rpc/main/authorized_clients"
        let btcTest = "\(torPath())/host/bitcoin/rpc/test/authorized_clients"
        let btcRegtest = "\(torPath())/host/bitcoin/rpc/regtest/authorized_clients"
        let btcSignet = "\(torPath())/host/bitcoin/rpc/signet/authorized_clients"
        
        switch switchNetworkOutlet.indexOfSelectedItem {
        case 0:
            authClientPath = btcMain
        case 1:
            authClientPath = btcTest
        case 2:
            authClientPath = btcSignet
        case 3:
            authClientPath = btcRegtest
        default:
            break
        }
        
        let fileManager = FileManager.default
        let filename = "Tor-Connect"// get a username from the user instead
        let pubkey = self.authField.stringValue.data(using: .utf8)
        
        do {
            try fileManager.createDirectory(atPath: authClientPath,
                                                    withIntermediateDirectories: true,
                                                    attributes: [FileAttributeKey.posixPermissions: 0o700])
        } catch {
            print("Directory previously created.")
        }
        
        fileManager.createFile(atPath: "\(authClientPath)/\(filename).auth", contents: pubkey, attributes: [FileAttributeKey.posixPermissions: 0o700])
        
        guard let data = fileManager.contents(atPath: "\(authClientPath)/\(filename).auth"),
                let retrievedPubkey = String(data: data, encoding: .utf8) else {
            //simpleAlert(message: "Auth key not added!", info: "Please reach out and let us know about this bug.", buttonLabel: "OK")
            return
        }
        
        if retrievedPubkey == self.authField.stringValue {
            restartTorAlert()
        } else {
            //simpleAlert(message: "Auth key error.", info: "Something went wrong and your auth key was not saved correctly. Please reach out and let us know about this bug.", buttonLabel: "OK")
        }
    }
    
    
    private func restartTorAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Done ✓"
            alert.informativeText = "Restart Tor-Connect for authentication to come into effect."
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .informational
            let modalResponse = alert.runModal()
            if modalResponse == NSApplication.ModalResponse.alertFirstButtonReturn {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.authField.stringValue = ""
                    load()
                }
            }
        }
    }
    
    @IBAction func copyAddressAction(_ sender: Any) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NSPasteboard.general.setString(addressLabel.stringValue, forType: .string)
            dialogOK(question: "Copied ✓", text: "Paste this string into Fully Noded to connect via Tor.")
        }
    }
    
    @IBAction func shareAddressAction(_ sender: Any) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let shareItems = [addressLabel.stringValue]
            let sharingPicker:NSSharingServicePicker = NSSharingServicePicker.init(items: shareItems)
            sharingPicker.show(relativeTo: shareButton.bounds, of: shareButton, preferredEdge: .minY)
        }
    }
    
    @IBAction func switchNetworkAction(_ sender: Any) {
        switch switchNetworkOutlet.indexOfSelectedItem {
        case 0:
            print("main")
            UserDefaults.standard.setValue("main", forKey: "chain")
        case 1:
            print("test")
            UserDefaults.standard.setValue("test", forKey: "chain")
        case 2:
            print("signet")
            UserDefaults.standard.setValue("signet", forKey: "chain")
        case 3:
            print("regtest")
            UserDefaults.standard.setValue("regtest", forKey: "chain")
        default:
            break
        }
        load()
    }
    
    
    private func dialogOK(question: String, text: String) {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func getAuthoizedClients() {
        var authClientPath = ""
        let btcMain = "\(torPath())/host/bitcoin/rpc/main/authorized_clients"
        let btcTest = "\(torPath())/host/bitcoin/rpc/test/authorized_clients"
        let btcRegtest = "\(torPath())/host/bitcoin/rpc/regtest/authorized_clients"
        let btcSignet = "\(torPath())/host/bitcoin/rpc/signet/authorized_clients"        
        
        switch switchNetworkOutlet.indexOfSelectedItem {
        case 0:
            authClientPath = btcMain
        case 1:
            authClientPath = btcTest
        case 2:
            authClientPath = btcSignet
        case 3:
            authClientPath = btcRegtest
        default:
            break
        }
        
        let fileManager = FileManager.default
        guard let dirContents = try? fileManager.contentsOfDirectory(atPath: authClientPath) else { return }
        authorizedClients.stringValue = "\(dirContents.count)"
        if dirContents.count > 0 {
            DispatchQueue.main.async { [weak self] in
                self?.deleteAuthButton.alphaValue = 1.0
                self?.deleteAuthHeader.alphaValue = 1.0
            }
        }
    }
    
    private func torPath() -> String {
        return "\(NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? "")/tor"
    }
    
}
