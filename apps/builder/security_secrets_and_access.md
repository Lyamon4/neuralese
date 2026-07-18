# Security, Secrets, and Access

This document describes how Neuralese should protect source code, runtime secrets, and team access.

## Threat Model

The most important assumption for this repo is:

- Anything shipped to a client device can eventually be inspected.

That includes:

- Godot export bundles such as `.pck` content
- GDScript logic
- frontend JavaScript bundles
- local config files stored on the user's machine

Because of that, client-side packaging or encryption can slow reverse engineering down, but it cannot be the place where real secrets live.

## What Encryption Helps With

Encryption is still useful, but only in the right places:

- Disk encryption protects a developer laptop or build machine at rest.
- Encrypted backups protect code and secret exports if backup storage is compromised.
- Encrypted secret stores such as Doppler protect secrets in transit and at rest.
- Godot asset/package encryption can raise the effort required to inspect client assets.

Encryption does **not** make it safe to embed privileged secrets into a Godot build, desktop app, or browser bundle.

## Rules for Secrets

These values must stay server-side only:

- `CLERK_SECRET_KEY`
- database credentials
- private signing keys
- admin API tokens
- service tokens with write access
- anything that can mint tokens, modify user data, or bypass auth

These are acceptable to expose to the client when the provider intends them to be public:

- `NEXT_PUBLIC_*` values such as `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`
- public API base URLs
- non-sensitive feature flags

## Neuralese Guidance

For the current architecture:

- Godot must never contain the Clerk secret key.
- The Godot client should eventually hold only a short-lived user token or session token.
- The Python backend should verify that token and act on behalf of the authenticated user.
- Doppler should be the source of truth for local development, CI, and deployed server secrets.

## Recommended Storage Strategy

Use three separate layers:

1. Code storage
2. Secrets storage
3. Backup and recovery

### Code Storage

- Keep the repository in a private git remote.
- Limit write access to trusted teammates.
- Protect the default branch.
- Require review for auth, deployment, and secret-handling changes.

### Secrets Storage

- Store development and server secrets in Doppler.
- Use one Doppler project per app or service where practical.
- Split environments by config, for example `dev`, `staging`, and `prod`.
- Use `doppler run` for local development.
- Use service tokens for deployed workloads instead of personal tokens.

For this repo:

- `clerk-nextjs/` currently uses Doppler project `neuralese-clerk-nextjs`
- active config: `dev`

### Backup and Recovery

- Keep the repo in git plus an encrypted offsite backup.
- Keep encrypted backups of critical secret material and environment exports.
- Keep a documented recovery path for Doppler, git hosting, and deployment credentials.
- Maintain at least two people with owner-level recovery access for critical platforms.

## Doppler Practices

### Local Development

Use Doppler-injected runtime secrets instead of checked-in `.env.local` files:

```bash
cd clerk-nextjs
npm run dev:doppler
```

### Production and CI

Do not use a personal Doppler token in production.

Prefer:

- read-only service tokens scoped to a single config
- service accounts if your Doppler plan and organization setup support them

### Rotation

Rotate secrets when:

- a secret was pasted into chat, logs, screenshots, or tickets
- a teammate leaves
- a machine is lost or compromised
- a provider notifies you of suspicious access

After rotation:

- update Doppler
- verify builds and runtime
- revoke any replaced tokens

## Teammate Access in Doppler

The clean setup is:

- invite the teammate to the Doppler workplace
- give them the lowest workplace role they need
- then grant project-level access only to the projects/configs they should touch

Recommended pattern:

- `Owner`: only founders or emergency recovery admins
- `Admin`: a small set of trusted operators
- `Collaborator`: most engineers

Project access:

- `Viewer`: can inspect but not modify
- `Collaborator`: can manage secrets for that project
- `Admin`: can fully manage the project

For a normal teammate working on the Clerk auth companion:

- workplace role: `Collaborator`
- project role on `neuralese-clerk-nextjs`: `Collaborator` if they must edit secrets, otherwise `Viewer`

## Hard Rules

- Never commit real secrets to the repository.
- Never embed privileged secrets in Godot exports or frontend bundles.
- Never rely on client-side code obfuscation as the main protection layer.
- Never use production secrets in development environments unless there is a specific, documented reason.
- Never share personal owner credentials for machine-to-machine access.

## Practical Checklist

- Store secrets in Doppler.
- Keep `.env` files local-only and ignored.
- Use server-side token verification for auth.
- Use encrypted backups for code and secret exports.
- Keep two recovery admins for critical systems.
- Rotate leaked or exposed secrets immediately.

