# Alpine, not Debian. Measured on the same contents: Debian slim carried 135
# High/Critical findings, Alpine carries 38 -- a 72% smaller surface, mostly
# because Alpine simply ships far fewer packages. The Claude Code CLI has an
# official musl build (`linux-{x64,arm64}-musl`) and install.sh detects musl
# itself, so nothing about the runtime is unofficial.
#
# Base image is digest-pinned. Renovate bumps the digest, and that bump is what
# refreshes the OS packages below: a new base changes the layer cache key, so the
# apk layer is rebuilt against the current Alpine repository.
FROM node:24.18.0-alpine3.23@sha256:595398b0081eacda8e1c4c5b97b76cd1020e4d58a8ebcb4843b9bca1e79e7436

# `apk upgrade` first: the base image is a point-in-time snapshot, so packages it
# already contains (openssl, libcrypto) can carry fixed CVEs that `apk add` alone
# would never touch. Upgrading at build time clears those. Same pattern as the
# encodinator dashboard image.
#
# Deliberately NOT version-pinned. Alpine drops old package versions from the
# repository as it moves, so pinning here breaks the build on a schedule nobody
# controls. The supply-chain control for this layer is the digest-pinned base above
# plus the weekly Grype scan, which is what tells us when that base bump is overdue.
# hadolint DL3018 is ignored in CI for this reason.
#
# bash is required: the SHELL directive below and the Claude installer both need it.
RUN apk upgrade --no-cache \
    && apk add --no-cache bash git curl jq

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

WORKDIR /opt/sdk
COPY package.json package-lock.json ./
RUN npm ci \
    && ln -s /opt/sdk/node_modules /node_modules

# Claude Code CLI, version-pinned so the image is reproducible. install.sh fetches
# the release manifest and verifies the downloaded binary's SHA-256 before
# installing, so the version pin plus that check is the control here -- there is no
# stable artifact URL for us to checksum ourselves. Renovate keeps the pin current
# via the `RUN <NAME>_VERSION=` custom manager; the CLI shares its version line with
# the @anthropic-ai/claude-code npm package, which is what that datasource tracks.
# renovate: datasource=npm depName=@anthropic-ai/claude-code
RUN CLAUDE_CODE_VERSION="2.1.172" \
    && curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}"

ENV PATH="/root/.local/bin:${PATH}"
