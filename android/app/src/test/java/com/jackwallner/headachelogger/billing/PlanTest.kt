package com.jackwallner.headachelogger.billing

import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Android catalog: about 20% under iOS ($9.99 / $39.99 / $89.99), one-week trials on both subscriptions. */
class PlanTest {
    init { Locale.setDefault(Locale.US) }

    private val monthly = Plan("\$rc_monthly", HeadacheProProduct.MONTHLY, PackageKind.MONTHLY, 7_990_000, "\$7.99", "USD", PlanPeriod(1, PeriodUnit.MONTH), PlanPeriod(7, PeriodUnit.DAY))
    private val yearly = Plan("\$rc_annual", HeadacheProProduct.YEARLY, PackageKind.YEARLY, 31_990_000, "\$31.99", "USD", PlanPeriod(1, PeriodUnit.YEAR), PlanPeriod(1, PeriodUnit.WEEK))
    private val lifetime = Plan("\$rc_lifetime", HeadacheProProduct.LIFETIME, PackageKind.LIFETIME, 71_990_000, "\$71.99", "USD", null, null)

    @Test fun productIdsMatchTheIosCatalog() {
        assertEquals("com.jackwallner.headachelogger", HeadacheProProduct.LIFETIME)
        assertEquals("com.jackwallner.headachelogger.pro.yearly", HeadacheProProduct.YEARLY)
        assertEquals("com.jackwallner.headachelogger.pro.monthly", HeadacheProProduct.MONTHLY)
    }

    @Test fun packageKindsComeFromTheIdentifiers() {
        assertEquals(PackageKind.YEARLY, PackageKind.fromIdentifiers("\$rc_annual", HeadacheProProduct.YEARLY))
        assertEquals(PackageKind.MONTHLY, PackageKind.fromIdentifiers("\$rc_monthly", HeadacheProProduct.MONTHLY))
        assertEquals(PackageKind.LIFETIME, PackageKind.fromIdentifiers("\$rc_lifetime", HeadacheProProduct.LIFETIME))
    }

    @Test fun priceLabelsReadLikeTheIosPaywall() {
        assertEquals("\$31.99 / year", yearly.priceLabel)
        assertEquals("\$7.99 / month", monthly.priceLabel)
        assertEquals("\$71.99", lifetime.priceLabel)
    }

    @Test fun trialLabelIsSevenDaysWhetherPlayReportsDaysOrAWeek() {
        assertEquals("7-day free trial", yearly.introOfferLabel)
        assertEquals("7-day free trial", monthly.introOfferLabel)
        assertEquals(7, monthly.trial?.days)
        assertNull(lifetime.introOfferLabel)
    }

    @Test fun yearlySavingsAndAnchorAreComputedAgainstTwelveMonthlies() {
        assertEquals(67, yearly.savingsPercent(monthly))
        assertEquals("\$95.88", yearly.anchorPriceLabel(monthly))
        assertEquals("\$2.67 / mo", yearly.perMonthLabel)
        assertNull(monthly.savingsPercent(monthly))
        assertNull(lifetime.savingsPercent(monthly))
    }
}
