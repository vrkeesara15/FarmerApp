"""ORM models. Import every model here so Alembic and ``Base.metadata`` see them.

Importing this package also installs the FA-006 audit listener (``farmerapp.db.audit``).
"""

import farmerapp.db.audit  # noqa: F401  (registers the session listener)
from farmerapp.api.idempotency import IdempotencyKey
from farmerapp.auth.models import OtpChallenge, RefreshToken, User
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import LabelClaim, PestOrDisease, PriceList, Product, Sku
from farmerapp.db.models.audit_log import AuditLog
from farmerapp.db.models.tenant import Tenant
from farmerapp.farmers.models import ConsentRecord, CropPlot, Farm, Farmer, FarmPhoto
from farmerapp.khata.models import CreditLimit, KhataEntry
from farmerapp.location.models import DutySession, LocationDailyAgg, LocationPoint, PolicyAcceptance
from farmerapp.notifications.models import Notification
from farmerapp.orders.models import Order, OrderLine
from farmerapp.payments.models import DayClose, Payment, WebhookEvent
from farmerapp.stock.models import StockBatch, StockMovement
from farmerapp.sync.models import SyncChange, SyncOp
from farmerapp.tenants.models import Cluster, Store, Village
from farmerapp.uploads.models import UploadChunk, UploadSession
from farmerapp.visits.models import OverrideRequest, Visit, VisitConfirmation, VisitPhoto

__all__ = [
    "AuditLog",
    "Cluster",
    "ConsentRecord",
    "CreditLimit",
    "Crop",
    "CropPlot",
    "DayClose",
    "DutySession",
    "Farm",
    "FarmPhoto",
    "Farmer",
    "IdempotencyKey",
    "KhataEntry",
    "LabelClaim",
    "LocationDailyAgg",
    "LocationPoint",
    "Notification",
    "Order",
    "OrderLine",
    "OtpChallenge",
    "OverrideRequest",
    "Payment",
    "PestOrDisease",
    "PolicyAcceptance",
    "PriceList",
    "Product",
    "RefreshToken",
    "Sku",
    "StockBatch",
    "StockMovement",
    "Store",
    "SyncChange",
    "SyncOp",
    "Tenant",
    "UploadChunk",
    "UploadSession",
    "User",
    "Village",
    "Visit",
    "VisitConfirmation",
    "VisitPhoto",
    "WebhookEvent",
]
