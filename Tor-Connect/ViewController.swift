//
//  ViewController.swift
//  Tor-Connect
//
//  Created by Peter Denton on 1/18/24.
//

import Cocoa

class ViewController: NSViewController {
    
    weak var torMgr = TorClient.sharedInstance
    
    
    @IBOutlet weak var hiddenServicesLabel: NSTextField!
    @IBOutlet weak var hiddenServicesImage: NSImageView!
    @IBOutlet weak var statusImage: NSImageView!
    @IBOutlet weak var statusLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        hiddenServicesImage.alphaValue = 0
        hiddenServicesLabel.alphaValue = 0
        
        if UserDefaults.standard.value(forKey: "chain") == nil {
            UserDefaults.standard.setValue("main", forKey: "chain")
        }
        torMgr?.start(delegate: self)
    }

    
}

extension ViewController: OnionManagerDelegate {
    func torConnProgress(_ progress: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            statusLabel.stringValue = "Bootstrapping \(progress)% complete"
        }
    }
    
    func torConnFinished() {
        DispatchQueue.main.async { [weak self] in
            self?.hiddenServicesImage.alphaValue = 1
            self?.hiddenServicesLabel.alphaValue = 1
        }
        
        if torMgr?.hostnames() != nil {
            DispatchQueue.main.async { [weak self] in
                self?.hiddenServicesImage.contentTintColor = .green
                self?.hiddenServicesLabel.stringValue = "Hidden services configured"
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch torMgr?.state {
            case .connected:
                statusLabel.stringValue = "Tor v0.4.8.10 connected ✓"
                statusImage.contentTintColor = .green
                if torMgr?.hostnames() != nil {
                    hiddenServicesLabel.stringValue = "Hidden services active ✓"
                }
            
            case .refreshing:
                statusLabel.stringValue = "Tor refreshing..."
                statusImage.contentTintColor = .yellow
                
            case .started:
                statusLabel.stringValue = "Tor started..."
                statusImage.contentTintColor = .yellow
            case .stopped:
                statusLabel.stringValue = "Tor stopped..."
                statusImage.contentTintColor = .yellow
            default:
                statusLabel.stringValue = "No status..."
                statusImage.contentTintColor = .gray
            }
        }
    }
    
    func torConnDifficulties() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            statusLabel.stringValue = "Tor connection difficulties..."
        }
    }
    
    
}

