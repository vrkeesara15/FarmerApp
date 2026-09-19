"""``EmailSender`` port (WC-013 scheduled reports, AN-015 weekly owner PDF, ST-008 accounting).

Adapters, chosen by ``EMAIL_PROVIDER``:

* ``LogEmailSender`` (``log``, the default) — writes one ``email_logged`` line (recipient
  count, subject, attachment names and sizes; never addresses or content) and sends nothing.
* ``FakeEmailSender`` (``fake``) — keeps the messages in memory (tests).
* ``SmtpEmailSender`` (``smtp``) — ``smtplib`` with STARTTLS in a worker thread.
* ``HttpEmailSender`` (``sendgrid``) — a SendGrid-style ``POST /v3/mail/send`` JSON API with a
  bearer key from Secret Manager (``EMAIL_API_KEY``).

A real provider account, the sending domain (SPF / DKIM) and the key are human work.
"""

from __future__ import annotations

import asyncio
import base64
import smtplib
from dataclasses import dataclass, field
from email.message import EmailMessage
from typing import Protocol

import httpx

from farmerapp.logging import get_logger
from farmerapp.settings import Settings

log = get_logger("farmerapp.exports.email")


class EmailError(RuntimeError):
    """The provider rejected or failed the send."""


@dataclass(frozen=True)
class Attachment:
    filename: str
    content: bytes
    content_type: str


@dataclass(frozen=True)
class Email:
    to: tuple[str, ...]
    subject: str
    text: str
    attachments: tuple[Attachment, ...] = ()


class EmailSender(Protocol):
    async def send(self, email: Email) -> None: ...


class LogEmailSender:
    async def send(self, email: Email) -> None:
        log.info(
            "email_logged",
            recipients=len(email.to),
            subject=email.subject,
            attachments=[(a.filename, len(a.content)) for a in email.attachments],
        )


@dataclass
class FakeEmailSender:
    sent: list[Email] = field(default_factory=list)
    fail: bool = False

    async def send(self, email: Email) -> None:
        if self.fail:
            raise EmailError("fake email provider failure")
        self.sent.append(email)


def _mime(sender: str, email: Email) -> EmailMessage:
    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = ", ".join(email.to)
    msg["Subject"] = email.subject
    msg.set_content(email.text)
    for a in email.attachments:
        maintype, _, subtype = a.content_type.partition("/")
        msg.add_attachment(
            a.content, maintype=maintype, subtype=subtype or "octet-stream", filename=a.filename
        )
    return msg


class SmtpEmailSender:  # pragma: no cover - needs an SMTP server
    def __init__(self, settings: Settings) -> None:
        self._s = settings

    def _send_sync(self, email: Email) -> None:
        s = self._s
        with smtplib.SMTP(s.email_smtp_host, s.email_smtp_port, timeout=s.email_timeout_s) as smtp:
            if s.email_smtp_starttls:
                smtp.starttls()
            if s.email_smtp_username and s.email_smtp_password:
                smtp.login(s.email_smtp_username, s.email_smtp_password)
            smtp.send_message(_mime(s.email_from, email))

    async def send(self, email: Email) -> None:
        try:
            await asyncio.to_thread(self._send_sync, email)
        except (OSError, smtplib.SMTPException) as exc:
            raise EmailError("smtp send failed") from exc


class HttpEmailSender:
    """SendGrid v3 ``mail/send`` shape (other HTTP providers accept the same with an adapter)."""

    def __init__(self, settings: Settings, client: httpx.AsyncClient | None = None) -> None:
        self._s = settings
        self._client = client

    def payload(self, email: Email) -> dict[str, object]:
        return {
            "personalizations": [{"to": [{"email": to} for to in email.to]}],
            "from": {"email": self._s.email_from},
            "subject": email.subject,
            "content": [{"type": "text/plain", "value": email.text}],
            "attachments": [
                {
                    "content": base64.b64encode(a.content).decode("ascii"),
                    "filename": a.filename,
                    "type": a.content_type,
                    "disposition": "attachment",
                }
                for a in email.attachments
            ],
        }

    async def send(self, email: Email) -> None:
        if not self._s.email_api_key:
            raise EmailError("EMAIL_API_KEY is not set")
        headers = {"Authorization": f"Bearer {self._s.email_api_key}"}
        client = self._client or httpx.AsyncClient(timeout=self._s.email_timeout_s)
        try:
            resp = await client.post(
                self._s.email_api_url, json=self.payload(email), headers=headers
            )
            if resp.status_code >= 300:
                raise EmailError(f"email API answered {resp.status_code}")
        except httpx.HTTPError as exc:
            raise EmailError("email API call failed") from exc
        finally:
            if self._client is None:
                await client.aclose()


def build_email_sender(settings: Settings) -> EmailSender:
    match settings.email_provider:
        case "fake":
            return FakeEmailSender()
        case "smtp":  # pragma: no cover - configuration
            return SmtpEmailSender(settings)
        case "sendgrid":
            return HttpEmailSender(settings)
        case _:
            return LogEmailSender()


__all__ = [
    "Attachment",
    "Email",
    "EmailError",
    "EmailSender",
    "FakeEmailSender",
    "HttpEmailSender",
    "LogEmailSender",
    "SmtpEmailSender",
    "build_email_sender",
]
