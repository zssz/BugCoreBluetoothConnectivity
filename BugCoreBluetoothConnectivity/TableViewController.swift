//
//  TableViewController.swift
//  BugCoreBluetoothConnectivity
//
//  Connects to discovered peripherals nearby periodically. An established connection will be disconnected after a timeout.
//
//  Run the app on at least 3 iOS devices at the same time to reproduce the issue quickly. I tested this with iPhone X, iPhone 7, iPhone SE, iPad (11.2.5) and with Bluetooth turned on on my MacBook Pro.
//  Expected result: The devices will connect to each other and disconnect shortly after.
//  Actual result: After a few minutes some devices won't be able to connect to discovered peripherals. All peripherals in their list will be in connecting state (orange rows). However, if a nearby device connects to them then the connection is established (green row). If you suspect that a specific device has reached this state (where it can not connect to peripherals nearby) then turn off scanning (switch control top right) on all other devices where the app is foreground running. Once a device has reached this state the only way to fix it is by going to Settings and toggling Bluetooth.
//  Related developer forums post (I'm not the author): https://forums.developer.apple.com/thread/94011
//
//  Created by Zsombor Szabo on 02/02/2018.
//  Copyright © 2018 Zsombor Szabo. All rights reserved.
//

import UIKit
import CoreBluetooth
import os.log

// Time interval after we consider the peripheral out of range (no recent advertisement data).
let discoveryTimeout: TimeInterval = 31

// Time interval between each peripheral connection attempts.
let connectionCycle: TimeInterval = 8

// Time interval after a connected peripheral will be disconnected.
let connectionTimeout: TimeInterval = 2

// The UUID of the service being advertised. Generated with uuidgen.
let serviceUUID = CBUUID(string: "8088D72C-11FC-4B87-ACC5-9F1B8720C052")

// The UUID of the sole characteristic that the advertised service contains. Generated with uuidgen.
let characteristicUUID = CBUUID(string: "73355FB9-8503-463D-BFE7-824C74A23A3A")

private let cellReuseIdentifier = "reuseIdentifier"
private var peripheralStateObservationContext = 0

class TableViewController: UITableViewController {
    
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "TVC")
    
    var centralManager: CBCentralManager!
    
    var peripheralManager: CBPeripheralManager!
    
    lazy var characteristic = CBMutableCharacteristic(type: characteristicUUID, properties: [.write], value: nil, permissions: [.writeable])

    lazy var peripheralService: CBMutableService = {
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        return service
    }()
    
    private var peripherals = [CBPeripheral]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Peripherals"
        navigationItem.prompt = "Black:=Disconnected Orange:=Connecting Green:=Connected"
        
        centralManager = CBCentralManager(delegate: self, queue: nil, options: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
    }
    
    @IBAction func toggleScan(_ sender: UISwitch) {
        isScanning = sender.isOn
    }
    
    var isScanning = true {
        didSet {
            guard oldValue != isScanning else {
                return
            }
            isScanning ? startScan() : stopScan()
        }
    }

    // MARK: - Table view

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.peripherals.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath)
        self.tableView(self.tableView, configureCell: cell, forRowAtIndexPath: indexPath)
        return cell
    }
    
    func tableView(_ tableView: UITableView, configureCell cell: UITableViewCell, forRowAtIndexPath indexPath: IndexPath, error: Error? = nil) -> Void {
        var peripheral: CBPeripheral?
        if indexPath.row < self.peripherals.count {
            peripheral = self.peripherals[indexPath.row]
        }
        cell.textLabel?.text = peripheral?.name
        cell.detailTextLabel?.text = peripheral?.identifier.uuidString

        var color = UIColor.black
        if let peripheral = peripheral {
            switch peripheral.state {
            case .connected:
                color = .green
            case .connecting:
                color = .orange
            default: ()
            }
        }
        if error != nil {
            color = .red
        }
        cell.textLabel?.textColor = color
        cell.detailTextLabel?.textColor = color
    }
    
    func configureTableViewCellIfNeededForPeripheral(_ peripheral: CBPeripheral, error: Error? = nil) {
        if let index = self.peripherals.index(of: peripheral) {
            let indexPath = IndexPath(row: index, section: 0)
            if let cell = self.tableView.cellForRow(at: indexPath) {
                self.tableView(self.tableView, configureCell: cell, forRowAtIndexPath: indexPath, error: error)
            }
        }
    }

}

extension TableViewController: CBPeripheralManagerDelegate {
    
    func peripheralManagerDidUpdateState(_ peripheralManager: CBPeripheralManager) {
        os_log("Peripheral manager did update state=%d.", log: TableViewController.log, peripheralManager.state.rawValue)
        
        if peripheralManager.state == .poweredOn {
            peripheralManager.removeAllServices()
            peripheralManager.add(peripheralService)
        }
    }
    
    func peripheralManager(_ peripheralManager: CBPeripheralManager, didAdd service: CBService, error: Error?) {                
        if let error = error {
            os_log("Peripheral manager did add service=%@ failed=%@.", log: TableViewController.log, type: .error, service.description, error as CVarArg)
            return
        }
        os_log("Peripheral manager did add service=%@.", log: TableViewController.log, service.description)
        
        peripheralManager.stopAdvertising()
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [serviceUUID]])
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            os_log("Peripheral manager did start advertising failed=%@.", log: TableViewController.log, type: .error, error as CVarArg)
            return
        }
        os_log("Peripheral manager did start advertising.", log: TableViewController.log)
    }
    
}

