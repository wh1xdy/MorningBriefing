import SwiftUI

/// Compact chat popover (~300×400). Shows last Q&A + text input.
/// Expand button opens the full BriefingPanel.
struct ChatView: View {
    @ObservedObject var vm: ChatViewModel
    @ObservedObject var briefingVM: BriefingViewModel
    var onExpand: () -> Void

    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            GradientBackground()
            VStack(spacing: 0) {
                toolbar
                Divider().opacity(0.3)
                conversationArea
                Divider().opacity(0.3)
                inputBar
            }
        }
        .frame(width: 300, height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .onAppear { focused = true }
    }

    // MARK: – Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.yellow)
                .imageScale(.small)
            Text("MorningBriefing")
                .font(.system(.subheadline, weight: .semibold))
            Spacer()
            if let p = briefingVM.result?.plugins.elpris?.data {
                Text(String(format: "%.0f öre", p.avgPrice))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help("Expandera")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: – Conversation

    @ViewBuilder
    private var conversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if vm.messages.isEmpty {
                        Text("Ställ en fråga om elmarknaden eller dagens briefing.")
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(vm.messages) { msg in
                        if msg.role == .user {
                            HStack {
                                Spacer()
                                Text(msg.text)
                                    .font(.body)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.15),
                                                in: RoundedRectangle(cornerRadius: 12))
                            }
                        } else {
                            Text(msg.text)
                                .font(.body)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(.quaternary.opacity(0.5),
                                            in: RoundedRectangle(cornerRadius: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                    }

                    if vm.isLoading {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.65)
                            Text("Tänker…").font(.callout).foregroundStyle(.secondary)
                        }
                    } else if let err = vm.error {
                        Text("Fel: \(err)")
                            .font(.caption).foregroundStyle(.red)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(14)
                .animation(.easeOut(duration: 0.2), value: vm.messages.count)
            }
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: vm.isLoading) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: – Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Fråga om elmarknaden…", text: $input)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { submit() }
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(input.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(input.isEmpty || vm.isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submit() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !vm.isLoading else { return }
        input = ""
        vm.send(q)
    }
}
