# AI Tooling instructions

This repo builds and publishes the Docker image used by Anchored Development drift
detection CI jobs. The image pre-installs the Claude Agent SDK so consuming pipelines
don't install it on every run. Claude Code itself is the official musl binary the SDK
vendors as a platform-specific optional dependency — it is what the SDK spawns, and it
is symlinked onto `PATH` as `claude`.

The build is two-stage: `npm ci` runs in a `node:<version>-alpine<X.Y>` stage, and the
runtime is a bare `alpine` of the same release with the `node` binary copied in. npm is
build-time only, so the runtime image ships no package manager. The Dockerfile is the
line of truth for those versions — don't restate them here, or in the README.

Those two bases MUST stay on the same Alpine release: the copied `node` binary links
against the build stage's musl and `libstdc++`, and a mismatch fails inside a consumer's
pipeline rather than in this build. `lint:base-lockstep` enforces it.

This is a **public** repo, mirrored to GitHub, and the image is pulled by projects
outside this namespace. Treat it as a reference implementation.

## Files

- `Dockerfile` — the image definition
- `.gitlab-ci.yml` — lint, build, release-on-tag, and security scanning
- `.grype.yaml` — accepted, dated vulnerability exceptions
- `package.json` / `package-lock.json` — the Agent SDK baked into the image, and with
  it the Claude Code binary (an SDK platform package, integrity-hashed in the lockfile)

## Release model

Publishing happens **only from a git tag**. Merge requests and branch pushes build
for validation and never push. Semver without a `v` prefix; the git tag and the image
tag are the same string.

Consumers pin `image:<version>@sha256:<digest>` — tag *and* digest. The tag keeps the
manifest from being garbage-collected; the digest is the integrity check. Never
suggest a digest-only pin: GitLab.com deletes untagged manifests ~24h after they stop
being referenced, which silently breaks every consumer pinned to them.

The **GitLab release page is the changelog**, and the tag is a pointer to it. A tag
message is read one line at a time through `git tag -n`, by someone deciding what to
pin — a poor home for a change list, and one that cannot be corrected afterwards where
a release page can. So the tag carries a summary line and a link, and nothing else:

```
3.0.0 — no package manager in the runtime image

Release notes: https://gitlab.com/boomshadow-public/anchor-watch-image/-/releases/3.0.0
```

The release URL is `/-/releases/<tag>`, so it is known before the release exists. That
is what lets the tag point at one not yet created.

### Cutting a release

```bash
git tag -a <version> -m "<summary line>

Release notes: https://gitlab.com/boomshadow-public/anchor-watch-image/-/releases/<version>"
git push origin <version>
# the tag pipeline builds and pushes the image — wait for it to go green
glab release create <version> --notes-file <notes>
```

Both halves of that order matter. `glab release create` will invent a missing tag, but
only a lightweight one from the default branch, with no message — so the annotated tag
has to exist first. And the release is the announcement: creating it before the
pipeline is green advertises an image that may never have been pushed.

Write the notes as a short paragraph saying what the release is *about*, then the
changes themselves. Take the list from `git log --oneline <previous-tag>..<version>`
and keep all of it — completeness is the point, and a note that drops the dull commits
is worse at the one job it has months later, which is telling someone where a change
landed and why. Group by what a reader came for rather than by commit type, and where
a release has no theme, say so instead of inventing one.

A published tag is never moved or deleted: consumers pin to it and the GitHub mirror
has already seen it. The repair for a bad release is the next version.

## Conventions

- Keep the image minimal. Only add packages required at runtime. Anything needed just
  to build belongs in the build stage, where it never reaches a published layer or an
  SBOM.
- **Pin everything that comes from outside the project**, by digest where the
  ecosystem has one: both base images, build toolchain (dind and BuildKit), scanner
  images, and npm deps (exact versions, lockfile integrity hashes — this covers Claude
  Code itself, which ships as the Agent SDK's platform package).
- **Never `--omit=optional` on `npm ci`.** Claude Code is a platform-specific
  optionalDependency of the Agent SDK; omitting it builds an image that fails at spawn
  time rather than at build time.
- **The one deliberate exception is `apk`.** Alpine removes old package versions from
  its repository as it moves, so version-pinning them breaks builds unpredictably.
  What refreshes them instead is `apk upgrade` at build time plus
  `--no-cache-filter runtime` on the build and push jobs, which stops the layer being
  replayed from the registry cache. The base-image digest is not enough on its own:
  Alpine fixes packages in the repository without rebuilding the base image, so a
  digest bump may never come. The weekly Grype scan against the published image is
  the signal that a release is overdue. `hadolint` DL3018 is ignored for this reason
  — don't "fix" it, and don't drop the `--no-cache-filter` to speed a build up.
- **Alpine, not Debian, and this was measured.** On identical contents Debian slim
  carried 135 High/Critical findings against Alpine's 38. Don't switch back without
  re-measuring. `yq` was removed for the same reason: nothing consuming this image
  used it, and Alpine's Go-built `yq` alone accounted for 10 of the remaining fixable
  findings. Note that Alpine's `yq` is mikefarah/yq v4 while Debian's was the Python
  kislyuk/yq 3.x — different tools, incompatible syntax — so re-adding it is a
  behavioural change, not just a package add.
- **Never add a timed rebuild.** A fully-pinned image rebuilt on a timer replays
  cached layers and produces an identical image under a *new manifest digest*, which
  is what breaks downstream pins. Freshness comes from Renovate.
- Renovate maintains the pins. When adding a new external dependency, make sure it is
  in a form Renovate can see — a digest, a lockfile entry, or a
  `# renovate: datasource=… depName=…` annotation above a `RUN <NAME>_VERSION=` line.
- Vulnerability exceptions go in `.grype.yaml`, **one entry per CVE** with a concrete
  reachability rationale and an `[expires:YYYY-MM-DD]` tag. Never use a blanket
  `package: type:` rule here — per-CVE entries mean a new finding in an
  already-excepted package still fails the build. The `security:exception-audit` job
  enforces the expiry tags.
- Security jobs are **inlined**, not included from the private `ci-templates` project.
  `include: project:` resolves with the permissions of whoever runs the pipeline, so a
  private include would break CI for outside contributors and leak a private path into
  a public file. Keep them inline.
- Bumping the Agent SDK is not routine: it is a `0.x` package, so a minor bump can
  break the drift-detector scripts that consumers run inside this image. Smoke-test
  before releasing, and consider whether it warrants a MAJOR.
