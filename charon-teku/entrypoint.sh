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
DEFINITION_FILE_HASH_FILE=${CHARON_ROOT_DIR}/definition_file_hash.txt

CHARON_P2P_EXTERNAL_HOSTNAME=${_DAPPNODE_GLOBAL_DOMAIN}
VALIDATOR_URL="https://localhost:3500"
GENESIS_VALIDATORS_ROOT=0x043db0d9a83813551ee2f33450d23797757d430911a9320530ad8a0eabc43efb
KEY_IMPORT_HEADER="{ \"keystores\": [], \"passwords\": [], \"slashing_protection\": {\"metadata\":{\"interchange_format_version\":\"5\",\"genesis_validators_root\":\"$GENESIS_VALIDATORS_ROOT\"},\"data\":[]}}"

TEKU_SECURITY_DIR=/opt/charon/security
TEKU_CERT_FILE=$TEKU_SECURITY_DIR/certs/teku_${CLUSTER_ID}_certificate.p12
TEKU_CERT_PASS_FILE=$TEKU_SECURITY_DIR/certs/teku_certificate_pass.txt
TEKU_CERT_PASS=$(cat $TEKU_CERT_PASS_FILE)
TEKU_API_TOKEN=$(cat $TEKU_SECURITY_DIR/validator-api-bearer)

# TODO: Check if it is ok to put all this files in the charon root
CHARON_LOCK_FILE=${CHARON_ROOT_DIR}/cluster-lock.json
REQUEST_BODY_FILE=${CHARON_ROOT_DIR}/request-body.json
CHARON_ROOT_DIR=${CHARON_ROOT_DIR}
VALIDATOR_KEYS_DIR=${CHARON_ROOT_DIR}/validator_keys

# If DEFINITION_FILE_HASH_FILE exists, get the definition file from the hash
if [ -f "$DEFINITION_FILE_HASH_FILE" ]; then
  DEFINITION_FILE_HASH=$(cat $DEFINITION_FILE_HASH_FILE)

elif [ -n "$DEFINITION_FILE_URL" ]; then
  #Get the definition file from the environment variable and the hash
  DEFINITION_FILE_HASH=$(echo $DEFINITION_FILE_URL | sed 's|https://api.obol.tech/dv/||g' | tr -d "/")
  if [[ $DEFINITION_FILE_URL != https* ]]; then
    DEFINITION_FILE_URL=https://api.obol.tech/dv/$DEFINITION_FILE_HASH
  fi

  echo $DEFINITION_FILE_HASH >$DEFINITION_FILE_HASH_FILE
fi

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

# function that handles the import of the validators
function import_key() {
  # Check if there are keys to import
  if [ -d $VALIDATOR_KEYS_DIR ]; then
    echo "${INFO} creating request body..."
    create_request_body_file
    echo "${INFO} importing validators.."
    import_validators
  fi
}

# Create request body file
# - It cannot be used as environment variable because the slashing data might be too big resulting in the error: Error list too many arguments
# - Exit if request body file cannot be created
function create_request_body_file() {
  echo ${KEY_IMPORT_HEADER} | jq >"$REQUEST_BODY_FILE"
  KEYSTORE_FILES=($(ls ${VALIDATOR_KEYS_DIR}/*.json))
  for KEYSTORE_FILE in "${KEYSTORE_FILES[@]}"; do
    KEYSTORE_NAME="${KEYSTORE_FILE%.*}"
    echo "${INFO} adding ${KEYSTORE_FILE}..."
    echo $(jq --slurpfile keystore ${KEYSTORE_FILE} '.keystores += [$keystore[0]|tojson]' ${REQUEST_BODY_FILE}) >${REQUEST_BODY_FILE}
    echo $(jq --slurpfile keystore ${KEYSTORE_FILE} '.slashing_protection.data += [{"pubkey": $keystore[0].pubkey, "signed_blocks":[],  "signed_attestations": []}]' ${REQUEST_BODY_FILE}) >${REQUEST_BODY_FILE}
    echo $(jq --arg walletpassword "$(cat ${KEYSTORE_NAME}.txt)" '.passwords += [$walletpassword]' ${REQUEST_BODY_FILE}) >${REQUEST_BODY_FILE}
  done
  echo $(jq '.slashing_protection |= tostring ' ${REQUEST_BODY_FILE}) >${REQUEST_BODY_FILE}
  cat ${REQUEST_BODY_FILE}
}

# Import validators with request body file
# - Docs: https://ethereum.github.io/keymanager-APIs/#/
function import_validators() {
  HTTP_RESPONSE=$(curl -X POST \
    --silent \
    -k --cert-type P12 --cert ${TEKU_CERT_FILE}:${TEKU_CERT_PASS} \
    -w "HTTPSTATUS:%{http_code}" \
    -d @"${REQUEST_BODY_FILE}" \
    --retry 30 \
    --retry-delay 3 \
    --retry-connrefused \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${TEKU_API_TOKEN}" \
    "${VALIDATOR_URL}"/eth/v1/keystores) ||
    {
      echo "[ERROR] failed to import keys into validator"
      exit 1
    }
  HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
  HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')

  if [ ! $HTTP_STATUS -eq 200 ]; then
    echo "[ERROR] failed to import keys into validator"
    exit 1
  else
    echo "${INFO} validator response: ${HTTP_BODY}"
  fi

  echo "${INFO} validators imported"
}

function run_charon() {
  # Start charon in a subshell in the background
  (
    exec charon run --private-key-file=$ENR_PRIVATE_KEY_FILE --lock-file=$CHARON_LOCK_FILE --builder-api
  ) &
}

function run_teku_validator() {
  # Teku must start with the current env due to JAVA_HOME var
  (
    exec /opt/teku/bin/teku --log-destination=CONSOLE \
      validator-client \
      --network=prater \
      --beacon-node-api-endpoint=http://localhost:3600 \
      --data-base-path=/opt/teku/data \
      --metrics-enabled=true \
      --metrics-interface 0.0.0.0 \
      --metrics-port 8008 \
      --metrics-host-allowlist=* \
      --validator-api-enabled=true \
      --validator-api-interface=0.0.0.0 \
      --validator-api-port=3500 \
      --validator-api-host-allowlist=* \
      --validator-api-keystore-file="${TEKU_CERT_FILE}" \
      --validator-api-keystore-password-file="${TEKU_CERT_PASS_FILE}" \
      --validators-keystore-locking-enabled=false \
      ${TEKU_EXTRA_OPTS}
  ) &
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

echo "${INFO} importing keys into validator..."
import_key
