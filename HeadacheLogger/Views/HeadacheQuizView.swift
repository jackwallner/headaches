import SwiftUI

struct HeadacheQuizView: View {
    @Binding var hasCompleted: Bool
    @State private var currentStep = 0
    @State private var answers: [String: String] = [:]
    @State private var isSkipping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isSkipping {
                skipConfirmation
            } else if currentStep < HeadacheQuizQuestions.all.count {
                questionStep
            } else {
                completionStep
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Question Step

    private var questionStep: some View {
        let q = HeadacheQuizQuestions.all[currentStep]
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Step \(currentStep + 1) of \(HeadacheQuizQuestions.all.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(currentStep + 1), total: Double(HeadacheQuizQuestions.all.count))
                    .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
            }

            VStack(alignment: .leading, spacing: 20) {
                Text(q.question)
                    .font(.title3.bold())

                ForEach(q.options, id: \.self) { option in
                    Button {
                        selectAnswer(for: q.id, answer: option)
                    } label: {
                        HStack {
                            Text(option)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            if answers[q.id] == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(answers[q.id] == option
                                    ? Color(red: 0.95, green: 0.25, blue: 0.36).opacity(0.08)
                                    : Color(.secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                if currentStep < HeadacheQuizQuestions.all.count - 1 {
                    Button("Next") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                    .frame(maxWidth: .infinity)
                } else {
                    Button("Finish") {
                        saveAndComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                    .frame(maxWidth: .infinity)
                }

                Button("Skip All Questions") {
                    isSkipping = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Skip Confirmation

    private var skipConfirmation: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Skip the Quiz?")
                    .font(.title2.bold())

                Text("Answering these HeadacheQuizQuestions.all helps us highlight the patterns most relevant to your headaches. You can always come back later from Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Go Back to Questions") {
                    isSkipping = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(maxWidth: .infinity)

                Button("Skip for Now") {
                    completeQuiz()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Completion

    private var completionStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))

                Text("That's All — Thank You!")
                    .font(.title2.bold())

                Text("Your answers will help us highlight the headache patterns most relevant to you. You can update them anytime in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("Continue") {
                completeQuiz()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func selectAnswer(for questionID: String, answer: String) {
        answers[questionID] = answer
        HeadacheQuizStore.saveAnswer(questionID: questionID, answer: answer)
    }

    private func saveAndComplete() {
        completeQuiz()
    }

    private func completeQuiz() {
        HeadacheQuizStore.hasCompletedQuiz = true
        hasCompleted = true
    }
}
