//
//  ToastView.swift
//  PushBro
//

import SwiftUI

/// A transient confirmation snackbar: green capsule for success, red for
/// failure. Auto-dismisses after a few seconds; tap to dismiss early.
struct Toast: Equatable {
    var text: String
    var isSuccess = true
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let current = toast {
                    Label(current.text, systemImage: current.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(current.isSuccess ? Color.green : Color.red, in: Capsule())
                        .shadow(radius: 4, y: 2)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture {
                            toast = nil
                        }
                        .task(id: current) {
                            try? await Task.sleep(for: .seconds(3))
                            toast = nil
                        }
                }
            }
            .animation(.spring(duration: 0.35), value: toast)
    }
}
