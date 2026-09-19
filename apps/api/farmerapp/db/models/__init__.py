"""ORM models. Import every model here so Alembic and ``Base.metadata`` see them.

Importing this package also installs the FA-006 audit listener (``farmerapp.db.audit``).
"""

import farmerapp.db.audit  # noqa: F401  (registers the session listener)
from farmerapp.api.idempotency import IdempotencyKey
from farmerapp.auth.models import Device, OtpChallenge, RefreshToken, User
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import LabelClaim, PestOrDisease, PriceList, Product, Sku
from farmerapp.db.models.audit_log import AuditLog
from farmerapp.db.models.tenant import Tenant
from farmerapp.diagnosis.models import (
    CorpusImage,
    CorpusProblem,
    CorpusVersion,
    Diagnosis,
    DiagnosisReview,
    DiagnosisThreshold,
    LlmCallLog,
)
from farmerapp.farmers.models import ConsentRecord, CropPlot, Farm, Farmer, FarmPhoto
from farmerapp.flags.models import Flag, FlagComment, FlagEvent, FlagSummary, RuleTenantOverride
from farmerapp.invoices.models import Invoice, InvoiceCounter
from farmerapp.khata.models import CreditApprovalRequest, CreditLimit, KhataEntry
from farmerapp.location.models import DutySession, LocationDailyAgg, LocationPoint, PolicyAcceptance
from farmerapp.notifications.models import Notification
from farmerapp.orders.models import Order, OrderLine, OrderStatusEvent
from farmerapp.payments.models import DayClose, Payment, WebhookEvent
from farmerapp.pii.models import TenantDataKey
from farmerapp.privacy.models import DataRequest
from farmerapp.rules.models import CropCalendar
from farmerapp.stock.models import StockBatch, StockMovement, StockReservation
from farmerapp.sync.models import SyncChange, SyncOp
from farmerapp.tenants.models import Cluster, Store, Village
from farmerapp.uploads.models import UploadChunk, UploadSession
from farmerapp.visits.models import OverrideRequest, Visit, VisitConfirmation, VisitPhoto

__all__ = [
    "AuditLog",
    "Cluster",
    "ConsentRecord",
    "CorpusImage",
    "CorpusProblem",
    "CorpusVersion",
    "CreditApprovalRequest",
    "CreditLimit",
    "Crop",
    "CropCalendar",
    "CropPlot",
    "DataRequest",
    "DayClose",
    "Device",
    "Diagnosis",
    "DiagnosisReview",
    "DiagnosisThreshold",
    "DutySession",
    "Farm",
    "FarmPhoto",
    "Farmer",
    "Flag",
    "FlagComment",
    "FlagEvent",
    "FlagSummary",
    "IdempotencyKey",
    "Invoice",
    "InvoiceCounter",
    "KhataEntry",
    "LabelClaim",
    "LlmCallLog",
    "LocationDailyAgg",
    "LocationPoint",
    "Notification",
    "Order",
    "OrderLine",
    "OrderStatusEvent",
    "OtpChallenge",
    "OverrideRequest",
    "Payment",
    "PestOrDisease",
    "PolicyAcceptance",
    "PriceList",
    "Product",
    "RefreshToken",
    "RuleTenantOverride",
    "Sku",
    "StockBatch",
    "StockMovement",
    "StockReservation",
    "Store",
    "SyncChange",
    "SyncOp",
    "Tenant",
    "TenantDataKey",
    "UploadChunk",
    "UploadSession",
    "User",
    "Village",
    "Visit",
    "VisitConfirmation",
    "VisitPhoto",
    "WebhookEvent",
]
