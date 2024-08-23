//
//  SigmaSSAIInterface.swift
//  SSAI Tracking
//
//  Created by Pham Hai on 13/01/2023.
//

import Foundation

public protocol SigmaSSAIInterface {
    func onSessionFail()
    func onSessionInitSuccess(_ videoUrl: String)
    func onSessionUpdate(_ videoUrl: String)
    func onTracking(_ message: String)
}
