# docker/mockserver

Tiny FastAPI stand-in for the external providers, used by `docker compose` and tests.
Everything is in memory; `DELETE /_mock/reset` clears it. Port 8090.

| Provider | Endpoints |
|---|---|
| SMS | `POST /sms/send` `{to, message}` -> stores; `GET /sms/messages?to=` lists (tests read OTPs here); `GET /sms/status/{id}` delivery report (`delivered` / `pending`); `POST /sms/messages/{id}/deliver` and `POST /_mock/sms/config` `{auto_deliver}` simulate late delivery (FA-001 WhatsApp fallback) |
| WhatsApp | `POST /whatsapp/send` `{to, template, params}` -> stores; `GET /whatsapp/messages?to=`; `GET /whatsapp/status/{id}` |
| Razorpay-like | `POST /razorpay/v1/orders`, `GET /razorpay/v1/orders/{id}`, `POST /razorpay/v1/payment_links`, `POST /razorpay/v1/payments/qr_codes`, `POST /razorpay/v1/orders/{id}/pay` (simulate capture), `POST /razorpay/v1/payments/qr_codes/{id}/pay` (simulate a UPI scan; payment carries the QR notes), `GET /razorpay/v1/settlements/recon/combined?year&month&day` and `GET /razorpay/settlements?date=` (OPS-008: captured payments of the day) |
| Webhook helper | `POST /_mock/webhooks/simulate` `{target_url, event, payload}` -> POSTs a Razorpay-style webhook to `target_url` signed with HMAC-SHA256 (`X-Razorpay-Signature`) using `MOCK_RAZORPAY_WEBHOOK_SECRET` |

Run outside Docker: `cd docker/mockserver && uv run uvicorn mockserver.app:app --port 8090`.
