//
//  SharedExtensions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Dispatch

// MARK: - CGError

public extension CGError {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .success: "\(rawValue): success"
        case .failure: "\(rawValue): failure"
        case .illegalArgument: "\(rawValue): illegalArgument"
        case .invalidConnection: "\(rawValue): invalidConnection"
        case .invalidContext: "\(rawValue): invalidContext"
        case .cannotComplete: "\(rawValue): cannotComplete"
        case .notImplemented: "\(rawValue): notImplemented"
        case .rangeCheck: "\(rawValue): rangeCheck"
        case .typeCheck: "\(rawValue): typeCheck"
        case .invalidOperation: "\(rawValue): invalidOperation"
        case .noneAvailable: "\(rawValue): noneAvailable"
        @unknown default: "\(rawValue): unknown"
        }
    }
}

// MARK: - CGPoint

public extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

// MARK: - CGRect

public extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

// MARK: - DispatchQueue

public extension DispatchQueue {}
