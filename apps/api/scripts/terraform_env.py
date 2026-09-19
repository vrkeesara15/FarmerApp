"""Read the app environment Terraform deploys (infra/envs/<env>/main.tf) without GCP.

``infra/envs/*/main.tf`` declares each process's settings as literal maps (``local.env_parts``
merged per ``local.env_layers``, plus ``local.secret_env`` / ``local.job_secret_env``), so they
can be read statically with python-hcl2. Used by ``tests/deploy/test_terraform_env.py`` (the
drift check against ``farmerapp.settings``) and to assemble a prd-like container environment:

    uv run python -m scripts.terraform_env prd api > /tmp/api.env

prints ``NAME=value`` lines for one process: plain values Terraform takes from variables or
other modules are filled with representative stand-ins, secrets with fake strong values.
Never real secrets.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from functools import cache
from pathlib import Path
from typing import Any

import hcl2

INFRA = Path(__file__).resolve().parents[3] / "infra"
PROCESSES = ("api", "worker", "jobs", "migrate")


def _unquote(value: Any) -> Any:
    if isinstance(value, str) and len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1]
    return value


def _clean(node: Any) -> Any:
    if isinstance(node, dict):
        return {_unquote(k): _clean(v) for k, v in node.items() if k != "__is_block__"}
    if isinstance(node, list):
        return [_clean(v) for v in node]
    return _unquote(node)


@dataclass(frozen=True)
class EnvConfig:
    """The app-settings locals and module blocks of one environment's main.tf."""

    locals: dict[str, Any]
    modules: dict[str, dict[str, Any]]

    def plain_env(self, process: str) -> dict[str, str]:
        merged: dict[str, str] = {}
        for layer in self.locals["env_layers"][process]:
            merged.update(self.locals["env_parts"][layer])
        return merged

    def secret_env(self, process: str, job: str | None = None) -> dict[str, str]:
        mounts = dict(self.locals["secret_env"][process])
        if job is not None:
            mounts.update(self.locals["job_secret_env"].get(job, {}))
        return mounts

    def required_env(self, process: str, job: str | None = None) -> set[str]:
        names = set(self.locals["required_env"][process])
        if job is not None:
            names |= set(self.locals["job_required_env"].get(job, []))
        return names

    def job_names(self) -> list[str]:
        return list(self.locals["jobs"])


@cache
def load(env: str) -> EnvConfig:
    with (INFRA / "envs" / env / "main.tf").open() as f:
        doc = _clean(hcl2.load(f))
    merged_locals: dict[str, Any] = {}
    for block in doc.get("locals", []):
        merged_locals.update(block)
    modules: dict[str, dict[str, Any]] = {}
    for block in doc.get("module", []):
        modules.update(block)
    return EnvConfig(locals=merged_locals, modules=modules)


# Stand-ins for values Terraform resolves from variables / other modules at plan time.
_STAND_INS: dict[str, str] = {
    "var.env": "prd",
    "var.project_id": "farmerapp-prd",
    "var.log_level": "INFO",
    "var.razorpay_base_url": "https://api.razorpay.com",
    "var.diagnosis_encoder_name": "siglip-base-patch16-224",
    "var.diagnosis_encoder_version": "2024-01",
    "var.diagnosis_llm": "claude",
    "var.diagnosis_llm_model": "claude-opus-5",
    "module.sql.connection_name": "farmerapp-prd:asia-south1:farmerapp-prd",
    "module.sql.database_name": "farmerapp",
    "module.storage.bucket_names.photos": "farmerapp-prd-photos",
    "module.storage.bucket_names.exports": "farmerapp-prd-exports",
    "module.kms.pii_key_name": (
        "projects/farmerapp-prd/locations/asia-south1/keyRings/farmerapp-prd/cryptoKeys/pii"
    ),
    "module.embed.uri": "https://embed-xyz-el.a.run.app",
    "module.iam.emails.api": "farmerapp-api@farmerapp-prd.iam.gserviceaccount.com",
}
_EXPR = re.compile(r"^\$\{(.*)\}$", re.S)
_FAKE_SECRETS: dict[str, str] = {
    "otp-sms-provider-url": "https://sms.example.invalid/send",
    "otp-whatsapp-provider-url": "https://whatsapp.example.invalid/send",
    "razorpay-key-id": "rzp_test_fake",
}


def resolve(value: str, process: str, env: str) -> str:
    """Best-effort rendering of one Terraform expression for a local container run."""
    match = _EXPR.match(value)
    if match is None:
        return value
    expr = match.group(1).strip()
    if expr.startswith("local.db_users."):
        return f"farmerapp-{expr.rsplit('.', 1)[1]}@farmerapp-{env}.iam"
    if expr.startswith("tostring(var.otel_sample_ratio"):
        return "1"
    if expr.startswith("jsonencode("):
        return f'["https://console.{env}.farmerapp.in"]'
    stand_in = _STAND_INS.get(expr)
    if stand_in is None:
        raise KeyError(f"no stand-in for {expr!r} ({process})")
    return stand_in.replace("prd", env) if env != "prd" else stand_in


def render(env: str, process: str, job: str | None = None) -> dict[str, str]:
    config = load(env)
    rendered = {
        name: resolve(value, process, env) for name, value in config.plain_env(process).items()
    }
    for name, secret_id in config.secret_env(process, job).items():
        rendered[name] = _FAKE_SECRETS.get(secret_id, f"fake-{secret_id}-" + "x" * 40)
    return rendered


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3) or argv[1] not in PROCESSES:
        sys.stderr.write(
            "usage: python -m scripts.terraform_env <dev|stg|prd> <api|worker|jobs|migrate> [job]\n"
        )
        return 2
    for name, value in sorted(render(*argv).items()):
        sys.stdout.write(f"{name}={value}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
