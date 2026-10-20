//
//  VoiceNotePrefetching.swift
//  NaarsCars
//

import Foundation

/// The narrow interface MessagingSyncEngine uses to warm a newly received voice note
/// (decisions A6 point 1). The conformer downloads through the signed storage path and keeps
/// the bytes keyed by the stored URL; it never persists or logs the signed URL. Fire-and-forget:
/// a failure is silent and the first tap downloads again.
@MainActor
protocol VoiceNotePrefetching: AnyObject {
    func prefetch(_ storedURL: URL) async
}
