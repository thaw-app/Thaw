//
//  ErrorAlert.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI

extension View {
    /// OK clears the binding; caller-supplied titles describe failures sharing a catch block better than generic error names.
    /// The optional role preserves Escape dismissal where needed.
    func errorAlert(
        _ title: LocalizedStringKey,
        message: Binding<String?>,
        role: ButtonRole? = nil
    ) -> some View {
        alert(title, item: message) { _ in
            Button("OK", role: role) {}
        } message: { message in
            Text(message)
        }
    }

    /// Uses the error's own wording without duplication or a replacement title; clearing the binding dismisses the alert.
    func errorAlert(_ error: Binding<(some LocalizedError)?>) -> some View {
        alert(
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        error.wrappedValue = nil
                    }
                }
            ),
            error: error.wrappedValue
        ) {
            Button("OK") {
                error.wrappedValue = nil
            }
        }
    }
}
