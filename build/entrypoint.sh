#!/bin/bash
# Exit on error
set -eo pipefail

#############
# VARIABLES #
#############
ERROR="[ ERROR-charon-manager ]"
WARN="[ WARN-charon-manager ]"
INFO="[ INFO-charon-manager ]"

CHARON_P2P_EXTERNAL_HOSTNAME=${_DAPPNODE_GLOBAL_DOMAIN}
ETH2_CLIENT_DNS="https://teku.obol-goerli-etherfi.dappnode:3500"
GENESIS_VALIDATORS_ROOT=0x043db0d9a83813551ee2f33450d23797757d430911a9320530ad8a0eabc43efb
KEY_IMPORT_HEADER="{ \"keystores\": [], \"passwords\": [], \"slashing_protection\": {\"metadata\":{\"interchange_format_version\":\"5\",\"genesis_validators_root\":\"$GENESIS_VALIDATORS_ROOT\"},\"data\":[]}}"

CHARON_DATA_DIR=/opt/charon/.charon
ENR_PRIVATE_KEY=$CHARON_DATA_DIR/charon-enr-private-key
CHARON_CLUSTER_LOCK_FILE=$CHARON_DATA_DIR/charon-cluster.lock
DEPOSIT_DATA_FILE=$CHARON_DATA_DIR/deposit-data.json
VALIDATOR_KEYS_DIR=$CHARON_DATA_DIR/validator_keys

TEKU_SECURITY_DIR=/opt/charon/teku/security
TEKU_CERT_FILE=$TEKU_SECURITY_DIR/cert/teku_client_keystore.p12
TEKU_CERT_PASS=$(cat $TEKU_SECURITY_DIR/cert/teku_keystore_password.txt)
TEKU_API_TOKEN=$(cat $TEKU_SECURITY_DIR/validator-api-bearer)


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

# function that handles the import of the validatorss
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
    -k --cert-type P12 --cert /${TEKU_CERT_FILE}:${TEKU_CERT_PASS} \
    -w "HTTPSTATUS:%{http_code}" \
    -d @"${REQUEST_BODY_FILE}" \
    --retry 30 \
    --retry-delay 3 \
    --retry-connrefused \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${TEKU_API_TOKEN}" \
    "${ETH2_CLIENT_DNS}"/eth/v1/keystores) ||
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
  # Check if the cluster definition file exists
  if [ -f "$CHARON_LOCK_FILE" ]; then
    exec charon run --private-key-file=$CHARON_DATA_DIR/charon-enr-private-key --lock-file=$CHARON_LOCK_FILE
  else
    echo "${ERROR} cluster definition file does not exist"
    sleep 300 # Wait 5 minutes to avoid restarting the container
    exit 1
  fi
}

########
# MAIN #
########

echo "${INFO} get the current beacon chain in use"
get_beacon_node_endpoint
echo "${INFO} importing keys into validator..."
import_key
echo "${INFO} starting charon.."
run_charon
