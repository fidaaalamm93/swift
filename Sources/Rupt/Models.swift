//
//  Models.swift
//  RuptSDK
//
//  Created by Ahmed Saleh on 7/11/22.
//

import Foundation

public struct RuptError: Error {
    public let message: String
}

public struct RuptAppearanceConfig {
    public let showBlockingDialog: Bool
    
    public init(showBlockingDialog: Bool) {
        self.showBlockingDialog = showBlockingDialog
    }
}

public struct RuptLimitConfig {
    public let mobileLimit: Int
    public let overallLimit: Int
    
    public init(mobileLimit: Int, overallLimit: Int) {
        self.mobileLimit = mobileLimit
        self.overallLimit = overallLimit
    }
}

public struct RuptOS: Codable {
    public let name: String?
    public let version: String?
}

public struct RuptDeviceDetails: Codable {
    public let vendor: String?
    public let type: String?
    public let model: String?
}

public struct RuptDeviceInfo: Codable {
    public let os: RuptOS?
    public let device: RuptDeviceDetails?
}

public struct RuptDevice: Codable, Identifiable, Hashable {
    public let id: String
    public let info: RuptDeviceInfo
    public let user: String
    public let createdAt: Date
    public let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case info, user, createdAt, updatedAt
    }

    public static func == (lhs: RuptDevice, rhs: RuptDevice) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct RuptAttachResponse: Decodable {
    public let deviceID: String
    public let attachedDevices: Int
    public let success: Bool
    public let blockOverUsage: Bool?
    public let defaultDeviceLimit: Int?

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case attachedDevices = "attached_devices"
        case blockOverUsage = "block_over_usage"
        case defaultDeviceLimit = "default_device_limit"
        case success

    }
}

public struct RuptDeviceIdentity: Decodable {
    public let identity: String
    public let confidence: Double
}

public enum RuptDeviceType: String {
    case mobile
    case tablet
    case computer
}
