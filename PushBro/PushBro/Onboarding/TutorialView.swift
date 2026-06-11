//
//  TutorialView.swift
//  PushBro
//

import SwiftUI

/// Paged how-it-works guide. Shown full-screen on first launch and as a
/// large sheet from the ? button on the Workout screen or Settings.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private static let pages: [TutorialPage] = [
        TutorialPage(
            icon: "iphone.gen3",
            title: "Phone on the floor",
            text: "Place your iPhone flat on the floor, screen up, directly under your face — where your nose points at the bottom of a rep. Do your pushups right over it."
        ),
        TutorialPage(
            icon: "camera.viewfinder",
            title: "The camera counts",
            text: "The front camera measures the distance to your face as you go down and up. Calibrate once — fully up, then fully down — and PushBro knows your range. Adjust how deep a rep must be in Settings."
        ),
        TutorialPage(
            icon: "mic.fill",
            title: "Totally hands-free",
            text: "Say “start” when you're in position and a countdown begins. Every rep is spoken aloud so you never need to look. Say “stop” when you're done — no phantom reps while you get up."
        ),
        TutorialPage(
            icon: "flame.fill",
            title: "Build the habit",
            text: "Set a daily goal, keep your streak alive, and watch the calendar fill up. Rest a few seconds mid-session and PushBro splits your workout into sets automatically."
        ),
        TutorialPage(
            icon: "lightbulb.max.fill",
            title: "Tips for best results",
            text: "Good lighting helps face tracking. Keep the phone under your face so you stay in frame all the way down — the camera losing you right at the bottom is normal and accounted for. If a device can't track faces, Tap mode counts nose-taps instead."
        ),
    ]

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button("Skip") {
                    dismiss()
                }
                .padding()
                .opacity(page == Self.pages.count - 1 ? 0 : 1)
            }

            TabView(selection: $page) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, tutorialPage in
                    VStack(spacing: 24) {
                        Image(systemName: tutorialPage.icon)
                            .font(.system(size: 80))
                            .foregroundStyle(.tint)
                        Text(tutorialPage.title)
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(tutorialPage.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                    .padding(.bottom, 48)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < Self.pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < Self.pages.count - 1 ? "Next" : "Let's go")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}

private struct TutorialPage {
    let icon: String
    let title: String
    let text: String
}

#Preview {
    TutorialView()
}
