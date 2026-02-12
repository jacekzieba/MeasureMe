import SwiftUI

struct FAQView: View {
    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 260)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenTitleHeader(title: AppLocalization.string("FAQ"), topPadding: 6, bottomPadding: 8)

                    faqSection(
                        title: "Getting started",
                        items: [
                            faqItem(
                                question: "How do I take measurements?",
                                answer: "Measure at a consistent time of day, in similar conditions, and record trends rather than single readings."
                            ),
                            faqItem(
                                question: "Why are circumference measurements important?",
                                answer: "You can build muscle and lose fat at the same time, so the scale might not change much. Waist circumference often reflects fat loss more clearly than weight alone."
                            ),
                            faqItem(
                                question: "What tools should I use for measurements?",
                                answer: "Use a soft measuring tape for circumferences. For weight and body fat, a smart scale can be helpful, but it can have a margin of error. The most accurate body composition results come from a DEXA scan."
                            ),
                            faqItem(
                                question: "What time of day should I measure?",
                                answer: "For best consistency, measure in the morning after using the bathroom and before eating or drinking."
                            ),
                            faqItem(
                                question: "How do I add measurements?",
                                answer: "Use Quick Add or open a metric and tap Update to enter a new value with date and time."
                            ),
                            faqItem(
                                question: "How do I set goals?",
                                answer: "Open a metric, tap Goal, and set a target value and direction (increase or decrease)."
                            ),
                            faqItem(
                                question: "How is progress calculated?",
                                answer: "Progress starts at the value you had when the goal was created and moves toward the target. It reaches 100% when the goal is met."
                            )
                        ]
                    )

                    faqSection(
                        title: "Data and privacy",
                        items: [
                            faqItem(
                                question: "What happens to my data?",
                                answer: "Your data is stored on device and encrypted. MeasureMe works offline by default."
                            ),
                            faqItem(
                                question: "Do I have to connect HealthKit?",
                                answer: "No. HealthKit is optional. You can log everything manually."
                            ),
                            faqItem(
                                question: "Are health indicators a reliable source?",
                                answer: "Health indicators are informational and based on simple algorithms from reputable health and medical institutions. They are not a diagnosis and should be reviewed with a medical professional."
                            ),
                            faqItem(
                                question: "What is the privacy policy?",
                                answer: "Your data stays on device. If you choose to export or share, you control where it goes."
                            ),
                            faqItem(
                                question: "Is any data processed on the internet?",
                                answer: "No. Measurements and photos are not sent to external servers."
                            )
                        ]
                    )

                    faqSection(
                        title: "Usage",
                        items: [
                            faqItem(
                                question: "Can I export my data or photos?",
                                answer: "Yes. Use Export data in Settings. Photos can be saved from the photo detail view."
                            ),
                            faqItem(
                                question: "Do I need to measure every day?",
                                answer: "No. Regular, consistent check‑ins are more valuable than daily measurements."
                            ),
                            faqItem(
                                question: "Why do my measurements fluctuate?",
                                answer: "Day‑to‑day changes are normal and can be caused by hydration, salt intake, sleep, stress, and training."
                            ),
                            faqItem(
                                question: "Can I edit or delete a measurement?",
                                answer: "Yes. Open a metric, go to History, and tap an entry to edit or swipe to delete."
                            ),
                            faqItem(
                                question: "What units does the app support?",
                                answer: "Metric and Imperial. You can switch anytime in Settings → Units."
                            ),
                            faqItem(
                                question: "How do photos help?",
                                answer: "Photos show visual changes that the scale doesn’t capture, especially when body composition is changing."
                            ),
                            faqItem(
                                question: "What’s the difference between weight, body fat %, and lean body mass?",
                                answer: "Weight is total body mass. Body fat % estimates fat as a portion of total weight. Lean body mass is everything except fat."
                            ),
                            faqItem(
                                question: "Why do HealthKit values look different from manual entries?",
                                answer: "Different devices and methods can produce different values. Trends are more important than single readings."
                            ),
                            faqItem(
                                question: "What happens if I set the wrong goal?",
                                answer: "No problem—go to the metric and update or delete the goal at any time."
                            ),
                            faqItem(
                                question: "Can I use the app offline?",
                                answer: "Yes. The app works fully offline; HealthKit sync is optional."
                            ),
                            faqItem(
                                question: "Do you send notifications automatically?",
                                answer: "Only if you enable reminders in Settings → Notifications."
                            ),
                            faqItem(
                                question: "What if AI Insights are unavailable?",
                                answer: "AI Insights in MeasureMe use Apple Intelligence. You need a supported device and language, plus Apple Intelligence enabled in system settings."
                            ),
                            faqItem(
                                question: "Can I compare photos?",
                                answer: "Yes. Use Compare in the Photos tab and select two photos to view them side by side."
                            ),
                            faqItem(
                                question: "How do I choose which metrics to track?",
                                answer: "Go to Settings → Tracked Measurements and select the metrics you want to follow."
                            ),
                            faqItem(
                                question: "Can I disable animations or haptics?",
                                answer: "Yes. In Settings → Animations and haptics you can turn off animations and haptics."
                            )
                        ]
                    )

                    faqSection(
                        title: "Premium and subscriptions",
                        items: [
                            faqItem(
                                question: "What is Premium Edition?",
                                answer: "Premium unlocks AI Insights, Health Indicators, data export, and photo comparison. AI Insights in MeasureMe use Apple Intelligence, so Apple Intelligence must be available and enabled."
                            ),
                            faqItem(
                                question: "Is there a free trial?",
                                answer: "Yes. Premium includes a free trial period when available. You can cancel before it ends to avoid being charged."
                            ),
                            faqItem(
                                question: "How do I cancel or manage my subscription?",
                                answer: "Open Settings in iOS → your Apple ID → Subscriptions, and manage MeasureMe there."
                            ),
                            faqItem(
                                question: "How do I restore purchases?",
                                answer: "Go to Settings → Premium Edition and tap Restore purchases."
                            ),
                            faqItem(
                                question: "What happens if I cancel Premium?",
                                answer: "You keep all your data. Premium-only features become locked, but your measurements and photos remain safe on device."
                            )
                        ]
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private func faqSection(title: String, items: [FAQItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.string(title))
                .font(AppTypography.sectionTitle)
                .foregroundStyle(.white)

            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.string(item.question))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                    Text(AppLocalization.string(item.answer))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            }
        }
    }

    private func faqItem(question: String, answer: String) -> FAQItem {
        FAQItem(question: question, answer: answer)
    }
}

private struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

#Preview {
    FAQView()
}
