//
//  ViewController.swift
//  Tor-Connect
//
//  Created by Peter Denton on 1/18/24.
//

import Cocoa

class ViewController: NSViewController {
    
    weak var torMgr = TorClient.sharedInstance

    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var configPathLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        torMgr?.start(delegate: self)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


}

extension ViewController: OnionManagerDelegate {
    func torConnProgress(_ progress: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            statusLabel.stringValue = "Bootstrapping \(progress)% complete."
        }
    }
    
    func torConnFinished() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch torMgr?.state {
            case .connected:
                statusLabel.stringValue = "Tor is connected."
            
            case .refreshing:
                statusLabel.stringValue = "Tor is refreshing."
            case .started:
                statusLabel.stringValue = "Tor started."
            case .stopped:
                statusLabel.stringValue = "Tor stopped."
            default:
                statusLabel.stringValue = "No status."
            }
        }
        print("hostname: \(torMgr?.hostnames())")
        
    }
    
    func torConnDifficulties() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            statusLabel.stringValue = "Tor connection difficulties..."
        }
    }
    
    
}

