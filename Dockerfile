FROM debian:bookworm-slim AS downloader
ARG VERSION=3.7.36
ARG SHA256=ec02ca80862cc1ed2c24626b01fc841a3772551a75ce93813d60d856e8712d1e
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    curl -fsSL "https://api.primecrunch.com/v2/upgrade/primecrunch-linux-amd64-v${VERSION}.tar.gz" \
         -o /tmp/crunch.tar.gz && \
    printf '%s  /tmp/crunch.tar.gz\n' "${SHA256}" | sha256sum -c && \
    tar -xzf /tmp/crunch.tar.gz -C /tmp/ && \
    chmod +x /tmp/crunch

FROM debian:bookworm-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl jq && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 1000 crunch && \
    useradd -u 1000 -g crunch -M -s /bin/sh crunch

COPY --from=downloader /tmp/crunch /usr/local/bin/crunch
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER crunch

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
