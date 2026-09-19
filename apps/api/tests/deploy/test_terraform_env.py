"""Drift check between Terraform (infra/envs/*/main.tf) and ``farmerapp.settings``.

The Cloud Run services and jobs must receive exactly the names ``Settings`` reads, with a
value for every setting the prd guard rails insist on, and nothing dev-only. Before this check
Terraform passed ``DB_HOST`` / ``ENV`` while the app read ``DATABASE_URL`` / ``APP_ENV``
(docs/prs/M6-followups.md). The table for humans is docs/deploy/configuration.md.
"""

from __future__ import annotations

import re
from collections.abc import Callable

import pytest

from farmerapp.settings import (
    CLOUD_FORBIDDEN_ENV,
    CLOUD_FORBIDDEN_ENV_STG_PRD,
    CLOUD_REQUIRED_ENV,
    CLOUD_REQUIRED_JOB_ENV,
    Settings,
)
from scripts import terraform_env
from scripts.terraform_env import INFRA, PROCESSES

ENVS = ("dev", "stg", "prd")
#: Read by a library rather than by Settings.
NON_SETTINGS_ENV = {"ANTHROPIC_API_KEY"}
SETTINGS_ENV = {name.upper() for name in Settings.model_fields}


def _names(expr: str) -> set[str]:
    return set(re.findall(r'"([A-Z][A-Z0-9_]+)"', expr))


def test_the_three_envs_share_main_tf() -> None:
    texts = {env: (INFRA / "envs" / env / "main.tf").read_text() for env in ENVS}
    assert texts["dev"] == texts["stg"] == texts["prd"]


def test_terraform_required_names_mirror_settings() -> None:
    config = terraform_env.load("prd")
    for process in PROCESSES:
        assert config.required_env(process) == set(CLOUD_REQUIRED_ENV[process]), process
    assert {job: set(names) for job, names in config.locals["job_required_env"].items()} == {
        job: set(names) for job, names in CLOUD_REQUIRED_JOB_ENV.items()
    }
    forbidden = config.locals["forbidden_env"]
    assert _names(forbidden) == set(CLOUD_FORBIDDEN_ENV_STG_PRD)
    # OTP_DEV_CODE is forbidden everywhere but dev.
    assert 'var.env == "dev" ? [] : ["OTP_DEV_CODE"]' in forbidden
    assert {"OTP_DEV_CODE"} == CLOUD_FORBIDDEN_ENV_STG_PRD - CLOUD_FORBIDDEN_ENV


@pytest.mark.parametrize("process", PROCESSES)
def test_every_required_setting_is_provided(process: str) -> None:
    config = terraform_env.load("prd")
    plain, secret = config.plain_env(process), config.secret_env(process)
    assert not set(plain) & set(secret), "a name is both plain env and a secret"
    provided = set(plain) | set(secret)
    assert CLOUD_REQUIRED_ENV[process] <= provided, CLOUD_REQUIRED_ENV[process] - provided
    assert not provided & CLOUD_FORBIDDEN_ENV_STG_PRD


def test_every_job_gets_the_jobs_settings_plus_its_own() -> None:
    config = terraform_env.load("prd")
    for job in config.job_names():
        provided = set(config.plain_env("jobs")) | set(config.secret_env("jobs", job))
        required = CLOUD_REQUIRED_ENV["jobs"] | CLOUD_REQUIRED_JOB_ENV.get(job, frozenset())
        assert required <= provided, (job, required - provided)
    assert set(CLOUD_REQUIRED_JOB_ENV) <= set(config.job_names())


def test_terraform_sets_only_names_the_app_reads() -> None:
    """No more DB_HOST / ENV / PUBLIC_URL: every deployed name is a Settings field."""
    config = terraform_env.load("prd")
    for process in PROCESSES:
        names = set(config.plain_env(process)) | set(config.secret_env(process))
        for job in config.locals["job_secret_env"]:
            names |= set(config.secret_env("jobs", job))
        assert names <= SETTINGS_ENV | NON_SETTINGS_ENV, names - SETTINGS_ENV - NON_SETTINGS_ENV
    for required in CLOUD_REQUIRED_ENV.values():
        assert required <= SETTINGS_ENV | NON_SETTINGS_ENV


