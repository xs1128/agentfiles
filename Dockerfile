FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      less \
      ripgrep \
      unzip \
    && rm -rf /var/lib/apt/lists/*

ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && npm cache clean --force

# Both installers target the invoking user's home; the image needs them on PATH
# for whichever uid the runtime decides to be.
RUN curl -fsSL https://bun.sh/install | bash \
    && mv /root/.bun/bin/bun /usr/local/bin/bun \
    && rm -rf /root/.bun
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh \
    && mv /root/.local/bin/rtk /usr/local/bin/rtk

ENV CLAUDE_CONFIG_DIR=/opt/agent-config
COPY config/ /opt/agent-config/
COPY manifests/ /opt/manifests/
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh && /opt/scripts/bootstrap.sh /opt/manifests

ARG VERSION=dev
RUN echo "$VERSION" > /opt/agent-config/.version

RUN git config --system user.name "Xinsheng Ooi" \
    && git config --system user.email "ooixinsheng@gmail.com" \
    && git config --system --add safe.directory '*'

USER node
WORKDIR /work
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
