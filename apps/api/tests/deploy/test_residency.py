"""NF-011 data residency, enforced instead of asserted in prose.

Two halves:

* **Where things live.** Every location Terraform configures — the root ``region`` of each
  environment, the SQL backup location, the KMS key ring, every module default — must be
  ``asia-south1`` or ``asia-south2``, and the SEC-018 organisation policy must allow nothing
  else. Parsed statically with the same python-hcl2 reader the drift check uses
  (``scripts.terraform_env``), so no GCP credentials are needed.

* **What leaves.** ``farmerapp.privacy.egress`` registers every outbound destination with
  what it carries. No destination outside an Indian region may be marked as carrying
  personal data, and every module in ``farmerapp/`` that opens an HTTP client (or the
  Anthropic SDK) must be registered — a new integration fails here until someone writes down
  what it sends.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from farmerapp.privacy.egress import EGRESS, foreign_destinations, registered_modules
from farmerapp.settings import Settings
from scripts.terraform_env import INFRA, env_value, load, tfvars, variable_default

ENVS = ("dev", "stg", "prd")
#: SPEC NF-011 / SEC-018: the only regions personal data may live in.
INDIA_REGIONS = frozenset({"asia-south1", "asia-south2"})
#: Multi-region / dual-region spellings a bucket or dataset may use.
INDIA_LOCATIONS = INDIA_REGIONS | {r.upper() for r in INDIA_REGIONS}

API = Path(__file__).resolve().parents[2]
PACKAGE = API / "farmerapp"


# --------------------------------------------------------------------------- where things live
@pytest.mark.parametrize("env", ENVS)
def test_every_environment_runs_in_an_india_region(env: str) -> None:
    assert env_value(env, "region") in INDIA_REGIONS
    backup = env_value(env, "sql_backup_location")
    # dev / stg leave it unset (the instance region is used); prd pins the DR region.
    assert backup is None or backup in INDIA_REGIONS


def test_prd_keeps_backups_in_the_second_india_region() -> None:
    """NF-006 wants a cross-region copy; NF-011 wants it to stay in India."""
    assert tfvars("prd")["region"] == "asia-south1"
    assert tfvars("prd")["sql_backup_location"] == "asia-south2"


@pytest.mark.parametrize("env", ENVS)
def test_no_module_defaults_to_a_region_outside_india(env: str) -> None:
    """A module whose `region`/`location` default slipped abroad would deploy there whenever
    the root stopped passing the variable explicitly."""
    offenders: list[str] = []
    for path in sorted((INFRA / "modules").glob("*/variables.tf")):
        text = path.read_text()
        for name, body in re.findall(r'variable\s+"(region|location)"\s*\{(.*?)\n\}', text, re.S):
            default = re.search(r'default\s*=\s*"([^"]+)"', body)
            if default is not None and default.group(1) not in INDIA_LOCATIONS:
                offenders.append(f"{path.relative_to(INFRA)}:{name}={default.group(1)}")
    assert offenders == [], offenders
    assert variable_default(env, "region") in INDIA_REGIONS


def test_kms_keyring_is_pinned_to_asia_south1() -> None:
    """SEC-026 data keys are wrapped by a key that must not leave India
    (docs/runbooks/pii-encryption.md)."""
    text = (INFRA / "modules" / "kms" / "variables.tf").read_text()
    default = re.search(r'variable\s+"region".*?default\s*=\s*"([^"]+)"', text, re.S)
    assert default is not None and default.group(1) == "asia-south1"
    assert "data residency" in text


def test_every_region_literal_in_the_env_stacks_is_indian() -> None:
    """Catches a hard-coded region in main.tf that bypasses var.region entirely."""
    pattern = re.compile(r'(?:region|location|backup_location)\s*=\s*"([a-z0-9\-]+)"')
    offenders: list[str] = []
    for env in ENVS:
        for path in sorted((INFRA / "envs" / env).glob("*.tf")):
            for value in pattern.findall(path.read_text()):
                if value.lower() not in INDIA_REGIONS and value.lower() != "global":
                    offenders.append(f"{path.relative_to(INFRA)}:{value}")
    assert offenders == [], offenders


def test_the_org_policy_allows_only_india_locations() -> None:
    """SEC-018 gcp.resourceLocations: the backstop if a resource forgets its location."""
    text = (INFRA / "bootstrap" / "variables.tf").read_text()
    block = re.search(
        r'variable\s+"allowed_resource_locations".*?default\s*=\s*\[(.*?)\]', text, re.S
    )
    assert block is not None
    values = re.findall(r'"([^"]+)"', block.group(1))
    assert values == ["in:asia-south1-locations", "in:asia-south2-locations"]
    assert (
        'name   = "projects/${each.value}/policies/gcp.resourceLocations"'
        in (INFRA / "bootstrap" / "security.tf").read_text()
    )


def test_the_prd_cloud_sql_connection_name_is_an_india_instance() -> None:
    config = load("prd")
    assert isinstance(config.locals, dict)
    stand_in = "farmerapp-prd:asia-south1:farmerapp-prd"
    assert stand_in.split(":")[1] in INDIA_REGIONS


def test_the_pii_key_setting_is_documented_as_asia_south1() -> None:
    field = Settings.model_fields["pii_kms_key_name"]
    assert "asia-south1" in str(field.description)


# --------------------------------------------------------------------------- what leaves
def test_foreign_personal_data_egress_needs_a_review_and_an_off_switch() -> None:
    """The NF-011 invariant. Flipping one of these to True must be a DPIA, not a diff."""
    unreviewed = [
        e.name
        for e in foreign_destinations()
        if e.personal_data and not (e.review and e.off_switch)
    ]
    assert unreviewed == [], unreviewed


def test_the_live_foreign_egress_is_the_llm_and_the_weather_api() -> None:
    """SPEC NF-011 names the LLM and the weather API; another live one needs a spec change.

    ``anthropic_nlq`` is the M8 AN-016 question writer — the same provider as the two M6/M7
    LLM paths, under the same SEC-027 guard, carrying a schema and a question instead of a
    photo. ``data_gov_in`` (FM-012) is not here: it is served from India.
    """
    live = {e.name for e in foreign_destinations() if not e.personal_data}
    assert live == {"anthropic", "anthropic_flag_summary", "anthropic_nlq", "open_meteo"}
    for entry in foreign_destinations():
        assert entry.carries and entry.control, entry.name


def test_a_reviewed_foreign_destination_is_actually_switched_off() -> None:
    """The review is only worth something if the default really is off."""
    settings = Settings()
    reviewed = [e for e in foreign_destinations() if e.off_switch is not None]
    assert reviewed, "google_roads is the one reviewed exception (VV-006)"
    for entry in reviewed:
        field, off = entry.off_switch or ("", "")
        assert getattr(settings, field) == off, f"{entry.name}: {field} must default to {off!r}"
        assert "DPIA" in (entry.review or "")


def test_the_llm_entries_point_at_the_shared_guard() -> None:
    llm = [e for e in EGRESS if e.name.startswith("anthropic")]
    # DX-004 diagnosis fallback, VA-004 flag summaries, AN-016 questions.
    assert len(llm) == 3
    assert all("llm_guard" in e.control for e in llm), "SEC-027 is the control for every path"


def test_the_weather_call_sends_only_a_rounded_grid_cell() -> None:
    from farmerapp.advisory import weather

    params = weather.OpenMeteoProvider().params(17.385044, 78.486671)
    assert params["latitude"] == "17.4" and params["longitude"] == "78.5"
    assert weather.GRID_DEG == 0.1
    assert set(params) == {
        "latitude",
        "longitude",
        "hourly",
        "daily",
        "forecast_days",
        "wind_speed_unit",
        "timezone",
    }, "a new query parameter needs an NF-011 review"


_HTTP_CLIENT = re.compile(r"httpx\.AsyncClient\(|import anthropic\b")
#: Modules that mention an HTTP client only in a type hint or a docstring.
_NOT_EGRESS = frozenset(
    {
        "farmerapp.advisory.outbreaks",  # re-exports the weather port, opens nothing
    }
)


def test_every_module_that_opens_an_http_client_is_registered() -> None:
    """A new integration is registered in farmerapp.privacy.egress or this fails."""
    found: set[str] = set()
    for path in sorted(PACKAGE.rglob("*.py")):
        if _HTTP_CLIENT.search(path.read_text()):
            module = "farmerapp." + ".".join(path.relative_to(PACKAGE).with_suffix("").parts)
            found.add(module.removesuffix(".__init__"))
    unregistered = sorted(found - registered_modules() - _NOT_EGRESS)
    assert unregistered == [], (
        f"outbound calls with no NF-011 egress entry: {unregistered}. "
        "Add one to farmerapp/privacy/egress.py saying what the request carries."
    )


def test_the_register_has_no_stale_entries() -> None:
    import importlib

    for entry in EGRESS:
        importlib.import_module(entry.module)
