"""FM-012 fixtures: the farmer login of the M7 advisory suite (a farmer with a crop plot)."""

from __future__ import annotations

from tests.advisory.conftest import FarmerLogin, login  # noqa: F401
from tests.authz.conftest import Bearer, World, bearer, step_up  # noqa: F401
from tests.authz.conftest import world as world  # fixture re-exported
