ARG TEKU_VERSION
FROM consensys/teku:${TEKU_VERSION}

# To prevent the user from editing the CLUSTER_ID, we set it as an ARG
ARG CLUSTER_ID
ENV CLUSTER_ID=${CLUSTER_ID} TEKU_NETWORK=prater JAVA_OPTS="-Xmx5g"

USER root 
RUN apt update && apt install curl jq ca-certificates --yes

COPY /security/validator-api-bearer /opt/teku/data/validator/key-manager/validator-api-bearer 
COPY /security/certs /certs
COPY entrypoint.sh /usr/bin/entrypoint.sh

ENTRYPOINT  ["entrypoint.sh"]
