# anchor-watch-image

Pre-built Docker image for running [Anchored Development](https://anchored-dev.org) drift detection in CI pipelines.

## What's in the image

- `alpine:3.23` base, digest-pinned, with the `node` binary copied from a digest-pinned
  `node:24.18.0-alpine3.23` build stage
- [`@anthropic-ai/claude-agent-sdk`](https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk),
  installed at `/opt/sdk` and symlinked to `/node_modules` so drift-detector scripts resolve it
  without a per-run `npm install`
- [Claude Code](https://claude.ai) CLI on `PATH` as `claude` — a symlink to the official musl
  binary the Agent SDK vendors, so the CLI and the binary drift detection actually runs are the
  same file
- `bash`, `git`, `curl`, `jq` (see [Dockerfile](Dockerfile))

**No package manager.** `npm`, `npx`, `yarn` and `corepack` exist only in the build stage. They are
never needed at runtime — consuming pipelines run `node …/ci-drift-detector.mjs`, and the Agent SDK
spawns Claude Code directly. npm carries ~144 vendored dependencies of its own that nothing here can
patch — they are not in `package-lock.json` — so keeping it in the build stage is what holds the
runtime image's Critical/High count at zero.

## Usage

Pin the version tag **and** the digest:

```yaml
anchor-watch:
  image: registry.gitlab.com/boomshadow/anchor-watch-image:2.0.0@sha256:<digest>
  script:
    - node .claude/agents/scripts/ci-drift-detector.mjs
```

The digest is printed by the release pipeline, and is also visible via:

```sh
docker buildx imagetools inspect registry.gitlab.com/boomshadow/anchor-watch-image:2.0.0
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
| Base images (runtime `alpine`, build `node`) | digest | Renovate |
| npm dependencies | exact version + lockfile integrity hashes | Renovate |
| Claude Code CLI | via the Agent SDK's platform package — exact version + lockfile integrity hash | Renovate |
| Build toolchain (dind, BuildKit) | digest | Renovate |
| Scanner images (Syft, Grype) | digest | Renovate |
| `apk` packages | **unpinned, deliberately** | base image digest bump |

Alpine drops old package versions from its repository as it moves, so pinning them breaks builds on a
schedule nobody controls. Instead, the build runs `apk upgrade` (which patches packages the base image
already shipped) and the base-image digest bump changes the layer cache key, rebuilding that layer
against the current repository — while the weekly Grype scan is what tells us when the bump is overdue.

Note the limit of that mechanism: the `apk` layer is cached, so it only re-runs when the base digest
changes. `apk upgrade` improves the starting point; it does not make a stale pin self-healing.

The two base images are coupled: the runtime `alpine` must stay on the same major.minor as the build
stage's `node:…-alpineX.Y`, because the `node` binary is copied out of that stage and links against its
musl and `libstdc++`. Renovate proposes the two digests independently, so when one moves to a new Alpine
minor the other has to move with it.

## Security scanning

Every pipeline runs Grype against the lockfile. Release and weekly-schedule pipelines additionally build
a Syft SBOM of the published image and scan it. High and Critical findings fail the job.

Accepted exceptions live in [`.grype.yaml`](.grype.yaml), one entry per CVE with a reachability
rationale, so a *new* finding in an already-excepted package still fails rather than hiding behind a
blanket rule. Every entry carries an `[expires:YYYY-MM-DD]` tag, and the `security:exception-audit` job
fails the build once one lapses — forcing the exception back into review instead of letting it rot.

## Building locally

```sh
docker build -t anchor-watch-image .
```

## License

[MPL-2.0](LICENSE)
