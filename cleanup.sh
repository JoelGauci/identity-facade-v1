#!/bin/sh
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ==============================================================================
# Script: cleanup.sh
# Purpose: Strictly POSIX-compliant cleanup script using apigeecli
#          (https://github.com/apigee/apigeecli) to remove all Apigee resources
#          provisioned by pipeline.sh (Developer App, API Product, Developer,
#          API Proxy, Environment KVM, and Environment Cache).
# ==============================================================================

set -e

echo "===================================================================="
echo "Starting Apigee Identity Facade Cleanup via apigeecli (cleanup.sh)"
echo "===================================================================="

# ==============================================================================
# Helper: Ensure apigeecli is available in PATH
# ==============================================================================
ensure_apigeecli() {
    if ! command -v apigeecli >/dev/null 2>&1; then
        if [ -x "$HOME/.apigeecli/bin/apigeecli" ]; then
            PATH="$PATH:$HOME/.apigeecli/bin"
            export PATH
        else
            echo "[INFO] apigeecli not found in PATH. Installing latest apigeecli..."
            curl -sL https://raw.githubusercontent.com/apigee/apigeecli/main/downloadLatest.sh | sh
            PATH="$PATH:$HOME/.apigeecli/bin"
            export PATH
        fi
    fi
}

APIGEE_X_ORG="${APIGEE_X_ORG:-${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}}"
APIGEE_X_ENV="${APIGEE_X_ENV:-$APIGEE_ENV}"

if [ -z "$APIGEE_X_ORG" ] || [ -z "$APIGEE_X_ENV" ]; then
    echo "[ERROR] Mandatory environment variables APIGEE_X_ORG and APIGEE_X_ENV must be set."
    echo "Usage:"
    echo "  export APIGEE_X_ORG=\"<your-apigee-org>\""
    echo "  export APIGEE_X_ENV=\"<your-apigee-env>\""
    echo "  ./cleanup.sh"
    exit 1
fi

ensure_apigeecli

APIGEE_TOKEN="${APIGEE_TOKEN:-$(gcloud auth application-default print-access-token 2>/dev/null || gcloud auth print-access-token 2>/dev/null)}"

echo "[INFO] Target Organization: $APIGEE_X_ORG | Target Environment: $APIGEE_X_ENV"

# 1. Delete Developer App (identityApp)
echo ""
echo "--- Step 1/6: Deleting Developer App (identityApp) ---"
apigeecli apps delete \
    --name "identityApp" \
    --id "janedoe@example.com" \
    --org "$APIGEE_X_ORG" \
    --token "$APIGEE_TOKEN" \
    --disable-check >/dev/null 2>&1 || \
    echo "[INFO] Developer App identityApp already deleted or does not exist."

# 2. Delete API Product (IdentityFacade)
echo ""
echo "--- Step 2/6: Deleting API Product (IdentityFacade) ---"
apigeecli products delete \
    --name "IdentityFacade" \
    --org "$APIGEE_X_ORG" \
    --token "$APIGEE_TOKEN" \
    --disable-check >/dev/null 2>&1 || \
    echo "[INFO] API Product IdentityFacade already deleted or does not exist."

# 3. Delete Developer (janedoe@example.com)
echo ""
echo "--- Step 3/6: Deleting Developer (janedoe@example.com) ---"
apigeecli developers delete \
    --email "janedoe@example.com" \
    --org "$APIGEE_X_ORG" \
    --token "$APIGEE_TOKEN" \
    --disable-check >/dev/null 2>&1 || \
    echo "[INFO] Developer janedoe@example.com already deleted or does not exist."

# 4. Undeploy and Delete API Proxy (identity-facade-v1)
echo ""
echo "--- Step 4/6: Undeploying and Deleting API Proxy (identity-facade-v1) ---"
apigeecli apis undeploy \
    --name "identity-facade-v1" \
    --env "$APIGEE_X_ENV" \
    --org "$APIGEE_X_ORG" \
    --token "$APIGEE_TOKEN" \
    --disable-check >/dev/null 2>&1 || \
    echo "[INFO] API Proxy identity-facade-v1 was not deployed in $APIGEE_X_ENV."

apigeecli apis delete \
    --name "identity-facade-v1" \
    --org "$APIGEE_X_ORG" \
    --token "$APIGEE_TOKEN" \
    --disable-check >/dev/null 2>&1 || \
    echo "[INFO] API Proxy identity-facade-v1 already deleted or does not exist."

# 5. Delete Environment KVM (idpConfigIdentityProxy)
echo ""
echo "--- Step 5/6: Deleting Environment KVM (idpConfigIdentityProxy) ---"
apigeecli kvms delete \
    --name "idpConfigIdentityProxy" \
    --env "$APIGEE_X_ENV" \
    --org "$APIGEE_X_ORG" \
    --token "$APIGEE_TOKEN" \
    --disable-check >/dev/null 2>&1 || \
    echo "[INFO] KVM idpConfigIdentityProxy already deleted or does not exist."

# 6. Delete Environment Cache (IDP_JWKS_CACHE)
echo ""
echo "--- Step 6/6: Deleting Environment Cache (IDP_JWKS_CACHE) ---"
apigeecli cache delete \
    --name "IDP_JWKS_CACHE" \
    --env "$APIGEE_X_ENV" \
    --org "$APIGEE_X_ORG" \
    --token "$APIGEE_TOKEN" \
    --disable-check >/dev/null 2>&1 || \
    echo "[INFO] Cache IDP_JWKS_CACHE already deleted or does not exist."

echo ""
echo "===================================================================="
echo "SUCCESS: Apigee Identity Facade Cleanup Completed!"
echo "===================================================================="
