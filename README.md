# anchor-watch-image

Pre-built Docker image for running [Anchored Development](https://anchored-dev.org) drift detection in CI pipelines.

## What's in the image

- `node:24.14.0-trixie-slim` base (Debian), digest-pinned
- [Claude Code](https://claude.ai) CLI, version-pinned
- [`@anthropic-ai/claude-agent-sdk`](https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk),
  installed at `/opt/sdk` and symlinked to `/node_modules` so drift-detector scripts resolve it
  without a per-run `npm install`
- `git`, `curl`, `jq`, `yq` (see [Dockerfile](Dockerfile))

## Usage

Pin the version tag **and** the digest:

```yaml
anchor-watch:
  image: registry.gitlab.com/boomshadow/anchor-watch-image:1.0.0@sha256:<digest>
  script:
    - node .claude/agents/scripts/ci-drift-detector.mjs
```

The digest is printed by the release pipeline, and is also visible via:

```sh
docker buildx imagetools inspect registry.gitlab.com/boomshadow/anchor-watch-image:1.0.0
```

**Pin the tag, not just the digest.** A digest-only reference (`@sha256:…` with no tag) points at a
manifest that becomes untagged as soon as a newer release moves `:latest` — and GitLab.com's registry
garbage-collects untagged manifests about 24 hours later, at which point every pipeline pinned to it
fails with `manifest unknown`. An immutable version tag keeps its manifest alive permanently, so a pin
can go stale but can never break.

`:latest` exists for discovery. Don't reference it from CI.

## Versioning

[Semantic versioning](https://semver.org), without a `v` prefix — the git tag and the image tag are both
`1.0.0`.

- **MAJOR** — breaking for consumers: a Node major, a removed tool, a changed `PATH`/entrypoint, or an
  SDK change that breaks drift-detector scripts
- **MINOR** — a tool added, or an SDK minor
- **PATCH** — base image digest refresh, SDK patch, apt security refresh

## Releasing

Publishing happens **only from a git tag**. Push a tag on `main` and the pipeline builds
`linux/amd64,linux/arm64`, pushes `:<tag>` and `:latest`, and prints the published manifest digest.
Nothing else in the pipeline pushes — merge requests and branches build for validation only.

## How this image stays current

Dependencies are pinned and [Renovate](https://docs.renovatebot.com) proposes the updates — the image is
never rebuilt on a timer. A timed rebuild of a fully-pinned image just replays cached layers: it changes
nothing except the manifest digest, which is precisely what breaks downstream pins.

| Component | Pin | Updated by |
|---|---|---|
| Base image | digest | Renovate |
| npm dependencies | exact version + lockfile integrity hashes | Renovate |
| Claude Code CLI | exact version | Renovate |
| Build toolchain (dind, BuildKit) | digest | Renovate |
| Scanner images (Syft, Grype) | digest | Renovate |
| `apt-get install` packages | **unpinned, deliberately** | base image digest bump |

Debian drops old package versions from the archive on every point release, so pinning them breaks builds
on a schedule nobody controls. Instead, the base-image digest bump changes the layer cache key, which
rebuilds the `apt-get install` layer against the current archive — and the weekly Grype scan is what
tells us when that bump is overdue.

## Security scanning

Every pipeline runs Grype against the lockfile. Release and weekly-schedule pipelines additionally build
a Syft SBOM of the published image and scan it. High and Critical findings fail the job.

## Building locally

```sh
docker build -t anchor-watch-image .
```

## License

[MPL-2.0](LICENSE)
