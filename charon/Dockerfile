ARG UPSTREAM_VERSION

FROM obolnetwork/charon:${UPSTREAM_VERSION}

# To prevent the user from editing the CLUSTER_ID, we set it as an ARG
ARG CLUSTER_ID
ENV CLUSTER_ID=${CLUSTER_ID} CHARON_LOG_FORMAT=console

USER root

RUN apt install curl jq -y

RUN mkdir -p /opt/charon/.charon && chown -R charon:charon /opt/charon

COPY teku_security/ /opt/charon/teku/security/

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]