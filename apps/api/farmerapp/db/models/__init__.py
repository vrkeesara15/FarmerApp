"""ORM models. Import every model here so Alembic and ``Base.metadata`` see them.

Importing this package also installs the FA-006 audit listener (``farmerapp.db.audit``).
"""

import farmerapp.db.audit  # noqa: F401  (registers the session listener)
from farmerapp.auth.models import OtpChallenge, RefreshToken, User
from farmerapp.db.models.audit_log import AuditLog
from farmerapp.db.models.tenant import Tenant

__all__ = ["AuditLog", "OtpChallenge", "RefreshToken", "Tenant", "User"]
