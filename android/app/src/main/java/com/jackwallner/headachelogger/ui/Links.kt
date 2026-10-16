package com.jackwallner.headachelogger.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import com.google.android.play.core.review.ReviewManagerFactory
import com.jackwallner.headachelogger.BuildConfig
import java.io.File

object Links {
    const val PACKAGE = "com.jackwallner.headachelogger"
    const val PRIVACY = "https://jackwallner.github.io/headaches/android-privacy.html"
    const val TERMS = "https://jackwallner.github.io/headaches/android-terms.html"
    const val SUPPORT = "https://jackwallner.github.io/headaches/support.html"
    const val SUPPORT_EMAIL = "jackwallner+ha@gmail.com"
    const val LISTING = "https://play.google.com/store/apps/details?id=$PACKAGE"
    const val WRITE_REVIEW = "market://details?id=$PACKAGE"
    const val HEALTH_CONNECT_PACKAGE = "com.google.android.apps.healthdata"

    fun manageSubscription(productId: String?): String =
        if (productId == null) "https://play.google.com/store/account/subscriptions"
        else "https://play.google.com/store/account/subscriptions?sku=$productId&package=$PACKAGE"
}

fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

fun Context.openUrl(url: String) {
    runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/** The Play listing's review page, from the Settings row (the in-app card is never tied to a button). */
fun Context.openWriteReview() {
    val opened = runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Links.WRITE_REVIEW)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }.isSuccess
    if (!opened) openUrl(Links.LISTING)
}

fun Context.openHealthConnectSettings() {
    val settings = Intent("android.health.connect.action.HEALTH_HOME_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    if (runCatching { startActivity(settings) }.isFailure) {
        openUrl("market://details?id=${Links.HEALTH_CONNECT_PACKAGE}&url=healthconnect%3A%2F%2Fonboarding")
    }
}

fun Context.openAppSettings() {
    val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { startActivity(intent) }
}

/** The Play in-app review card, never from a button and never after a question. */
fun Context.launchPlayReview() {
    val activity = findActivity() ?: return
    val manager = ReviewManagerFactory.create(activity)
    manager.requestReviewFlow().addOnCompleteListener { request ->
        if (request.isSuccessful) manager.launchReviewFlow(activity, request.result)
    }
}

/** A mail draft to support with app and device facts, never health data unless the user adds it. */
fun Context.composeMail(subject: String, body: String) {
    val uri = Uri.parse("mailto:${Links.SUPPORT_EMAIL}").buildUpon()
        .appendQueryParameter("subject", subject)
        .appendQueryParameter("body", body)
        .build()
    runCatching { startActivity(Intent(Intent.ACTION_SENDTO, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

val deviceLine: String get() = "Android ${Build.VERSION.RELEASE} on ${Build.MANUFACTURER} ${Build.MODEL}"
val appVersionLine: String get() = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

/** Shares a cache file (CSV or PDF) through the app's FileProvider. */
fun Context.shareFile(file: File, mime: String, title: String) {
    val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
    val send = Intent(Intent.ACTION_SEND)
        .setType(mime)
        .putExtra(Intent.EXTRA_STREAM, uri)
        .putExtra(Intent.EXTRA_SUBJECT, title)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    runCatching { startActivity(Intent.createChooser(send, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}
