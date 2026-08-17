ARG RALPHEX_VERSION

FROM ghcr.io/umputun/ralphex:${RALPHEX_VERSION}

ARG OPENCODE_VERSION

RUN npm install -g opencode-ai@${OPENCODE_VERSION} \
    && command -v opencode >/dev/null \
    && opencode --version

LABEL org.opencontainers.image.title="Ralphex with OpenCode"
LABEL org.opencontainers.image.description="Ralphex runtime with OpenCode CLI"
LABEL org.opencontainers.image.source="https://github.com/sshroot/ralphex-opencode"