def test_modules_are_wired_to_the_maps() -> None:
    """Each Cloud Run module receives its process's maps, contract and identity."""
    modules = terraform_env.load("prd").modules
    for module, process in (("api", "api"), ("worker", "worker"), ("migrate", "migrate")):
        block = modules[module]
        assert block["env"] == f"${{local.service_env.{process}}}"
        assert f"local.secret_env.{process}" in block["secret_env"]
        assert block["required_env"] == f"${{local.required_env.{process}}}"
        assert block["forbidden_env"] == "${local.forbidden_env}"
        assert block["service_account_email"] == f"${{module.iam.emails.{process}}}"
    job = modules["job"]
    assert job["env"] == "${local.service_env.jobs}"
    assert "local.secret_env.jobs" in job["secret_env"]
    assert "local.job_secret_env" in job["secret_env"]
    assert "local.required_env.jobs" in job["required_env"]
    assert "local.job_required_env" in job["required_env"]
    assert job["service_account_email"] == "${module.iam.emails.jobs}"


@pytest.fixture
def deployed(monkeypatch: pytest.MonkeyPatch) -> Callable[[dict[str, str]], Settings]:
    """Settings built from a process environment holding exactly ``values`` (as Cloud Run
    passes them: strings, JSON lists decoded by pydantic-settings), no .env file."""

    def build(values: dict[str, str]) -> Settings:
        for name in SETTINGS_ENV | NON_SETTINGS_ENV:
            monkeypatch.delenv(name, raising=False)
        for name, value in values.items():
            monkeypatch.setenv(name, value)
        return Settings(_env_file=None)

    return build


@pytest.mark.parametrize("env", ENVS)
@pytest.mark.parametrize("process", PROCESSES)
def test_deployed_env_passes_the_prd_guard_rails(
    deployed: Callable[[dict[str, str]], Settings], env: str, process: str
) -> None:
    """The env Terraform renders (fake secrets) builds Settings in prd mode for every process,
    so a Cloud Run revision does not crash-loop on a missing or dev-default setting."""
    values = terraform_env.render(env, process)
    values["APP_ENV"] = "prd"  # the same maps are deployed to dev and stg: hold them to prd
    settings = deployed(values)
    assert settings.db_iam_auth and settings.db_user and settings.db_instance_connection_name
    assert settings.otel_exporter == "gcp"
    assert settings.service_name == process
    if process != "migrate":
        assert settings.blob_store == "gcs" and settings.pii_kek_backend == "kms"


def test_every_job_env_passes_the_prd_guard_rails(
    deployed: Callable[[dict[str, str]], Settings],
) -> None:
    for job in terraform_env.load("prd").job_names():
        assert deployed(terraform_env.render("prd", "jobs", job)).service_name == "jobs"


@pytest.mark.parametrize(
    ("process", "drop", "message"),
    [
        ("api", "JWT_SIGNING_KEY", "JWT_SIGNING_KEY"),
        ("api", "OTP_PEPPER", "OTP_PEPPER"),
        ("api", "PII_KMS_KEY_NAME", "PII_KEK_BACKEND=kms"),
        ("worker", "PII_HASH_PEPPER", "PII_HASH_PEPPER"),
        ("worker", "RAZORPAY_WEBHOOK_SECRET", "RAZORPAY_WEBHOOK_SECRET"),
        ("jobs", "BLOB_STORE", "BLOB_STORE=gcs"),
        ("migrate", "DB_USER", "DB_IAM_AUTH=true needs"),
    ],
)
def test_a_missing_setting_stops_the_process(
    deployed: Callable[[dict[str, str]], Settings], process: str, drop: str, message: str
) -> None:
    values = terraform_env.render("prd", process)
    del values[drop]
    with pytest.raises(ValueError, match=re.escape(message)):
        deployed(values)


def test_migrate_and_runtime_identities_cannot_be_swapped(
    deployed: Callable[[dict[str, str]], Settings],
) -> None:
    """SEC-011 with IAM auth: only the migrate job logs in as the migrate service account."""
    migrate = terraform_env.render("prd", "migrate")
    api = terraform_env.render("prd", "api")
    with pytest.raises(ValueError, match="reserved for the migrate job"):
        deployed({**api, "DB_USER": migrate["DB_USER"]})
    with pytest.raises(ValueError, match="the migrate job must log in as"):
        deployed({**migrate, "DB_USER": api["DB_USER"]})


def test_every_embed_caller_may_invoke_embed() -> None:
    """The embed service is internal with invoker IAM: each process that gets
    DIAGNOSIS_EMBED_URL (api, worker, jobs) must hold roles/run.invoker on it, and in deployed
    environments uses the remote encoder (fake only locally)."""
    config = terraform_env.load("prd")
    callers = {
        process
        for process in PROCESSES
        if "DIAGNOSIS_EMBED_URL" in config.plain_env(process)
        and config.plain_env(process)["DIAGNOSIS_ENCODER"] == "remote"
    }
    assert callers == {"api", "worker", "jobs"}
    invokers = set(
        re.findall(r"module\.iam\.emails\.(\w+)", str(config.modules["embed"]["invoker_members"]))
    )
    assert invokers == callers
    assert "EMBED_URL" not in {n for p in PROCESSES for n in config.plain_env(p)}


