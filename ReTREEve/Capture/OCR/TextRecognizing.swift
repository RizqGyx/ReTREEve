//  TextRecognizing.swift
//  The boundary between "how text was read" and "what the app does with it".
//
//  Implementations return a CapturedPage — text WITH position, never a bare
//  String. Flattening OCR to a String would make automatic marked-region
//  detection impossible later, because there would be nothing to overlap a
//  detected highlight against.

import Foundation
import UIKit

enum TextRecognitionError: LocalizedError {
    case unreadableImage
    case noTextFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "That photo couldn't be read."
        case .noTextFound:
            "No text was found on this page."
        case .failed(let reason):
            reason
        }
    }

    /// Shown under the title. Always tells the reader what to actually do next.
    var recoverySuggestion: String? {
        switch self {
        case .unreadableImage:
            "Take the photo again, holding the camera steady above the page."
        case .noTextFound:
            "Move closer to the page, make sure it's evenly lit, and try again."
        case .failed:
            "Try capturing the page again."
        }
    }
}

protocol TextRecognizing: Sendable {
    /// Reads `image` and returns it alongside every region found, in reading order.
    /// Throws `TextRecognitionError.noTextFound` rather than returning an empty
    /// page, so callers handle "nothing readable" as one explicit case.
    func recognizePage(in image: UIImage) async throws -> CapturedPage
}
