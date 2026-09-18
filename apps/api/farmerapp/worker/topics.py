"""Pub/Sub topic names (SPEC 9.2). Each topic has a dead-letter topic in Terraform."""

from __future__ import annotations

from enum import StrEnum


class Topic(StrEnum):
    VISIT_CREATED = "visit.created"
    FARMER_REGISTERED = "farmer.registered"
    DIAGNOSIS_REQUESTED = "diagnosis.requested"
    PAYMENT_WEBHOOK = "payment.webhook"
    ORDER_CREATED = "order.created"
    LOCATION_BATCH = "location.batch"
    NOTIFY_SEND = "notify.send"
