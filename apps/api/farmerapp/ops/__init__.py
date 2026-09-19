"""SPEC 12.2 business monitors that run as jobs (OPS-007 store day watch, OPS-009 queue age).

OPS-006 (officer sync silence) lives with duty (``farmerapp.duty.auto_end``), OPS-008
(payment reconciliation) with payments (``farmerapp.payments.reconcile``) and OPS-010 (flags
past SLA) with flags (``farmerapp.flags.service.escalate_overdue``).
"""
