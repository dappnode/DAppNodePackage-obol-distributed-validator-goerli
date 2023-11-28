#!/bin/bash
# Exit on error
set -eo pipefail

#############
# VARIABLES #
#############
ERROR="[ ERROR-charon-manager ]"
WARN="[ WARN-charon-manager ]"
INFO="[ INFO-charon-manager ]"

CHARON_ROOT_DIR=/opt/charon/.charon
CREATE_ENR_FILE=${CHARON_ROOT_DIR}/create_enr.txt
ENR_PRIVATE_KEY_FILE=${CHARON_ROOT_DIR}/charon-enr-private-key
ENR_FILE=${CHARON_ROOT_DIR}/enr
DEFINITION_FILE_URL_FILE=${CHARON_ROOT_DIR}/definition_file_url.txt

TEKU_SECURITY_DIR=/opt/charon/security
TEKU_CERT_FILE=$TEKU_SECURITY_DIR/certs/teku_${CLUSTER_ID}_certificate.p12
TEKU_CERT_PASS_FILE=$TEKU_SECURITY_DIR/certs/teku_certificate_pass.txt
TEKU_CERT_PASS=$(cat $TEKU_CERT_PASS_FILE)

CHARON_LOCK_FILE=${CHARON_ROOT_DIR}/cluster-lock.json
REQUEST_BODY_FILE=${CHARON_ROOT_DIR}/request-body.json
VALIDATOR_KEYS_DIR=${CHARON_ROOT_DIR}/validator_keys

if [ -n "$DEFINITION_FILE_URL" ]; then
  echo $DEFINITION_FILE_URL >$DEFINITION_FILE_URL_FILE
fi

export CHARON_P2P_EXTERNAL_HOSTNAME=${_DAPPNODE_GLOBAL_DOMAIN}

#############
# FUNCTIONS #
#############

# Get the current beacon chain in use
# Assign proper value to _DAPPNODE_GLOBAL_CONSENSUS_CLIENT_PRATER.
function get_beacon_node_endpoint() {
  case "$_DAPPNODE_GLOBAL_CONSENSUS_CLIENT_PRATER" in
  "prysm-prater.dnp.dappnode.eth")
    export CHARON_BEACON_NODE_ENDPOINTS="http://beacon-chain.prysm-prater.dappnode:3500"
    ;;
  "teku-prater.dnp.dappnode.eth")
    export CHARON_BEACON_NODE_ENDPOINTS="http://beacon-chain.teku-prater.dappnode:3500"
    ;;
  "lighthouse-prater.dnp.dappnode.eth")
    export CHARON_BEACON_NODE_ENDPOINTS="http://beacon-chain.lighthouse-prater.dappnode:3500"
    ;;
  "nimbus-prater.dnp.dappnode.eth")
    export CHARON_BEACON_NODE_ENDPOINTS="http://beacon-validator.nimbus-prater.dappnode:4500"
    ;;
  "lodestar-prater.dnp.dappnode.eth")
    export CHARON_BEACON_NODE_ENDPOINTS="http://beacon-chain.lodestar-prater.dappnode:3500"
    ;;
  *)
    echo "_DAPPNODE_GLOBAL_CONSENSUS_CLIENT_PRATER env is not set propertly"
    sleep 300 # Wait 5 minutes to avoid restarting the container
    ;;
  esac
}

# Get the ENR of the node or create it if it does not exist
function get_ENR() {
  # Check if ENR file exists and create it if it does not
  if [[ ! -f "$ENR_PRIVATE_KEY_FILE" ]]; then
    echo "${INFO} ENR does not exist, creating it..."
    charon create enr --data-dir=${CHARON_ROOT_DIR} | tee ${CREATE_ENR_FILE}
  fi
  # Get ENR from file
  if [[ ! -f "$ENR" ]]; then
    grep "enr:" ${CREATE_ENR_FILE} | cut -d " " -f 2 >$ENR_FILE
    ENR=$(cat $ENR_FILE)
    echo "${INFO} ENR: ${ENR}"
    echo "${INFO} Publishing ENR to dappmanager..."
    post_ENR_to_dappmanager
  else
    echo "${ERROR} it was not possible to get the ENR file"
    sleep 300 # Wait 5 minutes to avoid restarting the container
    exit 1
  fi
}

# function to be post the ENR to dappmanager
function post_ENR_to_dappmanager() {
  # Post ENR to dappmanager
  curl --connect-timeout 5 \
    --max-time 10 \
    --silent \
    --retry 5 \
    --retry-delay 0 \
    --retry-max-time 40 \
    -X POST "http://my.dappnode/data-send?key=ENR-Cluster-${CLUSTER_ID}&data=${ENR}" ||
    {
      echo "[ERROR] failed to post ENR to dappmanager"
      exit 1
    }
}

function check_DKG() {
  # If the definition file URL is set and the lock file does not exist, start DKG ceremony
  if [ -n "${DEFINITION_FILE_URL}" ] && [ ! -f "${CHARON_LOCK_FILE}" ]; then
    echo "${INFO} Waiting for DKG ceremony..."
    charon dkg --definition-file="${DEFINITION_FILE_URL}" --data-dir="${CHARON_ROOT_DIR}" || {
      echo "${ERROR} DKG ceremony failed"
      exit 1
    }

  # If the definition file URL is not set and the lock file does not exist, wait for the definition file URL to be set
  elif [ -z "${DEFINITION_FILE_URL}" ] && [ ! -f "${CHARON_LOCK_FILE}" ]; then
    echo "${INFO} Set the definition file URL in the Charon config to start DKG ceremony..."
    exit 0

  else
    echo "${INFO} DKG ceremony already done. Process can continue..."
  fi
}

function run_charon() {
  # Start charon in a subshell in the background
  (
    exec charon run --private-key-file=$ENR_PRIVATE_KEY_FILE --lock-file=$CHARON_LOCK_FILE --builder-api
  ) &
}

function run_teku_validator() {

  exec /opt/teku/bin/teku --log-destination=CONSOLE \
    validator-client \
    --network=prater \
    --beacon-node-api-endpoint=http://localhost:3600 \
    --data-base-path=/opt/teku/data \
    --metrics-enabled=true \
    --metrics-interface 0.0.0.0 \
    --metrics-port 8008 \
    --metrics-host-allowlist=* \
    --validator-api-enabled=false \
    --validators-keystore-locking-enabled=false \
    --validator-keys=${VALIDATOR_KEYS_DIR}:${VALIDATOR_KEYS_DIR} \
    --network=${NETWORK} \
    ${TEKU_EXTRA_OPTS}
}

########
# MAIN #
########

echo "${INFO} get the current beacon chain in use"
get_beacon_node_endpoint

echo "${INFO} getting the ENR..."
get_ENR

echo "${INFO} checking for DKG ceremony..."
check_DKG

echo "${INFO} starting charon..."
run_charon

echo "${INFO} starting teku validator..."
run_teku_validator