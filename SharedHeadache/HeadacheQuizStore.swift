import Foundation

struct HeadacheQuizAnswer: Codable, Sendable {
    let questionID: String
    let answer: String
}

enum HeadacheQuizStore {
    private static let storageKey = "headacheQuizAnswers"
    private static let completedKey = "headacheQuizCompleted"

    static var answers: [HeadacheQuizAnswer] {
        get {
            guard let data = HeadacheAppGroup.userDefaults.data(forKey: storageKey) else { return [] }
            return (try? JSONDecoder().decode([HeadacheQuizAnswer].self, from: data)) ?? []
        }
        set {
            HeadacheAppGroup.userDefaults.set(try? JSONEncoder().encode(newValue), forKey: storageKey)
        }
    }

    static var hasCompletedQuiz: Bool {
        get { HeadacheAppGroup.userDefaults.bool(forKey: completedKey) }
        set { HeadacheAppGroup.userDefaults.set(newValue, forKey: completedKey) }
    }

    static func saveAnswer(questionID: String, answer: String) {
        var current = answers
        current.removeAll { $0.questionID == questionID }
        current.append(HeadacheQuizAnswer(questionID: questionID, answer: answer))
        answers = current
    }

    static func answer(for questionID: String) -> String? {
        answers.first { $0.questionID == questionID }?.answer
    }

    /// Which insight categories the user should see prioritized based on their answers.
    static var prioritizedInsightKinds: [HeadacheInsightKind] {
        var kinds: [HeadacheInsightKind] = []

        if answer(for: "trigger_sleep") == "Yes" {
            kinds.append(.sleep)
        }
        if let weatherAnswer = answer(for: "trigger_weather"),
           weatherAnswer == "Pressure drops" || weatherAnswer == "Heat" {
            kinds.append(.pressure)
            if weatherAnswer == "Heat" { kinds.append(.temperature) }
        }
        if let timeAnswer = answer(for: "time_of_day"),
           timeAnswer != "No pattern" && timeAnswer != "N/A" {
            kinds.append(.timeOfDay)
        }
        if answer(for: "trigger_food") == "Yes" {
            kinds.append(.hrv)
        }
        if let severityAnswer = answer(for: "severity"),
           severityAnswer == "Extreme" || severityAnswer == "Medium" {
            kinds.append(.severity)
        }

        if kinds.isEmpty {
            kinds = [.timeOfDay, .pressure, .sleep]
        }
        return Array(Set(kinds))
    }
}

enum HeadacheInsightKind: String, Codable, Sendable, CaseIterable {
    case timeOfDay
    case sleep
    case pressure
    case temperature
    case humidity
    case hrv
    case severity
    case aqi
}

struct HeadacheQuizQuestion: Codable, Sendable {
    let id: String
    let question: String
    let options: [String]
}

enum HeadacheQuizQuestions {
    static let all: [HeadacheQuizQuestion] = [
        HeadacheQuizQuestion(
            id: "time_of_day",
            question: "What time of day do you most often get headaches?",
            options: ["Morning", "Afternoon", "Evening", "Overnight", "No pattern", "N/A"]
        ),
        HeadacheQuizQuestion(
            id: "trigger_sleep",
            question: "Do you notice headaches after poor or too little sleep?",
            options: ["Yes", "No", "Not sure", "N/A"]
        ),
        HeadacheQuizQuestion(
            id: "trigger_weather",
            question: "Have you noticed weather changes triggering your headaches?",
            options: ["Pressure drops", "Heat", "Cold", "No", "Not sure", "N/A"]
        ),
        HeadacheQuizQuestion(
            id: "trigger_food",
            question: "Do certain foods or drinks seem to trigger your headaches?",
            options: ["Yes", "No", "Not sure", "N/A"]
        ),
        HeadacheQuizQuestion(
            id: "side",
            question: "Are your headaches typically on one side of your head?",
            options: ["Yes, usually right", "Yes, usually left", "No, both sides", "It varies", "N/A"]
        ),
        HeadacheQuizQuestion(
            id: "severity",
            question: "How severe are your headaches on a typical day?",
            options: ["Slight — can ignore it", "Medium — noticeable but functional", "Extreme — hard to function", "It varies a lot", "N/A"]
        ),
    ]
}
