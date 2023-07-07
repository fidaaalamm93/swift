import Foundation
import UIKit
import SwiftUI
import LDSwiftEventSource

public final class Rupt {
    public static let shared = Rupt()

    private var eventSource: EventSource?
    public var clientID: String?
    public var secret: String?
    public var accountID: String?
    public var email: String?
    public var phone: String?
    public var limitExceeded: Bool?
    public var onChallenge: Bool?
    public var appearanceConfig: RuptAppearanceConfig?
    private let baseURL = "https://api.rupt.dev"
    private var window: UIWindow? = UIWindow(frame: UIScreen.main.bounds)
    private let rootVC = UIViewController()
    private let viewModel = DialogViewModel(currentDeviceID: "",
                                            attachedDevices: [],
                                            limitConfig: nil)
    /**
     * The unique device id generated and tracked by Rupt. It will be null until the first attach call.
     */
    public private(set) var deviceID: String? {
        set {
            UserDefaults.standard.set(newValue, forKey: "rupt_device_id")
            self.viewModel.currentDeviceID = newValue ?? ""
        }
        get {
            return UserDefaults.standard.string(forKey: "sabil_device_id") ?? UserDefaults.standard.string(forKey: "sabil_device_id")
        }
    }

    /**
     * The device identity. Each identity is unique across your application. If two devices have the same identity, that means they are the same physical device.
     */
    public private(set) var identity: String? {
        set {
            UserDefaults.standard.set(newValue, forKey: "sabil_device_identity")
        }
        get {
            return UserDefaults.standard.string(forKey: "sabil_device_identity")
        }
    }

    /// Called when the number of attached devices for  the user exceed the allotted limit.
    public var onLimitExceeded: ((Int) -> Void)?

    /**
     * Called when the user chooses to log out of the current device.
     *
     * This function will be called immediately after the user detaches the current device from the list of active devices.
     * The user can then continue using the app until the next attach.
     * It is **strongly recommended** that you log the user out when this function fires.
     */
    public var onLogoutCurrentDevice: ((RuptDevice?) -> Void)? {
        didSet {
            listenToRealtimeEvents()
        }
    }

    /**
     * Called when the user chooses to log out a remote device (as apposed to this device).
     *
     * This function will be called immeditely after the user detaches the current device from the list of active devices.
     * The user can then continue using the app until the next attach.
     * It is **strongly recommended** that you log the user out when this function fires.
     */
    public var onLogoutOtherDevice: ((RuptDevice) -> Void)?

    public func config(clientID: String, secret: String? = nil, appearanceConfig: RuptAppearanceConfig? = nil, limitConfig: RuptLimitConfig? = nil) {
        self.clientID = clientID
        self.secret = secret
        if let appearanceConfig = appearanceConfig {
            self.appearanceConfig = appearanceConfig
        }
        if let limitConfig = limitConfig {
            self.viewModel.limitConfig = limitConfig
        }
    }

    /**
     * Use this to set the user ID.
     * - Parameters:
     *  - parameter id: The user ID. Must be a string. If you have the user as anything other than a string, you must use a string representation of it. Send nil to remove the user ID (i.e. on logout).
     */
    public func setUserID(_ id: String?) {
        self.accountID = id
    }

    private func getDeviceIDForVendor() -> String {
        let vendorID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        return vendorID
    }
    
    private func getDeviceType() -> String {
        var deviceType = ""
        switch UIDevice.current.userInterfaceIdiom {
        case .unspecified:
            deviceType = "unspecified"
        case .phone, .pad:
            deviceType = "ios"
        case .tv:
            deviceType = "apple-tv"
        case .carPlay:
            deviceType = "car-play"
        case .mac:
            deviceType = "mac"
        @unknown default:
            break
        }
        return deviceType
    }

