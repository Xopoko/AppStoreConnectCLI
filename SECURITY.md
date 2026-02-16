# Security Policy

## Reporting a Vulnerability

Please do not open a public GitHub issue for security reports.

Preferred: use GitHub Security Advisories (private vulnerability report) for this repository.

If that is not available, open a minimal public issue that asks for a private contact, without including sensitive details.

## Secrets / Credentials

- Never commit `.p8` keys, PEM private keys, JWTs, or real config files.
- Keep secrets in environment variables or in your local config outside the repository.
- Treat any secret that was ever placed inside the repository working tree as compromised and rotate it.

