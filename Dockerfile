# Base image is digest-pinned. Renovate bumps the digest, and that bump is what
# actually refreshes the apt packages below: a new base changes the layer cache
# key, so the `apt-get install` layer is rebuilt against the current archive.
FROM node:24.14.0-trixie-slim@sha256:8c8f12cedb96c3b59642cf30d713943c2b223990c9919b96a141681f62e6e292

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# Deliberately NOT version-pinned. Debian drops old package versions from the
# archive on every point release, so pinning here breaks the build on a schedule
# nobody controls. The supply-chain control for this layer is the digest-pinned
# base above (which carries Debian's own patched packages) plus the weekly Grype
# scan, which is what tells us when that base bump is overdue. hadolint DL3008 is
# ignored in CI for this reason.
RUN apt-get update && apt-get install -y \
    git curl jq yq \
    && rm -rf /var/lib/apt/lists/*

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
