#!/bin/bash
set -euo pipefail
source /tmp/cloud_init_vars

echo "Deploying keys and certificates."

# Deploy the osbuild CA certificate.
base64 -d - <<< ${OSBUILD_CA_CERT} > ${COMPOSER_DIR}/ca-crt.pem

# Deploy the composer key.
/usr/local/bin/aws secretsmanager get-secret-value \
  --endpoint-url ${SECRETS_MANAGER_ENDPOINT_URL} \
  --secret-id ${COMPOSER_SSL_KEYS_ARN} | jq -r ".SecretString" > /tmp/composer_keys.json
jq -r ".composer_key" /tmp/composer_keys.json | base64 -d - > ${COMPOSER_DIR}/composer-key.pem
jq -r ".composer_crt" /tmp/composer_keys.json | base64 -d - > ${COMPOSER_DIR}/composer-crt.pem
rm -f /tmp/composer_keys.json
