"""ORM models. Import every model here so Alembic and ``Base.metadata`` see them.

Importing this package also installs the FA-006 audit listener (``farmerapp.db.audit``).
"""

import farmerapp.db.audit  # noqa: F401  (registers the session listener)
from farmerapp.auth.models import OtpChallenge, RefreshToken, User
from farmerapp.catalog.crops import Crop
from farmerapp.db.models.audit_log import AuditLog
from farmerapp.db.models.tenant import Tenant
from farmerapp.farmers.models import ConsentRecord, CropPlot, Farm, Farmer
from farmerapp.tenants.models import Cluster, Store, Village

__all__ = [
    "AuditLog",
    "Cluster",
    "ConsentRecord",
    "Crop",
    "CropPlot",
    "Farm",
    "Farmer",
    "OtpChallenge",
    "RefreshToken",
    "Store",
    "Tenant",
    "User",
    "Village",
]
