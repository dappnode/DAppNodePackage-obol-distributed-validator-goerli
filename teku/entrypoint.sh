#!/bin/bash

# Retry 10 times with 30 seconds between each try
for i in {1..10}; do
  echo "[INFO] Checking if charon is ready (Attempt $i)..."
  if wget -qO- "http://charon-${CLUSTER_ID}:3620/readyz" &>/dev/null; then
    echo "[INFO] Charon is ready!"
    break
  fi
  sleep 30
done

# Exit 0 if charon is not ready. Saying that the cluster is disabled
if [ $i -eq 10 ]; then
  echo "[INFO] Charon is not ready. The cluster is disabled."
  exit 0
fi

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
