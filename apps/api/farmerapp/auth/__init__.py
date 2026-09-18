"""Auth module (SPEC 8.1): phone + OTP login, JWT access/refresh tokens, current user.

FA-001 (OTP), SEC-020 (token lifetimes, rotation, reuse detection, device binding),
SEC-021 (OTP hashed at rest, constant-time compare, single use, per-phone velocity).
"""
