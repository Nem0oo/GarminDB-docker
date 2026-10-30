# Build the GarminDB wheel from the upstream submodule
FROM python:3.12-slim AS wheel-builder
WORKDIR /build
COPY GarminDB/ .
RUN pip install --no-cache-dir build && python -m build --wheel --outdir /dist

FROM python:3.12-slim

ARG SUPERCRONIC_VERSION=v0.2.51
ARG SUPERCRONIC_SHA1SUM=1692066e350a88ff4d7d6474fe3c7a6c41ec5e89
ADD https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64 /usr/local/bin/supercronic
RUN echo "${SUPERCRONIC_SHA1SUM}  /usr/local/bin/supercronic" | sha1sum -c - \
 && chmod +x /usr/local/bin/supercronic

COPY --from=wheel-builder /dist/*.whl /tmp/
RUN pip install --no-cache-dir /tmp/*.whl && rm /tmp/*.whl

COPY scripts/sync.sh scripts/healthcheck.sh scripts/entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh && ln -s /usr/local/bin/sync.sh /usr/local/bin/sync-now

ENV SYNC_SCHEDULE="0 4 * * *" \
    MAX_AGE_HOURS=36

HEALTHCHECK --interval=1h --timeout=10s CMD ["healthcheck.sh"]
ENTRYPOINT ["entrypoint.sh"]
