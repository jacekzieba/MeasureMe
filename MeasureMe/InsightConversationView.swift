import SwiftUI

struct InsightConversationView: View {
    let metricTitle: String
    let originalInsight: String
    let input: MetricInsightInput

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [InsightMessage] = []
    @State private var questionText = ""
    @State private var isLoading = false
    @State private var followUpCount = 0
    @FocusState private var isInputFocused: Bool

    private let maxFollowUps = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }

                            if isLoading {
                                loadingBubble
                                    .id("loading")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) {
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: isLoading) {
                        if isLoading {
                            withAnimation {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()
                    .overlay(AppColorRoles.borderSubtle)

                inputBar
            }
            .background(AppColorRoles.surfaceCanvas)
            .navigationTitle(AppLocalization.string("Ask about") + " " + metricTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                    .accessibilityLabel(AppLocalization.string("Close"))
                }
            }
        }
        .onAppear {
            messages = [InsightMessage(role: .assistant, text: originalInsight)]
        }
        .onDisappear {
            Task {
                await MetricInsightService.shared.clearConversation()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Message Bubbles

    @ViewBuilder
    private func messageBubble(_ message: InsightMessage) -> some View {
        switch message.role {
        case .assistant:
            assistantBubble(message.text)
        case .user:
            userBubble(message.text)
        }
    }

    private func assistantBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(AppTypography.iconSmall)
                .foregroundStyle(AppColorRoles.accentPrimary)
                .padding(6)
                .background(AppColorRoles.accentPrimary.opacity(0.12))
                .clipShape(Circle())

            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColorRoles.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func userBubble(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.body)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColorRoles.accentPrimary)
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
    }

    private var loadingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(AppTypography.iconSmall)
                .foregroundStyle(AppColorRoles.accentPrimary)
                .padding(6)
                .background(AppColorRoles.accentPrimary.opacity(0.12))
                .clipShape(Circle())

            Text("Thinking...")
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
                .redacted(reason: .placeholder)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColorRoles.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var inputBar: some View {
        if followUpCount >= maxFollowUps {
            Text(AppLocalization.string("You've reached the follow-up limit"))
                .font(AppTypography.micro)
                .foregroundStyle(AppColorRoles.textSecondary)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 8) {
                TextField(AppLocalization.string("Ask a question..."), text: $questionText, axis: .vertical)
                    .font(AppTypography.body)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppColorRoles.surfaceGlass)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )

                Button {
                    sendQuestion()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? AppColorRoles.accentPrimary : AppColorRoles.textSecondary.opacity(0.4))
                }
                .disabled(!canSend)
                .accessibilityLabel(AppLocalization.string("Send"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var canSend: Bool {
        !questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    private func sendQuestion() {
        let trimmed = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = InsightMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        questionText = ""
        isLoading = true

        Task {
            do {
                let response = try await MetricInsightService.shared.followUp(
                    question: trimmed,
                    originalInsight: originalInsight,
                    input: input
                )
                messages.append(InsightMessage(role: .assistant, text: response))
                followUpCount += 1
            } catch {
                messages.append(InsightMessage(role: .assistant, text: AppLocalization.string("Sorry, I couldn't generate a response. Please try again.")))
            }
            isLoading = false
        }
    }
}
