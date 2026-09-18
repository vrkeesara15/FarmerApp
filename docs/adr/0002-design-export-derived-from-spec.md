# ADR 0002: Design export derived from SPEC §13 (no Claude Design handoff supplied)

Date: 2026-09-17. Status: accepted (provisional).

## Context
SPEC §0 step 2 expects a Claude Design export committed under `design/`. Only the PDF specification was supplied.

## Decision
`design/tokens.json` is written directly from the token values in §13.1. Component names and screen IDs from §13.1–§13.4 are used verbatim. `design/screens/<ID>.md` and `design/components/<Name>.md` are authored by the build loop when a requirement first touches them, using the copy and data fields listed in the prompts.

## Consequences
When a real design export arrives, replace the files under `design/` and re-run the golden tests; component names are stable so the mapping stays 1:1.