extension TableViewController: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ centralManager: CBCentralManager) {
        os_log("Central manager did update state=%d.", log: TableViewController.log, centralManager.state.rawValue)
        
        if centralManager.state == .poweredOn {
            isScanning ? startScan() : stopScan()
        }
        else {
            flushPeripherals()
        }
    }
    
    func startScan() {
        guard centralManager.state == .poweredOn else {
            return
        }
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey : NSNumber(booleanLiteral: true)])
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Have we seen this peripheral before?
        if let _ = self.peripherals.index(where: { $0 == peripheral }) {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.discoveryTimeoutForPeripheral), object: peripheral)
            self.perform(#selector(self.discoveryTimeoutForPeripheral), with: peripheral, afterDelay: discoveryTimeout)
        }
        else {
            os_log("Central manager did discover new peripheral (.identifier=%@ .name=%@).", log: TableViewController.log, peripheral.identifier.description, peripheral.name ?? "")
            self.peripherals.append(peripheral)
            self.tableView.insertRows(at: [IndexPath(row: self.peripherals.count-1, section: 0)], with: .automatic)
            peripheral.addObserver(self, forKeyPath: "state", options: [.new, .old], context: &peripheralStateObservationContext)
            self.connectToPeripheral(peripheral)
        }
    }
    
    @objc private func connectToPeripheral(_ peripheral: CBPeripheral) {
        os_log("Central manager connecting peripheral (.identifier=%@ .name=%@)...", log: TableViewController.log, peripheral.identifier.description, peripheral.name ?? "")
        centralManager.connect(peripheral, options: nil)
    }
    
    @objc private func discoveryTimeoutForPeripheral(_ peripheral: CBPeripheral) {
        os_log("Discovery timeout for peripheral (.identifier=%@ .name=%@).", log: TableViewController.log, peripheral.identifier.description, peripheral.name ?? "")
        flushPeripheral(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("Central manager did connect peripheral (.identifier=%@ .name=%@).", log: TableViewController.log, peripheral.identifier.description, peripheral.name ?? "")
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.cancelPeripheralConnection), object: peripheral)
        self.perform(#selector(self.cancelPeripheralConnection(_:)), with: peripheral, afterDelay: connectionTimeout)
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.connectToPeripheral), object: peripheral)
        self.perform(#selector(self.connectToPeripheral), with: peripheral, afterDelay: connectionCycle)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            os_log("Central manager did fail to connect peripheral (.identifier=%@ .name=%@) error=%@.", log: TableViewController.log, type: .error, peripheral.identifier.description, peripheral.name ?? "", error as CVarArg)
            configureTableViewCellIfNeededForPeripheral(peripheral, error: error)
        }
        else {
            os_log("Central manager did fail to connect peripheral (.identifier=%@ .name=%@).", log: TableViewController.log, type: .error, peripheral.identifier.description, peripheral.name ?? "")
            configureTableViewCellIfNeededForPeripheral(peripheral, error: NSError(domain: CBErrorDomain, code: CBError.Code.connectionFailed.rawValue, userInfo: nil))
        }
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.connectToPeripheral), object: peripheral)
        self.perform(#selector(self.connectToPeripheral), with: peripheral, afterDelay: connectionCycle)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            os_log("Central manager did disconnect peripheral (.identifier=%@ .name=%@) error=%@.", log: TableViewController.log, type: .error, peripheral.identifier.description, peripheral.name ?? "", error as CVarArg)
        }
        else {
            os_log("Central manager did disconnect peripheral (.identifier=%@ .name=%@).", log: TableViewController.log, peripheral.identifier.description, peripheral.name ?? "")
        }
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.connectToPeripheral), object: peripheral)
        self.perform(#selector(self.connectToPeripheral), with: peripheral, afterDelay: connectionCycle)
    }
    
    func stopScan() {
        flushPeripherals()
        guard centralManager.state == .poweredOn else {
            return
        }
        centralManager.stopScan()
    }
    
    @objc private func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
        guard centralManager.state == .poweredOn else {
            return
        }
        if (peripheral.state == .connected || peripheral.state == .connecting) && peripheral.state != .disconnecting {
            os_log("Canceled connection to peripheral (.identifier=%@ .name=%@).", log: TableViewController.log, peripheral.identifier.description, peripheral.name ?? "")
            self.centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    private func flushPeripherals() {
        self.peripherals.forEach({
            self.flushPeripheral($0)
        })
    }
    
    private func flushPeripheral(_ peripheral: CBPeripheral) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.connectToPeripheral), object: peripheral)
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.discoveryTimeoutForPeripheral), object: peripheral)
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.cancelPeripheralConnection(_:)), object: peripheral)
        if let index = self.peripherals.index(of: peripheral) {
            peripheral.removeObserver(self, forKeyPath: "state", context: &peripheralStateObservationContext)
            self.peripherals.remove(at: index)
            self.tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        }
        self.cancelPeripheralConnection(peripheral)
    }
    
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &peripheralStateObservationContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        if let keyPath = keyPath, keyPath == "state", let object = object as? CBPeripheral {
            self.configureTableViewCellIfNeededForPeripheral(object)
        }
    }
    
}
