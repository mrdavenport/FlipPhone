import SwiftUI

private let howToImages = ["howto-kitchen", "howto-playground", "howto-field", "howto-coffee"]

struct HowToStartView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentImageIndex = 0
    private let cycleInterval: TimeInterval = 3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                phoneImageSection
                stepsSection
                footnotesSection
                    .padding(.bottom, 24)
                dismissButton
            }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Subviews

    private var phoneImageSection: some View {
        ZStack {
            ForEach(howToImages.indices, id: \.self) { index in
                Image(howToImages[index])
                    .resizable()
                    .scaledToFill()
                    .opacity(index == currentImageIndex ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8), value: currentImageIndex)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 20))
        .padding(.bottom, 24)
        .onAppear {
            startCycling()
        }
    }

    private func startCycling() {
        Timer.scheduledTimer(withTimeInterval: cycleInterval, repeats: true) { _ in
            currentImageIndex = (currentImageIndex + 1) % howToImages.count
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepRow(number: 1, title: "Flip phone.", text: "Place your phone face down on any flat surface")
            StepRow(number: 2, title: "Focus.", text: "Your focus session starts automatically")
            StepRow(number: 3, title: "Get rewards.", text: "Pick your phone up to end the session and save your time")
        }
        .padding(.bottom, 20)
    }

    private var footnotesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FootnoteRow(icon: "clock.badge.xmark", text: "Sessions under 5 seconds are not saved")
            FootnoteRow(icon: "lock.display", text: "For best results, enable auto-lock in your iPhone Settings so the screen turns off while face down")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 14))
    }

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Got it")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(UIColor.systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: .rect(cornerRadius: 16))
        }
    }
}

// MARK: - Supporting Views

private struct StepRow: View {
    let number: Int
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color(UIColor.systemBackground))
                .frame(width: 28, height: 28)
                .background(.white, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(text)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FootnoteRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    Color.black.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            HowToStartView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(UIColor.secondarySystemBackground))
        }
}
