//
//  File.swift
//  
//
//  Created by Ahmed Saleh on 7/11/22.
//

import Foundation

final class DialogViewModel: ObservableObject {
    @Published var currentDeviceID: String
    @Published var attachedDevices: [RuptDevice] = []
    @Published var limitConfig: RuptLimitConfig?
    @Published var loadingDevices: Bool = false
    @Published var detachLoading: Bool = false
    @Published var defaultDeviceLimit: Int = 0

    init(currentDeviceID: String, attachedDevices: [RuptDevice], limitConfig: RuptLimitConfig?) {
        self.currentDeviceID = currentDeviceID
        self.attachedDevices = attachedDevices
        self.limitConfig = limitConfig
    }
}
