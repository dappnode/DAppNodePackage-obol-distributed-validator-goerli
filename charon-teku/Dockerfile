ARG UPSTREAM_VERSION

FROM obolnetwork/charon:${UPSTREAM_VERSION}

# To prevent the user from editing the CLUSTER_ID, we set it as an ARG
ARG CLUSTER_ID
ENV CLUSTER_ID=${CLUSTER_ID} CHARON_LOG_FORMAT=console JAVA_OPTS="-Xmx5g"

USER root

# TODO: Install ca-certificates?
# Install Java to run Teku
RUN apt-get update && \
    apt-get install -y jq curl openjdk-17-jdk && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG TEKU_VERSION
RUN curl -L https://artifacts.consensys.net/public/teku/raw/names/teku.tar.gz/versions/${TEKU_VERSION}/teku-${TEKU_VERSION}.tar.gz | tar -xz -C /tmp && \
    mkdir -p /opt/teku/bin /opt/teku/lib && \
    mv /tmp/teku-${TEKU_VERSION}/bin/teku /opt/teku/bin && \
    mv /tmp/teku-${TEKU_VERSION}/lib/* /opt/teku/lib && \
    rm -rf /tmp/teku-${TEKU_VERSION}

RUN mkdir -p /opt/charon/.charon && chown -R charon:charon /opt/charon

COPY teku_security/ /opt/charon/security/

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]