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
ETH2_CLIENT_DNS="https://teku.obol-distributed-validator-goerli.dappnode:3500"
PRIVATE_KEY=/opt/charon/.charon/charon-enr-private-key
ENR_FILE=/opt/charon/.charon/enr
GENESIS_VALIDATORS_ROOT=0x043db0d9a83813551ee2f33450d23797757d430911a9320530ad8a0eabc43efb
KEY_IMPORT_HEADER="{ \"keystores\": [], \"passwords\": [], \"slashing_protection\": {\"metadata\":{\"interchange_format_version\":\"5\",\"genesis_validators_root\":\"$GENESIS_VALIDATORS_ROOT\"},\"data\":[]}}"
CURRENT_DEFINITION=/opt/charon/.charon/definition_file_hash.txt

if [ ! -z "$DEFINITION_FILE" ]; then
  #Get the definition file from the environment variable and the hash
  DEFINITION_FILE_HASH=$(echo $DEFINITION_FILE | sed 's|https://api.obol.tech/dv/||g' | tr -d "/")
  if [[ $DEFINITION_FILE != https* ]]; then
    DEFINITION_FILE=https://api.obol.tech/dv/$DEFINITION_FILE_HASH
  fi

  # Create the directory where the files will be stored
  mkdir -p /opt/charon/.charon/$DEFINITION_FILE_HASH

  CHARON_LOCK_FILE=/opt/charon/.charon/$DEFINITION_FILE_HASH/cluster-lock.json
  REQUEST_BODY_FILE=/opt/charon/.charon/$DEFINITION_FILE_HASH/request-body.json
  CHARON_DATA_DIR=/opt/charon/.charon/$DEFINITION_FILE_HASH
  VALIDATOR_KEYS_DIR=/opt/charon/.charon/$DEFINITION_FILE_HASH/validator_keys

  echo $DEFINITION_FILE_HASH >$CURRENT_DEFINITION
elif [ -f "$CURRENT_DEFINITION" ]; then
  DEFINITION_FILE_HASH=$(cat $CURRENT_DEFINITION)
  CHARON_LOCK_FILE=/opt/charon/.charon/$DEFINITION_FILE_HASH/cluster-lock.json
  REQUEST_BODY_FILE=/opt/charon/.charon/$DEFINITION_FILE_HASH/request-body.json
  CHARON_DATA_DIR=/opt/charon/.charon/$DEFINITION_FILE_HASH
  VALIDATOR_KEYS_DIR=/opt/charon/.charon/$DEFINITION_FILE_HASH/validator_keys
fi

#############
# FUNCTIONS #
#############

# Get the current beacon chain in use
# Assign proper value to _DAPPNODE_GLOBAL_CONSENSUS_CLIENT_PRATER.
function getBeaconNodeEndpoint() {
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
function getENR() {
  # Check if ENR file exists and create it if it does not
  if [[ ! -f "$PRIVATE_KEY" ]]; then
    echo "${INFO} ENR does not exist, creating it..."
    charon create enr | tee /opt/charon/.charon/create_enr.txt
  fi
  # Get ENR from file
  if [[ ! -f "$ENR" ]]; then
    grep "enr:" /opt/charon/.charon/create_enr.txt | cut -d " " -f 2 >$ENR_FILE
    ENR=$(cat $ENR_FILE)
    echo "${INFO} ENR: ${ENR}"
    echo "${INFO} Publishing ENR to dappmanager..."
    postENR2Dappmanager
  else
    echo "${ERROR} it was not possible to get the ENR file"
    sleep 300 # Wait 5 minutes to avoid restarting the container
    exit 1
  fi
}

# function to be post the ENR to dappmanager
function postENR2Dappmanager() {
  # Post ENR to dappmanager
  curl --connect-timeout 5 \
    --max-time 10 \
    --silent \
    --retry 5 \
    --retry-delay 0 \
    --retry-max-time 40 \
    -X POST "http://my.dappnode/data-send?key=ENR&data=${ENR}" ||
    {
      echo "[ERROR] failed to post ENR to dappmanager"
      exit 1
    }
}

# function to check if DKG is already done and if not, wait for it
function checkDKG() {
  # Check if DKG is already done
  # by checking that DEFINITION_FILE exits but there is no CHARON_LOCK_FILE
  if [ ! -z "$DEFINITION_FILE" ] && [ ! -f "$CHARON_LOCK_FILE" ]; then
    cp $PRIVATE_KEY $CHARON_DATA_DIR
    cp $ENR_FILE $CHARON_DATA_DIR
    echo "${INFO} waiting for DKG ceremony..."
    charon dkg --definition-file=$DEFINITION_FILE --data-dir=$CHARON_DATA_DIR
  elif [ -z "$DEFINITION_FILE" ] && [ ! -f "$CHARON_LOCK_FILE" ]; then
    echo "${WARN} waiting for definition file to start dkg ceremony..."
    sleep 300 # Wait 5 minutes to avoid restarting the container
    exit 1
  fi
}

# function that handles the import of the validatorss
function importKey() {
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
    -k --cert-type P12 --cert /teku_client_keystore.p12:dappnode \
    -w "HTTPSTATUS:%{http_code}" \
    -d @"${REQUEST_BODY_FILE}" \
    --retry 30 \
    --retry-delay 3 \
    --retry-connrefused \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer cd4892ca35d2f5d3e2301a65fc7aa660" \
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

function runCharon() {
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
getBeaconNodeEndpoint
echo "${INFO} getting the ENR..."
getENR
echo "${INFO} checking for DKG ceremony..."
checkDKG
echo "${INFO} importing keys into validator..."
importKey
echo "${INFO} starting charon.."
runCharon
