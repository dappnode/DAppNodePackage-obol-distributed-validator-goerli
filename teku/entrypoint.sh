#!/bin/bash

# TODO: How to handle p12 keystore?

# Teku must start with the current env due to JAVA_HOME var
exec /opt/teku/bin/teku --log-destination=CONSOLE \
  validator-client \
  --data-base-path=/opt/teku/data \
  --metrics-enabled=true \
  --metrics-interface 0.0.0.0 \
  --metrics-port 8008 \
  --metrics-host-allowlist=* \
  --validator-api-enabled=true \
  --validator-api-interface=0.0.0.0 \
  --validator-api-port=3500 \
  --validator-api-host-allowlist=* \
  --validator-api-keystore-file="/certs/teku_${CLUSTER_ID}_certificate.p12" \
  --validator-api-keystore-password-file=/certs/teku_certificate_pass.txt \
  --logging=${LOG_TYPE} \
  --validators-keystore-locking-enabled=false \
  ${EXTRA_OPTS}
