ARG UPSTREAM_VERSION

FROM obolnetwork/charon:${UPSTREAM_VERSION}

USER root

RUN apt install curl jq -y

RUN mkdir -p /opt/charon/.charon && chown -R charon:charon /opt/charon

COPY teku_client_keystore.p12 /teku_client_keystore.p12
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]