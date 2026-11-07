import SwiftUI

struct HeadacheQuizRetakeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var answers: [String: String] = HeadacheQuizStore.answers.reduce(into: [:]) {
        $0[$1.questionID] = $1.answer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if currentStep < HeadacheQuizQuestions.all.count {
                questionStep
            } else {
                completionStep
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pattern Quiz")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var questionStep: some View {
        let q = HeadacheQuizQuestions.all[currentStep]
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Step \(currentStep + 1) of \(HeadacheQuizQuestions.all.count)")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                ProgressView(value: Double(currentStep + 1), total: Double(HeadacheQuizQuestions.all.count))
                    .tint(AppTheme.brandText)
            }

            VStack(alignment: .leading, spacing: 20) {
                Text(q.question)
                    .font(.title3.bold())

                ForEach(q.options, id: \.self) { option in
                    Button {
                        answers[q.id] = option
                        HeadacheQuizStore.saveAnswer(questionID: q.id, answer: option)
                    } label: {
                        HStack {
                            Text(option)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            if answers[q.id] == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.brandText)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(answers[q.id] == option
                                    ? AppTheme.brandText.opacity(0.08)
                                    : Color(.secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button(currentStep < HeadacheQuizQuestions.all.count - 1 ? "Next" : "Done") {
                if currentStep < HeadacheQuizQuestions.all.count - 1 {
                    currentStep += 1
                } else {
                    HeadacheQuizStore.hasCompletedQuiz = true
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.brand)
            .frame(maxWidth: .infinity)
        }
    }

    private var completionStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(AppTheme.brandText)
            Text("Answers Updated")
                .font(.title2.bold())
            Text("Thanks! Your answers help us improve future versions of Patterns.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.brand)
            .frame(maxWidth: .infinity)
        }
    }
}
