//
//  IAPError.swift
//  AIVideo
//
//  Error types for in-app purchase operations
//  Copied from templates-reference
//

import Foundation

enum IAPError: Error {
    case purchaseFail
    case restoringFail
    case cancelledByUser
    case paymentRequestIsNotFinished
    case userIsUnauthorizedForPayments
    case noContent
    case noInternetConnection
    
    var message: String {
        switch self {
        case .purchaseFail:
            return "Purchase failed. Please try again."
        case .restoringFail:
            return "Failed to restore purchases. Please try again."
        case .cancelledByUser:
            return "Purchase was cancelled."
        case .paymentRequestIsNotFinished:
            return "Payment request is still processing."
        case .userIsUnauthorizedForPayments:
            return "You are not authorized to make payments."
        case .noContent:
            return "Unable to load subscription options."
        case .noInternetConnection:
            return "No internet connection. Please check your network."
        }
    }
}
