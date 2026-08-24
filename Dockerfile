# Two stages, and the split is the security control rather than a size trick.
#
# npm exists only to run `npm ci`. It is never invoked at runtime -- consuming
# pipelines run `node .claude/agents/scripts/ci-drift-detector.mjs`, and the Agent
# SDK spawns Claude Code directly without shelling out to a package manager. But
# npm ships ~144 vendored dependencies of its own inside the node image -- half the
# SBOM, and the source of most of its Critical/High findings (node-tar,
# brace-expansion, undici, ip-address). None of them are fixable here: they are not
# in package-lock.json, and for several no published node base carries the patched
# version at all. Leaving the builder behind deletes that entire class of finding
# instead of suppressing it one advisory at a time.
#
# Alpine, not Debian. On identical contents Debian slim was measured at 135
# High/Critical findings against a far smaller count on Alpine, mostly because
# Alpine simply ships fewer packages.

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: build. Exists to run `npm ci` and nothing else, so it installs no
# packages -- everything the runtime needs is installed in stage 2.
# ─────────────────────────────────────────────────────────────────────────────
FROM node:24.18.0-alpine3.23@sha256:595398b0081eacda8e1c4c5b97b76cd1020e4d58a8ebcb4843b9bca1e79e7436 AS build

WORKDIR /opt/sdk
COPY package.json package-lock.json ./

# NEVER add --omit=optional. Claude Code ships as a platform-specific
# optionalDependency of the Agent SDK (@anthropic-ai/claude-agent-sdk-linux-*),
# and it is the binary the SDK actually executes. Omitting optional dependencies
# produces an image that fails at spawn time with "Native CLI binary not found".
RUN npm ci

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: runtime. Bare Alpine plus the node binary, which is the pattern the
# official nodejs/docker-node BestPractices guide recommends for exactly this.
#
# This base MUST stay on the same Alpine major.minor as the node image above --
# the node binary is copied out of that image and links against its musl and
# libstdc++. Renovate bumps the two digests independently, so when one moves to a
# new Alpine minor the other has to move with it.
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

# `apk upgrade` first: the base image is a point-in-time snapshot, so packages it
# already contains can carry fixed CVEs that `apk add` alone would never touch.
# Upgrading at build time clears those.
#
# Deliberately NOT version-pinned. Alpine drops old package versions from the
# repository as it moves, so pinning here breaks the build on a schedule nobody
# controls. The supply-chain control for this layer is the digest-pinned base above
# plus the weekly Grype scan, which is what tells us when that base bump is overdue.
# hadolint DL3018 is ignored in CI for this reason.
#
# bash is required by the SHELL directive below. libstdc++ is what the copied node
# binary links against (`ldd node` resolves musl, libstdc++ and libgcc_s, the last
# of which comes in as a libstdc++ dependency).
#
# The `node` user is created for parity with the official node image, which also
# creates it and also does not switch to it. Jobs still run as root: GitLab's helper
# container clones the repository as root, and a non-root job user then trips git's
# dubious-ownership guard, which would break the drift detector's git calls. Running
# non-root additionally requires FF_DISABLE_UMASK_FOR_DOCKER_EXECUTOR in every
# consuming pipeline.
RUN apk upgrade --no-cache \
    && apk add --no-cache bash git curl jq libstdc++ \
    && addgroup -g 1000 node \
    && adduser -u 1000 -G node -s /bin/sh -D node

COPY --from=build /usr/local/bin/node /usr/local/bin/node
COPY --from=build /opt/sdk/node_modules /opt/sdk/node_modules

# Two symlinks, both pointing into the SDK tree:
#
#   /node_modules  -- lets drift-detector scripts resolve the SDK from any cwd
#                     without a per-run `npm install`.
#   claude         -- the CLI on PATH. Deliberately a link, not a second copy.
#                     Installing Claude Code separately (`claude.ai/install.sh`) was
#                     rejected: it produces a byte-identical duplicate of the binary
#                     the SDK already vendors, and the SDK never runs it -- the SDK
#                     resolves its executable through require.resolve on its platform
#                     package and does not consult PATH at all. Two independently
#                     pinned copies also drift, leaving `claude --version` disagreeing
#                     with the binary drift detection actually runs. Linking keeps the
#                     SDK's copy as the single source of truth, and the lockfile's
#                     integrity hash as the supply-chain control in place of a
#                     `curl | bash`.
RUN ln -s /opt/sdk/node_modules /node_modules \
    && ln -s /opt/sdk/node_modules/@anthropic-ai/claude-agent-sdk-linux-*/claude /usr/local/bin/claude

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
