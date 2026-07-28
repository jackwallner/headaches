#!/usr/bin/env python3
"""Audit Headache Pro subscription prices and free-trial coverage."""
from __future__ import annotations

import base64
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from asc_lib import ASCClient, bearer_token, find_app, list_all, load_credentials

BUNDLE_ID = "com.jackwallner.headachelogger"
EXPECTED_PRODUCTS = {
    "monthly": ("com.jackwallner.headachelogger.pro.monthly", "4.99"),
    "yearly": ("com.jackwallner.headachelogger.pro.yearly", "29.99"),
}
US_TERRITORY = "USA"


def territory_from_id(encoded_id: str) -> str | None:
    padded = encoded_id + "=" * ((4 - len(encoded_id) % 4) % 4)
    try:
        payload = json.loads(base64.urlsafe_b64decode(padded))
    except (ValueError, json.JSONDecodeError):
        return None
    return payload.get("i") or payload.get("c")


def territory_ids(rows: list[dict]) -> set[str]:
    result = set()
    for row in rows:
        relationship = row.get("relationships", {}).get("territory", {}).get("data") or {}
        territory = relationship.get("id") or territory_from_id(row["id"])
        if territory:
            result.add(territory)
    return result


def us_price(client: ASCClient, subscription_id: str) -> str | None:
    prices = list_all(
        client,
        f"/subscriptions/{subscription_id}/prices?filter[territory]={US_TERRITORY}"
        "&include=subscriptionPricePoint&limit=200",
    )
    for price in prices:
        point = price.get("relationships", {}).get("subscriptionPricePoint", {}).get("data") or {}
        if point:
            detail = client.get(f"/subscriptionPricePoints/{point['id']}")
            return detail.get("data", {}).get("attributes", {}).get("customerPrice")
    return None


def main() -> None:
    client = ASCClient(bearer_token(*load_credentials()))
    app = find_app(client, BUNDLE_ID)
    territories = {item["id"] for item in list_all(client, "/territories?limit=200")}
    groups = list_all(client, f"/apps/{app['id']}/subscriptionGroups?limit=200")
    subscriptions = []
    for group in groups:
        subscriptions.extend(
            list_all(client, f"/subscriptionGroups/{group['id']}/subscriptions?limit=200")
        )
    by_product = {item["attributes"]["productId"]: item for item in subscriptions}

    failed = False
    for label, (product_id, expected_price) in EXPECTED_PRODUCTS.items():
        subscription = by_product.get(product_id)
        if subscription is None:
            print(f"{label}: MISSING {product_id}")
            failed = True
            continue

        subscription_id = subscription["id"]
        prices = list_all(
            client,
            f"/subscriptions/{subscription_id}/prices?include=territory&limit=200",
        )
        offers = list_all(
            client,
            f"/subscriptions/{subscription_id}/introductoryOffers?include=territory&limit=200",
        )
        priced = territory_ids(prices)
        trial = territory_ids(
            [
                offer
                for offer in offers
                if offer["attributes"].get("offerMode") == "FREE_TRIAL"
                and offer["attributes"].get("duration") == "ONE_WEEK"
                and offer["attributes"].get("numberOfPeriods") == 1
            ]
        )
        missing_prices = sorted(territories - priced)
        missing_trials = sorted(priced - trial)
        actual_price = us_price(client, subscription_id)
        state = subscription["attributes"].get("state", "UNKNOWN")
        print(
            f"{label}: state={state} us_price={actual_price or 'missing'} "
            f"expected={expected_price} priced={len(priced)}/{len(territories)} "
            f"one_week_trials={len(trial)}/{len(priced)} "
            f"missing_prices={','.join(missing_prices) or 'none'} "
            f"missing_trials={','.join(missing_trials) or 'none'}"
        )
        if (
            state != "APPROVED"
            or actual_price != expected_price
            or missing_prices
            or missing_trials
        ):
            failed = True

    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