    fileprivate func httpRequest(method: String, url urlString: String, body: [String: Any]? = nil, onCompletion: ((Data?) -> Void)? = nil) {
        do {
            guard let clientID = clientID else {
                print("[Rupt SDK]: clientID must not be nil.")
                onCompletion?(nil)
                return
            }
            guard let url = URL(string: urlString) else {
                onCompletion?(nil)
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.addValue("application/json", forHTTPHeaderField: "Accept")
            req.addValue("Basic \(clientID):\(secret ?? "")", forHTTPHeaderField: "Authorization")
            if let body = body {
                req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            }
            let task = URLSession.shared.dataTask(with: req) { data, response, error in
                if let error = error {
                    print("[Rupt SDK]: \(error)")
                    onCompletion?(data)
                    return
                }
                onCompletion?(data)
            }
            task.resume()
        } catch {
            print("[Rupt SDK]: \(error)")
            onCompletion?(nil)
            return
        }
    }

    fileprivate func showBlockingDialog() {
        self.viewModel.detachLoading = true
        if (self.window == nil) {
            self.window = UIWindow(frame: UIScreen.main.bounds)
        }
        self.window?.rootViewController = self.rootVC
        self.rootVC.view.backgroundColor = .clear
        self.window?.makeKeyAndVisible()
        let dialogView = DialogView(viewModel: self.viewModel) { devices in
            for device in devices {
                self.detach(device: device)
            }
        }
        let dialogViewContoller = UIHostingController(rootView: dialogView)
        dialogViewContoller.isModalInPresentation = true
        self.rootVC.present(dialogViewContoller, animated: true)
        self.getUserAttachedDevices()
        self.viewModel.detachLoading = false
    }

    /**
     * Adds the device to the user's attached device list.
     *
     * Call this fuction to attach this device to the user. **You must set the userID & clientID first.**
     * If the userID is not set, nothing will happen.
     * Once the attaching is successfully concluded, if the user has  exceeded the limit of devices, the "onLimitExceeded" function will be called.
     * - You should call this function immeditely after you know the userID (i.e. after login, or after app launch).
     * - Multiple calls to this function for the same device will not count as different devices for the user.
     * - You should call this function ideally, in every view. But if that's not feasible, we suggest critical views and app launch and when entering foreground.
     * - Parameters:
     *  - parameter metadata: A key-value dictionary with any data that you want saved with all accesses
     */
    public func attach(metadata: [String: String]? = nil) {
        guard let accountID  = accountID else {
            print("[Rupt SDK]: userID must not be nil.")
            return
        }
        let deviceInfo = getDeviceInfo()
        var body: [String : Any] = ["user": accountID ,
                                    "device_info": deviceInfo,
                                    "signals": ["iosVendorIdentifier": getDeviceIDForVendor()],
                                    "metadata": metadata ?? [],
                                    "callbacks": ["limit_exceeded": self.limitExceeded != nil ? self.limitExceeded : false,
                                                  "on_challenge": self.onChallenge != nil ? self.onChallenge : false ],
                                    "client": getDeviceType(),
                                    "version": "3.0.0"]
        if let email = self.email {
            body["email"] = email
        }
        
        if let phone = self.phone {
            body["phone"] = phone
        }

        if let identity = self.identity {
            body["identity"] = identity
        }
        httpRequest(method: "POST", url: "\(baseURL)/v2/access", body: body) { data in

            guard let data = data else { return }
            let decoder = JSONDecoder()
            guard let attachResponse = try? decoder.decode(RuptAttachResponse.self, from: data) else { return }
            self.deviceID = attachResponse.deviceID
            guard let limit = self.viewModel.limitConfig?.overallLimit ?? attachResponse.defaultDeviceLimit else {
                return
            }
            DispatchQueue.main.async {
                self.viewModel.defaultDeviceLimit = limit
            }
            guard attachResponse.attachedDevices > limit else {
                return
            }
            DispatchQueue.main.async {
                self.onLimitExceeded?(attachResponse.attachedDevices)
            }
            guard self.appearanceConfig?.showBlockingDialog ?? attachResponse.blockOverUsage ?? false else {
                return
            }

            DispatchQueue.main.async {
                self.showBlockingDialog()
            }
        }
    }

    public func identify(metadata: [String: String]? = nil, onCompletion: ((RuptDeviceIdentity?, RuptError?) -> Void)? = nil) {
        let deviceInfo = getDeviceInfo()
        var body: [String : Any] = ["device_info": deviceInfo, "signals": ["iosVendorIdentifier": getDeviceIDForVendor()], "metadata": metadata ?? []]
        if let identity = self.identity {
            body["identity_id"] = identity
        }
        httpRequest(method: "POST", url: "\(baseURL)/v2/identity", body: body) { data in

            guard let data = data else {
                onCompletion?(nil, RuptError(message: "Could not identify device"))
                return
            }
            let decoder = JSONDecoder()
            guard let identityResponse = try? decoder.decode(RuptDeviceIdentity.self, from: data) else {
                onCompletion?(nil, RuptError(message: "Unable to decode device response"))
                return
            }
            self.identity = identityResponse.identity
            DispatchQueue.main.async {
                onCompletion?(identityResponse, nil)
            }
        }
    }

    fileprivate func getDeviceInfo() -> [String: Any] {
        return [
            "os": ["name": UIDevice.current.systemName, "version": UIDevice.current.systemVersion],
            "device": [
                "vendor": "Apple",
                "model": UIDevice.current.model,
                "type": deviceType().rawValue]]
    }

    fileprivate func deviceType() -> RuptDeviceType {
        return UIDevice.current.model.contains("iPad") ? .tablet : .mobile
    }

    /**
     * Detaches the devices from the user device list.
     *
     * Call this function only when the device is no longer attached to the user. A common place to call this function is the logout sequence. You should not call this function anywhere else unless you are an advancer user and you know what you're doing.
     */
    public func detach(device: RuptDevice) {
        detach(deviceID: device.id) { response in
            guard response?.success == true else {
                return
            }
            DispatchQueue.main.async {
                self.viewModel.attachedDevices.removeAll(where: {$0.id == device.id})
                self.viewModel.defaultDeviceLimit = response?.defaultDeviceLimit ?? self.viewModel.defaultDeviceLimit

                if device.id != self.deviceID {
                    self.onLogoutOtherDevice?(device)
                }

                if let limit = self.viewModel.limitConfig?.overallLimit ?? response?.defaultDeviceLimit, self.viewModel.attachedDevices.count <= limit {
                    self.hideBlockingDialog()
                }
            }
        }
    }

    public func detach(deviceID device: String, completion: ((RuptAttachResponse?) -> Void)? = nil) {
        guard let accountID = accountID else {
            print("[Rupt SDK]: accountID must not be nil.")
            completion?(nil)
            return
        }

        var body: [String : Any] = [
            "device": device,
            "user": accountID]

        httpRequest(method: "POST", url: "\(baseURL)/v2/access/detach", body: body) { data in
            guard let data = data else { return }
            let decoder = JSONDecoder()
            do {
                completion?(try decoder.decode(RuptAttachResponse.self, from: data))
            } catch {
                print("[Rupt SDK]: \(error)")
                completion?(nil)
            }
        }
    }

    fileprivate func hideBlockingDialog() {
        self.rootVC.dismiss(animated: true)
        self.window?.resignKey()
        self.window = nil
    }

    /**
     * Returns the devices currently attached to the user.
     */
    public func getUserAttachedDevices() {
        guard let userID = accountID else {
            print("[Rupt SDK]: userID must not be nil.")
            return
        }
        self.viewModel.loadingDevices = true
        httpRequest(method: "GET", url: "\(baseURL)/v2/access/user/\(userID)/attached_devices") { data in
            DispatchQueue.main.async {
                self.viewModel.loadingDevices = false
            }

            guard let data = data else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(.iso8601Full)
            do {
                let devices = try decoder.decode([RuptDevice].self, from: data)
                DispatchQueue.main.async {
                    self.viewModel.attachedDevices = devices
                }
            } catch {
                print("[Rupt SDK]: \(error)")
            }
        }
    }
}


extension Rupt: EventHandler {

    func listenToRealtimeEvents() {
        if let clientID = clientID, let device = deviceID, let url = URL(string: "\(baseURL)/v2/access/device/\(device)/listen?auth=Basic \(clientID):\(secret ?? "")".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
            eventSource?.stop()
            eventSource = EventSource(config: EventSource.Config(handler: self, url: url))
            eventSource?.start()
        }
    }

    public func onOpened() {
        // left empty on purpose
    }

    public func onClosed() {
        // left empty on purpose
    }

    public func onMessage(eventType: String, messageEvent: LDSwiftEventSource.MessageEvent) {
        if messageEvent.data == "\"logout\"" {
            DispatchQueue.main.async {
                self.onLogoutCurrentDevice?(self.viewModel.attachedDevices.first(where: {$0.id == self.deviceID}))
                self.hideBlockingDialog()
            }

        }
    }

    public func onComment(comment: String) {
        // left empty on purpose
    }

    public func onError(error: Error) {
        // left empty on purpose
    }


}
