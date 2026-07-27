# Claude instructions

This repo builds and publishes the Docker image used by Anchored Development drift
detection CI jobs. The image pre-installs the Claude Code CLI and the Claude Agent
SDK on `node:24.14.0-trixie-slim` so consuming pipelines don't install them on every
run.

This is a **public** repo, mirrored to GitHub, and the image is pulled by projects
outside this namespace. Treat it as a reference implementation.

## Files

- `Dockerfile` — the image definition
- `.gitlab-ci.yml` — lint, build, release-on-tag, and security scanning
- `package.json` / `package-lock.json` — the Agent SDK baked into the image

## Release model

Publishing happens **only from a git tag**. Merge requests and branch pushes build
for validation and never push. Semver without a `v` prefix; the git tag and the image
tag are the same string.

Consumers pin `image:<version>@sha256:<digest>` — tag *and* digest. The tag keeps the
manifest from being garbage-collected; the digest is the integrity check. Never
suggest a digest-only pin: GitLab.com deletes untagged manifests ~24h after they stop
being referenced, which silently breaks every consumer pinned to them.

## Conventions

- Keep the image minimal. Only add packages required at runtime.
- **Pin everything that comes from outside the project**, by digest where the
  ecosystem has one: base image, build toolchain (dind and BuildKit), scanner images,
  npm deps (exact versions, lockfile integrity hashes), and the Claude Code CLI
  version.
- **The one deliberate exception is `apt-get install`.** Debian removes old package
  versions from the archive, so version-pinning them breaks builds unpredictably. The
  refresh path is the base-image digest bump (it changes the layer cache key, so the
  apt layer rebuilds against the current archive); the weekly Grype scan is the signal
  that the bump is overdue. `hadolint` DL3008 is ignored for this reason — don't
  "fix" it.
- **Never add a timed rebuild.** A fully-pinned image rebuilt on a timer replays
  cached layers and produces an identical image under a *new manifest digest*, which
  is what breaks downstream pins. Freshness comes from Renovate.
- Renovate maintains the pins. When adding a new external dependency, make sure it is
  in a form Renovate can see — a digest, a lockfile entry, or a
  `# renovate: datasource=… depName=…` annotation above a `RUN <NAME>_VERSION=` line.
- Security jobs are **inlined**, not included from the private `ci-templates` project.
  `include: project:` resolves with the permissions of whoever runs the pipeline, so a
  private include would break CI for outside contributors and leak a private path into
  a public file. Keep them inline.
- Bumping the Agent SDK is not routine: it is a `0.x` package, so a minor bump can
  break the drift-detector scripts that consumers run inside this image. Smoke-test
  before releasing, and consider whether it warrants a MAJOR.
