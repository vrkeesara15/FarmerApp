"""ORM models. Import every model here so Alembic and ``Base.metadata`` see them."""

from farmerapp.db.models.tenant import Tenant

__all__ = ["Tenant"]
