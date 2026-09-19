"""ORM models. Import every model here so Alembic and ``Base.metadata`` see them.

Importing this package also installs the FA-006 audit listener (``farmerapp.db.audit``).
"""

import farmerapp.db.audit  # noqa: F401  (registers the session listener)
from farmerapp.advisory.models import CropPlotTask, CropTaskTemplate, OutbreakAlert
from farmerapp.api.idempotency import IdempotencyKey
from farmerapp.auth.models import Device, OtpChallenge, RefreshToken, User
from farmerapp.beat.models import BeatPlan
from farmerapp.campaigns.models import Campaign, CampaignRecipient
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import LabelClaim, PestOrDisease, PriceList, Product, Sku
from farmerapp.db.models.audit_log import AuditLog
from farmerapp.db.models.tenant import Tenant
from farmerapp.demo_plots.models import DemoObservation, DemoPlot
from farmerapp.diagnosis.models import (
    CorpusImage,
    CorpusProblem,
    CorpusVersion,
    Diagnosis,
    DiagnosisReview,
    DiagnosisThreshold,
    LlmCallLog,
)
from farmerapp.duty.models import TrackGap
from farmerapp.exports.models import ExportJob, ReportRun, ReportSchedule
from farmerapp.farmers.models import ConsentRecord, CropPlot, Farm, Farmer, FarmPhoto
from farmerapp.flags.models import Flag, FlagComment, FlagEvent, FlagSummary, RuleTenantOverride
from farmerapp.incentives.models import IncentivePayout, IncentiveRuleSet, SalesTarget
from farmerapp.invoices.models import Invoice, InvoiceCounter
from farmerapp.khata.models import CreditApprovalRequest, CreditLimit, KhataEntry
from farmerapp.location.models import DutySession, LocationDailyAgg, LocationPoint, PolicyAcceptance
from farmerapp.meetings.models import FarmerMeeting, MeetingAttendance
from farmerapp.mlops.models import CorpusEmbedding, EncoderActivation, EvaluationRun, ModelRelease
from farmerapp.notifications.feed import install_feed_listener
from farmerapp.notifications.models import Notification, PushToken
from farmerapp.orders.models import Order, OrderLine, OrderStatusEvent
from farmerapp.payments.models import DayClose, Payment, WebhookEvent
from farmerapp.pii.models import TenantDataKey
from farmerapp.privacy.models import DataRequest
from farmerapp.rules.models import CropCalendar
from farmerapp.stock.models import StockBatch, StockMovement, StockReservation
from farmerapp.stock.reorder import ReorderLevel
from farmerapp.sync.models import SyncChange, SyncOp
from farmerapp.tenants.models import Cluster, Store, Village
from farmerapp.travel.models import TravelClaim
from farmerapp.uploads.models import UploadChunk, UploadSession
from farmerapp.visits.models import OverrideRequest, Visit, VisitConfirmation, VisitPhoto

install_feed_listener()  # FA-007: notifications in the sync change feed (offline inbox)

__all__ = [
    "AuditLog",
    "BeatPlan",
    "Campaign",
    "CampaignRecipient",
    "Cluster",
    "ConsentRecord",
    "CorpusEmbedding",
    "CorpusImage",
    "CorpusProblem",
    "CorpusVersion",
    "CreditApprovalRequest",
    "CreditLimit",
    "Crop",
    "CropCalendar",
    "CropPlot",
    "CropPlotTask",
    "CropTaskTemplate",
    "DataRequest",
    "DayClose",
    "DemoObservation",
    "DemoPlot",
    "Device",
    "Diagnosis",
    "DiagnosisReview",
    "DiagnosisThreshold",
    "DutySession",
    "EncoderActivation",
    "EvaluationRun",
    "ExportJob",
    "Farm",
    "FarmPhoto",
    "Farmer",
    "FarmerMeeting",
    "Flag",
    "FlagComment",
    "FlagEvent",
    "FlagSummary",
    "IdempotencyKey",
    "IncentivePayout",
    "IncentiveRuleSet",
    "Invoice",
    "InvoiceCounter",
    "KhataEntry",
    "LabelClaim",
    "LlmCallLog",
    "LocationDailyAgg",
    "LocationPoint",
    "MeetingAttendance",
    "ModelRelease",
    "Notification",
    "Order",
    "OrderLine",
    "OrderStatusEvent",
    "OtpChallenge",
    "OutbreakAlert",
    "OverrideRequest",
    "Payment",
    "PestOrDisease",
    "PolicyAcceptance",
    "PriceList",
    "Product",
    "PushToken",
    "RefreshToken",
    "ReorderLevel",
    "ReportRun",
    "ReportSchedule",
    "RuleTenantOverride",
    "SalesTarget",
    "Sku",
    "StockBatch",
    "StockMovement",
    "StockReservation",
    "Store",
    "SyncChange",
    "SyncOp",
    "Tenant",
    "TenantDataKey",
    "TrackGap",
    "TravelClaim",
    "UploadChunk",
    "UploadSession",
    "User",
    "Village",
    "Visit",
    "VisitConfirmation",
    "VisitPhoto",
    "WebhookEvent",
]
