package com.jackwallner.headachelogger.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject

/** Port of `HeadacheQuizStore`: answers as a JSON list of {questionID, answer}, same keys as iOS. */
class QuizStore(private val defaults: KeyValueStore) {
    var answers: List<Pair<String, String>> by mutableStateOf(load())
        private set

    var hasCompletedQuiz: Boolean by mutableStateOf(defaults.getBoolean(COMPLETED_KEY))
        private set

    fun setCompleted(value: Boolean) {
        hasCompletedQuiz = value
        defaults.putBoolean(COMPLETED_KEY, value)
    }

    fun saveAnswer(questionId: String, answer: String) {
        answers = answers.filterNot { it.first == questionId } + (questionId to answer)
        val array = JSONArray()
        answers.forEach { (q, a) -> array.put(JSONObject().put("questionID", q).put("answer", a)) }
        defaults.putString(STORAGE_KEY, array.toString())
    }

    fun answer(questionId: String): String? = answers.firstOrNull { it.first == questionId }?.second

    private fun load(): List<Pair<String, String>> {
        val text = defaults.getString(STORAGE_KEY) ?: return emptyList()
        val array = runCatching { JSONArray(text) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull { i ->
            val o = array.optJSONObject(i) ?: return@mapNotNull null
            o.optString("questionID").takeIf { it.isNotEmpty() }?.let { it to o.optString("answer") }
        }
    }

    private companion object {
        const val STORAGE_KEY = "headacheQuizAnswers"
        const val COMPLETED_KEY = "headacheQuizCompleted"
    }
}
