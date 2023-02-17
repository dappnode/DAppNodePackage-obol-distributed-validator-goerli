FROM obolnetwork/charon:v0.13.0 

USER root

RUN apk add --no-cache bash curl jq

RUN mkdir -p /opt/charon/.charon && chown -R charon:charon /opt/charon

COPY teku_client_keystore.p12 /teku_client_keystore.p12
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]