"""Access tokens for the M7 field P1 tests (a plain helper, not a re-exported fixture).

Each test module declares its own ``bearer`` fixture from ``mint_bearer(app)``: re-exporting
the authz ``bearer`` fixture object from several modules is fragile across pytest-xdist
collection orders.
"""

from __future__ import annotations

from fastapi import FastAPI

from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import User
from tests.authz.conftest import Bearer


def mint_bearer(app: FastAPI) -> Bearer:
    services: AuthServices = app.state.auth

    def _mint(user: User) -> dict[str, str]:
        # The clock is read at mint time: tests that swap in a FakeClock get matching tokens.
        token = services.tokens.issue_access_token(user, app.state.auth.clock.now())
        return {"Authorization": f"Bearer {token}"}

    return _mint


__all__ = ["mint_bearer"]