def test_every_setting_is_documented() -> None:
    """docs/deploy/configuration.md has a row for every setting the app reads."""
    doc = (INFRA.parent / "docs" / "deploy" / "configuration.md").read_text()
    documented = set(re.findall(r"`([A-Z][A-Z0-9_]+)`", doc))
    missing = (SETTINGS_ENV | NON_SETTINGS_ENV) - documented
    assert not missing, f"add to docs/deploy/configuration.md: {sorted(missing)}"


def test_deploy_workflow_updates_every_job_image() -> None:
    """deploy.yml rolls the jobs image to every Cloud Run job Terraform creates."""
    workflow = (INFRA.parent / ".github" / "workflows" / "deploy.yml").read_text()
    loop = re.search(r"for job in (.*?); do", workflow, re.S)
    assert loop is not None
    listed = set(loop.group(1).replace("\\", " ").split())
    assert listed == set(terraform_env.load("prd").job_names())


def test_render_cli(capsys: pytest.CaptureFixture[str]) -> None:
    assert terraform_env.main(["prd", "migrate"]) == 0
    out = capsys.readouterr().out
    assert "DB_USER=farmerapp-migrate@farmerapp-prd.iam\n" in out
    assert "SERVICE_NAME=migrate\n" in out
    assert terraform_env.main(["prd"]) == 2


#: modules/db_budget defaults as wired in main.tf (headroom_percent, reserve).
BUDGET_HEADROOM_PERCENT, BUDGET_RESERVE = 80, 20


def _budget(env: str) -> tuple[dict[str, int], int, int]:
    """Worst-case connections per process, total (with the reserve) and the ceiling, from the
    env's tfvars, as module.db_budget computes them."""
    pools = terraform_env.env_value(env, "db_pool")
    max_instances = terraform_env.env_value(env, "max_instances")
    instances = {
        "api": max_instances["api"],
        "worker": max_instances["worker"],
        "jobs": len(terraform_env.load(env).job_names()),
    }
    per_process = {
        name: count * (pools[name]["pool_size"] + pools[name]["max_overflow"])
        for name, count in instances.items()
    }
    max_connections = terraform_env.env_value(env, "sql_max_connections")
    ceiling = max_connections * BUDGET_HEADROOM_PERCENT // 100
    return per_process, sum(per_process.values()) + BUDGET_RESERVE, ceiling


def test_db_budget_module_is_wired_to_the_sql_flag_and_every_pooled_process() -> None:
    config = terraform_env.load("prd")
    budget = config.modules["db_budget"]
    assert budget["max_connections"] == "${module.sql.max_connections}"
    assert budget["headroom_percent"] == BUDGET_HEADROOM_PERCENT
    assert budget["reserve"] == BUDGET_RESERVE
    assert config.modules["sql"]["max_connections"] == "${var.sql_max_connections}"
    assert "length(local.jobs)" in str(budget["processes"])
    for process in ("api", "worker", "jobs"):
        env = config.plain_env(process)
        assert env["DB_POOL_SIZE"] == f"${{module.db_budget.env.{process}.DB_POOL_SIZE}}"
        assert env["DB_MAX_OVERFLOW"] == f"${{module.db_budget.env.{process}.DB_MAX_OVERFLOW}}"
    assert "DB_POOL_SIZE" not in config.plain_env("migrate")  # Alembic uses NullPool


@pytest.mark.parametrize("env", ENVS)
def test_db_connection_budget_fits_and_is_documented(env: str) -> None:
    """Mirror of the module.db_budget precondition (proved by `terraform test` in
    infra/modules/db_budget) on each env's real values, and the numbers in the docs table."""
    per_process, total, ceiling = _budget(env)
    assert total <= ceiling, (env, per_process, total, ceiling)
    rendered = terraform_env.render(env, "api")
    pools = terraform_env.env_value(env, "db_pool")
    assert rendered["DB_POOL_SIZE"] == str(pools["api"]["pool_size"])
    doc = (INFRA.parent / "docs" / "deploy" / "configuration.md").read_text()
    row = re.search(rf"^\| {env} \|.*$", doc, re.M)
    assert row is not None, f"no connection budget row for {env}"
    cells = [c.strip() for c in row.group(0).strip("|").split("|")]
    assert cells[-2:] == [str(total), str(ceiling)], (env, cells, total, ceiling)
