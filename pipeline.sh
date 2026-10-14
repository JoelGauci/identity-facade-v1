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
# Script: pipeline.sh
# Purpose: Modernized POSIX-compliant deployment pipeline for the Apigee
#          Identity Facade (identity-facade-v1) using apigeecli (https://github.com/apigee/apigeecli).
#          Supports OAuth 2.0, OIDC, PKCE (enabled by default), and RFC 8693 Token Exchange.
# ==============================================================================

set -e

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 || exit 1 ; pwd -P )"

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

# ==============================================================================
# Helper: Extract hostname and URI path from a full https:// URL
# ==============================================================================
extract_hostname() {
    url_no_proto="${1#https://}"
    url_no_proto="${url_no_proto#http://}"
    printf '%s' "${url_no_proto%%/*}"
}

extract_uri_path() {
    url_no_proto="${1#https://}"
    url_no_proto="${url_no_proto#http://}"
    printf '%s' "${url_no_proto#*/}"
}

# ==============================================================================
# Function: set_idp_env_var
# Parses the upstream IdP OIDC Discovery Document (/.well-known/openid-configuration)
# ==============================================================================
set_idp_env_var() {
    idp_discovery_document_uri="$1"
    callback_url="$2"

    echo "[INFO] Fetching OIDC Discovery Document from: $idp_discovery_document_uri"
    response=$(curl --silent -k -fsSL -X GET -H "Accept: application/json" "$idp_discovery_document_uri")

    if [ -z "$response" ] || [ "$(printf '%s' "$response" | jq -r '.issuer // empty')" = "" ]; then
        echo "[ERROR] Failed to parse valid OIDC Discovery Document from $idp_discovery_document_uri"
        printf '%s\n' "$response"
        exit 1
    fi

    issuer_url=$(printf '%s' "$response" | jq -r '.issuer')
    authorization_endpoint=$(printf '%s' "$response" | jq -r '.authorization_endpoint')
    token_endpoint=$(printf '%s' "$response" | jq -r '.token_endpoint')
    jwks_uri=$(printf '%s' "$response" | jq -r '.jwks_uri')
    userinfo_endpoint=$(printf '%s' "$response" | jq -r '.userinfo_endpoint')

    TEST_IDP_ISSUER="$issuer_url"
    export TEST_IDP_ISSUER

    TEST_IDP_APIGEE_REDIRECT_URI="$callback_url"
    export TEST_IDP_APIGEE_REDIRECT_URI

    TEST_IDP_AZ_HOSTNAME=$(extract_hostname "$authorization_endpoint")
    export TEST_IDP_AZ_HOSTNAME
    TEST_IDP_AZ_URI=$(extract_uri_path "$authorization_endpoint")
    export TEST_IDP_AZ_URI

    TEST_IDP_TOKEN_HOSTNAME=$(extract_hostname "$token_endpoint")
    export TEST_IDP_TOKEN_HOSTNAME
    TEST_IDP_TOKEN_URI=$(extract_uri_path "$token_endpoint")
    export TEST_IDP_TOKEN_URI

    TEST_IDP_JWKS_HOSTNAME=$(extract_hostname "$jwks_uri")
    export TEST_IDP_JWKS_HOSTNAME
    TEST_IDP_JWKS_URI=$(extract_uri_path "$jwks_uri")
    export TEST_IDP_JWKS_URI

    TEST_IDP_USERINFO_HOSTNAME=$(extract_hostname "$userinfo_endpoint")
    export TEST_IDP_USERINFO_HOSTNAME
    TEST_IDP_USERINFO_URI=$(extract_uri_path "$userinfo_endpoint")
    export TEST_IDP_USERINFO_URI

    TEST_IDP_APIGEE_CLIENT_ID="${TEST_IDP_APIGEE_CLIENT_ID:-dummy-client_id-apigee123}"
    export TEST_IDP_APIGEE_CLIENT_ID

    TEST_IDP_APIGEE_CLIENT_SECRET="${TEST_IDP_APIGEE_CLIENT_SECRET:-dummy-client_secret_apigee456}"
    export TEST_IDP_APIGEE_CLIENT_SECRET

    APP_REDIRECT_URI="${APP_REDIRECT_URI:-https://mocktarget.apigee.net/echo}"
    export APP_REDIRECT_URI
}

# ==============================================================================
# Function: set_functional_test_env_var
# Sets consumer key/secret and PKCE S256 challenge/verifier test parameters
# ==============================================================================
set_functional_test_env_var() {
    TEST_APP_CONSUMER_KEY="${TEST_APP_CONSUMER_KEY:-xkey-$1}"
    export TEST_APP_CONSUMER_KEY
    TEST_APP_CONSUMER_SECRET="${TEST_APP_CONSUMER_SECRET:-xsecret}"
    export TEST_APP_CONSUMER_SECRET

    # PKCE test variables (Challenge method: S256, SHA-256 of 'iloveapis1234567890')
    TEST_APP_PKCE_CODE_CHALLENGE="hoLP4vNbBccHkhNAbk_jbyLhlGwgeoRyo53A-Luiirg"
    export TEST_APP_PKCE_CODE_CHALLENGE
    TEST_APP_PKCE_CODE_VERIFIER="iloveapis1234567890"
    export TEST_APP_PKCE_CODE_VERIFIER
}

# ==============================================================================
# Function: set_pkce_config
# Updates AM-SetPKCEMode.xml with the configured PKCE mode (true by default)
# ==============================================================================
set_pkce_config() {
    pkce_mode="$1"
    echo "[INFO] Setting PKCE enforcement mode (flow.pkce.enabled) to: $pkce_mode"
    sed "s|@IsPKCEEnabled@|$pkce_mode|g" \
        "$SCRIPTPATH/AM-SetPKCEMode.template.xml" > "$SCRIPTPATH/apiproxy/policies/AM-SetPKCEMode.xml"
}

# ==============================================================================
# Function: deploy_with_apigeecli
# Provisions KVM, API Proxy, Modernized API Product (operationGroup), Developer,
# and Developer App using apigeecli
# ==============================================================================
deploy_with_apigeecli() {
    org="$1"
    env="$2"
    token="$3"

    ensure_apigeecli

    # 1. Create and Populate Environment KVM (idpConfigIdentityProxy)
    echo "[INFO] Step 1/5: Configuring Environment KVM (idpConfigIdentityProxy) in $env via apigeecli..."
    apigeecli kvms create \
        --name "idpConfigIdentityProxy" \
        --env "$env" \
        --org "$org" \
        --token "$token" \
        --disable-check >/dev/null 2>&1 || \
        echo "[INFO] KVM idpConfigIdentityProxy already exists."

    upsert_kvm_entry() {
        k_key="$1"
        k_val="$2"
        apigeecli kvms entries create \
            --map "idpConfigIdentityProxy" \
            --key "$k_key" \
            --value "$k_val" \
            --env "$env" \
            --org "$org" \
            --token "$token" \
            --disable-check >/dev/null 2>&1 || \
        apigeecli kvms entries update \
            --map "idpConfigIdentityProxy" \
            --key "$k_key" \
            --value "$k_val" \
            --env "$env" \
            --org "$org" \
            --token "$token" \
            --disable-check >/dev/null 2>&1
    }

    upsert_kvm_entry "idp.issuer" "$TEST_IDP_ISSUER"
    upsert_kvm_entry "idp.az.hostname" "$TEST_IDP_AZ_HOSTNAME"
    upsert_kvm_entry "idp.az.uri" "$TEST_IDP_AZ_URI"
    upsert_kvm_entry "idp.token.hostname" "$TEST_IDP_TOKEN_HOSTNAME"
    upsert_kvm_entry "idp.token.uri" "$TEST_IDP_TOKEN_URI"
    upsert_kvm_entry "idp.jwks.hostname" "$TEST_IDP_JWKS_HOSTNAME"
    upsert_kvm_entry "idp.jwks.uri" "$TEST_IDP_JWKS_URI"
    upsert_kvm_entry "idp.userinfo.hostname" "$TEST_IDP_USERINFO_HOSTNAME"
    upsert_kvm_entry "idp.userinfo.uri" "$TEST_IDP_USERINFO_URI"
    upsert_kvm_entry "idp.apigee.client_id" "$TEST_IDP_APIGEE_CLIENT_ID"
    upsert_kvm_entry "idp.apigee.client_secret" "$TEST_IDP_APIGEE_CLIENT_SECRET"
    upsert_kvm_entry "idp.apigee.redirect_uri" "$TEST_IDP_APIGEE_REDIRECT_URI"

    # 2. Deploy API Proxy Bundle (identity-facade-v1)
    echo "[INFO] Step 2/5: Deploying API Proxy (identity-facade-v1) to $env via apigeecli..."
    apigeecli apis create bundle \
        --name "identity-facade-v1" \
        --proxy-folder "$SCRIPTPATH/apiproxy" \
        --env "$env" \
        --org "$org" \
        --token "$token" \
        --ovr \
        --wait \
        --disable-check

    # 3. Create / Update Modernized API Product (IdentityFacade with operationGroup)
    echo "[INFO] Step 3/5: Provisioning Modernized API Product (IdentityFacade) via apigeecli..."
    ops_file=$(mktemp)
    cat <<EOF > "$ops_file"
{
  "operationConfigType": "proxy",
  "operationConfigs": [
    {
      "apiSource": "identity-facade-v1",
      "operations": [
        {
          "resource": "/authorize",
          "methods": ["GET"]
        }
      ],
      "quota": {}
    },
    {
      "apiSource": "identity-facade-v1",
      "operations": [
        {
          "resource": "/callback",
          "methods": ["GET"]
        }
      ],
      "quota": {}
    },
    {
      "apiSource": "identity-facade-v1",
      "operations": [
        {
          "resource": "/token",
          "methods": ["POST"]
        }
      ],
      "quota": {}
    },
    {
      "apiSource": "identity-facade-v1",
      "operations": [
        {
          "resource": "/protected",
          "methods": ["GET"]
        }
      ],
      "quota": {}
    },
    {
      "apiSource": "identity-facade-v1",
      "operations": [
        {
          "resource": "/**",
          "methods": ["GET", "POST"]
        }
      ],
      "quota": {}
    }
  ]
}
EOF

    if apigeecli products get --name "IdentityFacade" --org "$org" --token "$token" --disable-check >/dev/null 2>&1; then
        echo "[INFO] Updating existing API Product IdentityFacade..."
        apigeecli products update \
            --name "IdentityFacade" \
            --display-name "Identity Facade" \
            --desc "OAuth 2.0, OIDC and RFC 8693 Token Exchange Identity Facade Product" \
            --opgrp "$ops_file" \
            --envs "$env" \
            --approval auto \
            --attrs "access=public" \
            --org "$org" \
            --token "$token" \
            --disable-check >/dev/null
    else
        echo "[INFO] Creating new API Product IdentityFacade..."
        apigeecli products create \
            --name "IdentityFacade" \
            --display-name "Identity Facade" \
            --desc "OAuth 2.0, OIDC and RFC 8693 Token Exchange Identity Facade Product" \
            --opgrp "$ops_file" \
            --envs "$env" \
            --approval auto \
            --attrs "access=public" \
            --org "$org" \
            --token "$token" \
            --disable-check >/dev/null
    fi
    rm -f "$ops_file"

    # 4. Create Developer (janedoe@example.com)
    echo "[INFO] Step 4/5: Provisioning Developer (janedoe@example.com) via apigeecli..."
    apigeecli developers create \
        --user "janedoe" \
        --email "janedoe@example.com" \
        --first "Jane" \
        --last "Doe" \
        --org "$org" \
        --token "$token" \
        --disable-check >/dev/null 2>&1 || \
        echo "[INFO] Developer janedoe@example.com already exists."

    # Ensure Environment Cache (IDP_JWKS_CACHE) exists
    apigeecli cache create \
        --name "IDP_JWKS_CACHE" \
        --env "$env" \
        --org "$org" \
        --token "$token" \
        --disable-check >/dev/null 2>&1 || true

    # 5. Create / Update Developer App (identityApp) & Custom Credentials
    echo "[INFO] Step 5/5: Provisioning Developer App (identityApp) and credentials via apigeecli..."
    app_attrs="displayName=identity App,redirection_uris=$APP_REDIRECT_URI,redirect_uris=$APP_REDIRECT_URI,idp_client_id=$TEST_IDP_APIGEE_CLIENT_ID,idp_client_secret=$TEST_IDP_APIGEE_CLIENT_SECRET,idp_redirect_uri=$TEST_IDP_APIGEE_REDIRECT_URI"

    if ! apigeecli apps create \
        --name "identityApp" \
        --email "janedoe@example.com" \
        --callback "$APP_REDIRECT_URI" \
        --prods "IdentityFacade" \
        --attrs "$app_attrs" \
        --org "$org" \
        --token "$token" \
        --disable-check >/dev/null 2>&1; then
        echo "[INFO] Developer App identityApp already exists. Updating..."
        apigeecli apps update \
            --name "identityApp" \
            --email "janedoe@example.com" \
            --callback "$APP_REDIRECT_URI" \
            --prods "IdentityFacade" \
            --attrs "$app_attrs" \
            --org "$org" \
            --token "$token" \
            --disable-check >/dev/null
    fi

    # Register custom Consumer Key & Consumer Secret on identityApp and bind to IdentityFacade
    apigeecli apps keys create \
        --name "identityApp" \
        --dev "janedoe@example.com" \
        --key "$TEST_APP_CONSUMER_KEY" \
        --secret "$TEST_APP_CONSUMER_SECRET" \
        --prods "IdentityFacade" \
        --org "$org" \
        --token "$token" \
        --disable-check >/dev/null 2>&1 || true
}

# ==============================================================================
# Function: generate_authz_url
# Prints the comprehensive deployment summary, IdP callback requirements,
# KVM & Developer App attributes, Authorization URL, and ready-to-run curl
# commands for Authorization Code + PKCE, Protected API, Refresh Token, and
# RFC 8693 Token Exchange.
# ==============================================================================
generate_authz_url() {
    HOST="$1"
    CLIENT_KEY="$2"
    CHALLENGE="$3"
    PKCE_FLAG="$4"

    BASE_PATH="/v1/oauth20"
    AZ_URI="/authorize"
    CLIENT_ID="?client_id=$CLIENT_KEY"
    RESPONSE_TYPE="&response_type=code"
    SCOPE="&scope=openid%20email%20profile"
    STATE="&state=abcd-1234"
    REDIRECT_URI="&redirect_uri=$APP_REDIRECT_URI"

    if [ "$PKCE_FLAG" = "true" ]; then
        CODE_CHALLENGE_METHOD="&code_challenge_method=S256"
        CODE_CHALLENGE="&code_challenge=$CHALLENGE"
    else
        CODE_CHALLENGE_METHOD=""
        CODE_CHALLENGE=""
    fi

    printf "\n"
    printf "================================================================================\n"
    printf "  Apigee Identity Facade (identity-facade-v1) - Deployment Summary\n"
    printf "================================================================================\n\n"

    # 1. Upstream IdP Callback & Client Configuration
    printf "1. UPSTREAM OIDC IdP CONFIGURATION (e.g., Keycloak / Okta / Entra ID)\n"
    printf -- "--------------------------------------------------------------------------------\n"
    printf "Ensure the following Redirect URI (Valid Redirect URIs) is registered on your\n"
    printf "upstream OIDC IdP client ('%s'):\n\n" "$TEST_IDP_APIGEE_CLIENT_ID"
    printf "  - Apigee Callback URL (IdP Redirect URI) : %s\n" "$TEST_IDP_APIGEE_REDIRECT_URI"
    printf "  - Upstream IdP Client ID                 : %s\n" "$TEST_IDP_APIGEE_CLIENT_ID"
    printf "  - OIDC Discovery Document                : %s\n\n" "$DISCOVERY_DOCUMENT_URI"

    # 2. Extracted KVM Endpoints & Developer App Configuration
    printf "2. PROVISIONED APIGEE RESOURCES & EXTRACTED KVM CONFIGURATION\n"
    printf -- "--------------------------------------------------------------------------------\n"
    printf "Target Apigee Environment:\n"
    printf "  - Organization / Environment             : %s / %s\n" "$APIGEE_X_ORG" "$APIGEE_X_ENV"
    printf "  - Environment Group Hostname             : %s\n" "$HOST"
    printf "  - API Proxy / BasePath                   : identity-facade-v1 (%s)\n" "$BASE_PATH"
    printf "  - API Product                            : IdentityFacade\n"
    printf "  - Environment Cache                      : IDP_JWKS_CACHE\n\n"

    printf "Environment KVM ('idpConfigIdentityProxy') Entries:\n"
    printf "  - idp.issuer                             : %s\n" "$TEST_IDP_ISSUER"
    printf "  - idp.az.hostname / idp.az.uri           : %s / %s\n" "$TEST_IDP_AZ_HOSTNAME" "$TEST_IDP_AZ_URI"
    printf "  - idp.token.hostname / idp.token.uri     : %s / %s\n" "$TEST_IDP_TOKEN_HOSTNAME" "$TEST_IDP_TOKEN_URI"
    printf "  - idp.jwks.hostname / idp.jwks.uri       : %s / %s\n" "$TEST_IDP_JWKS_HOSTNAME" "$TEST_IDP_JWKS_URI"
    printf "  - idp.userinfo.hostname / idp.userinfo.uri: %s / %s\n\n" "$TEST_IDP_USERINFO_HOSTNAME" "$TEST_IDP_USERINFO_URI"

    printf "Developer App ('identityApp' - Owner: janedoe@example.com):\n"
    printf "  - Apigee Client ID (Consumer Key)        : %s\n" "$CLIENT_KEY"
    printf "  - Apigee Client Secret (Consumer Secret) : %s\n" "$TEST_APP_CONSUMER_SECRET"
    printf "  - Allowed Client App Redirect URI        : %s\n" "$APP_REDIRECT_URI"
    printf "  - Custom Attribute 'idp_client_id'       : %s\n" "$TEST_IDP_APIGEE_CLIENT_ID"
    printf "  - Custom Attribute 'idp_redirect_uri'    : %s\n" "$TEST_IDP_APIGEE_REDIRECT_URI"
    printf "  - PKCE Enforcement Mode                  : %s\n" "$PKCE_FLAG"
    if [ "$PKCE_FLAG" = "true" ]; then
        printf "  - PKCE Code Challenge (S256)             : %s\n" "$CHALLENGE"
        printf "  - PKCE Code Verifier                     : %s\n" "$TEST_APP_PKCE_CODE_VERIFIER"
    fi
    printf "\n"

    # 3. Step 0: Export Test Session Environment Variables
    printf "3. STEP 0: EXPORT SESSION ENVIRONMENT VARIABLES (COPY/PASTE ONCE)\n"
    printf -- "--------------------------------------------------------------------------------\n"
    printf "Copy/paste these exports into your terminal before running the curl commands:\n\n"
    printf "export APIGEE_HOST=\"%s\"\n" "$HOST"
    printf "export CLIENT_ID=\"%s\"\n" "$CLIENT_KEY"
    printf "export CLIENT_SECRET=\"%s\"\n" "$TEST_APP_CONSUMER_SECRET"
    printf "export REDIRECT_URI=\"%s\"\n" "$APP_REDIRECT_URI"
    printf "export SCOPE=\"openid email profile\"\n"
    if [ "$PKCE_FLAG" = "true" ]; then
        printf "export PKCE_CODE_CHALLENGE=\"%s\"\n" "$CHALLENGE"
        printf "export PKCE_CODE_VERIFIER=\"%s\"\n" "$TEST_APP_PKCE_CODE_VERIFIER"
    fi
    printf "export TARGET_AUDIENCE=\"%s\"\n" "$TEST_IDP_APIGEE_CLIENT_ID"
    printf "export EXCHANGE_SCOPE=\"openid email\"\n\n"

    # 4. Step 1: Authorization URL (Browser) & Export APIGEE_AUTH_CODE
    printf "4. STEP 1: INITIATE AUTHORIZATION CODE FLOW (BROWSER)\n"
    printf -- "--------------------------------------------------------------------------------\n"
    printf "a) Open the following Authorization URL in your browser and log in to your IdP:\n\n"
    printf "https://%s%s%s%s%s%s%s%s%s%s\n\n" \
        "$HOST" \
        "$BASE_PATH" \
        "$AZ_URI" \
        "$CLIENT_ID" \
        "$RESPONSE_TYPE" \
        "$SCOPE" \
        "$STATE" \
        "$REDIRECT_URI" \
        "$CODE_CHALLENGE_METHOD" \
        "$CODE_CHALLENGE"
    printf "b) Intermediate Environment Variable to Export after Browser Redirect:\n"
    printf "   Copy the 'code' query parameter from the redirect URL (%s?code=...) and run:\n\n" "$APP_REDIRECT_URI"
    printf "export APIGEE_AUTH_CODE=\"<PASTE_CODE_FROM_BROWSER_HERE>\"\n\n"

    # 5. Step 2: Token Issuance (Authorization Code + PKCE)
    printf "5. STEP 2: EXCHANGE AUTHORIZATION CODE FOR APIGEE TOKENS (POST /v1/oauth20/token)\n"
    printf -- "--------------------------------------------------------------------------------\n"
    printf "Copy/paste this block as-is (uses \$APIGEE_AUTH_CODE and \$SCOPE, and automatically\n"
    printf "exports \$APIGEE_ACCESS_TOKEN and \$APIGEE_REFRESH_TOKEN for the next steps):\n\n"
    if [ "$PKCE_FLAG" = "true" ]; then
        printf "TOKEN_RESPONSE=\$(curl -s -X POST \"https://\${APIGEE_HOST}%s/token\" \\\\\n" "$BASE_PATH"
        printf "  -H \"Authorization: Basic \$(printf '%%s:%%s' \"\${CLIENT_ID}\" \"\${CLIENT_SECRET}\" | base64 | tr -d '\\\\n')\" \\\\\n"
        printf "  -H \"Content-Type: application/x-www-form-urlencoded\" \\\\\n"
        printf "  -d \"grant_type=authorization_code\" \\\\\n"
        printf "  -d \"redirect_uri=\${REDIRECT_URI}\" \\\\\n"
        printf "  -d \"scope=\${SCOPE}\" \\\\\n"
        printf "  -d \"code=\${APIGEE_AUTH_CODE}\" \\\\\n"
        printf "  -d \"code_verifier=\${PKCE_CODE_VERIFIER}\")\n"
    else
        printf "TOKEN_RESPONSE=\$(curl -s -X POST \"https://\${APIGEE_HOST}%s/token\" \\\\\n" "$BASE_PATH"
        printf "  -H \"Authorization: Basic \$(printf '%%s:%%s' \"\${CLIENT_ID}\" \"\${CLIENT_SECRET}\" | base64 | tr -d '\\\\n')\" \\\\\n"
        printf "  -H \"Content-Type: application/x-www-form-urlencoded\" \\\\\n"
        printf "  -d \"grant_type=authorization_code\" \\\\\n"
        printf "  -d \"redirect_uri=\${REDIRECT_URI}\" \\\\\n"
        printf "  -d \"scope=\${SCOPE}\" \\\\\n"
        printf "  -d \"code=\${APIGEE_AUTH_CODE}\")\n"
    fi
    printf "echo \"\$TOKEN_RESPONSE\" | jq .\n"
    printf "export APIGEE_ACCESS_TOKEN=\$(echo \"\$TOKEN_RESPONSE\" | jq -r '.access_token')\n"
    printf "export APIGEE_REFRESH_TOKEN=\$(echo \"\$TOKEN_RESPONSE\" | jq -r '.refresh_token')\n\n"

    # 6. Step 3: Protected Endpoint & Refresh Token
    printf "6. STEP 3: CALL PROTECTED ENDPOINT & REFRESH TOKEN (ZERO-EDIT COPY/PASTE)\n"
    printf -- "--------------------------------------------------------------------------------\n"
    printf "a) Call Protected Endpoint (uses \$APIGEE_ACCESS_TOKEN):\n\n"
    printf "curl -i -X GET \"https://\${APIGEE_HOST}%s/protected\" \\\\\n" "$BASE_PATH"
    printf "  -H \"Authorization: Bearer \${APIGEE_ACCESS_TOKEN}\"\n\n"

    printf "b) Refresh Opaque Access Token (uses \$APIGEE_REFRESH_TOKEN and updates tokens):\n\n"
    printf "REFRESH_RESPONSE=\$(curl -s -X POST \"https://\${APIGEE_HOST}%s/token\" \\\\\n" "$BASE_PATH"
    printf "  -H \"Content-Type: application/x-www-form-urlencoded\" \\\\\n"
    printf "  -d \"grant_type=refresh_token\" \\\\\n"
    printf "  -d \"client_id=\${CLIENT_ID}\" \\\\\n"
    printf "  -d \"client_secret=\${CLIENT_SECRET}\" \\\\\n"
    printf "  -d \"refresh_token=\${APIGEE_REFRESH_TOKEN}\")\n"
    printf "echo \"\$REFRESH_RESPONSE\" | jq .\n"
    printf "export APIGEE_ACCESS_TOKEN=\$(echo \"\$REFRESH_RESPONSE\" | jq -r '.access_token')\n"
    printf "export APIGEE_REFRESH_TOKEN=\$(echo \"\$REFRESH_RESPONSE\" | jq -r '.refresh_token')\n\n"

    # 7. Step 4: RFC 8693 Token Exchange
    printf "7. STEP 4: OAUTH 2.0 TOKEN EXCHANGE - RFC 8693 (ZERO-EDIT COPY/PASTE)\n"
    printf -- "--------------------------------------------------------------------------------\n"
    printf "Exchange \$APIGEE_ACCESS_TOKEN for a downscoped token and export \$EXCHANGED_ACCESS_TOKEN:\n\n"
    printf "EXCHANGE_RESPONSE=\$(curl -s -X POST \"https://\${APIGEE_HOST}%s/token\" \\\\\n" "$BASE_PATH"
    printf "  -H \"Content-Type: application/x-www-form-urlencoded\" \\\\\n"
    printf "  -d \"grant_type=urn:ietf:params:oauth:grant-type:token-exchange\" \\\\\n"
    printf "  -d \"client_id=\${CLIENT_ID}\" \\\\\n"
    printf "  -d \"client_secret=\${CLIENT_SECRET}\" \\\\\n"
    printf "  -d \"subject_token=\${APIGEE_ACCESS_TOKEN}\" \\\\\n"
    printf "  -d \"subject_token_type=urn:ietf:params:oauth:token-type:access_token\" \\\\\n"
    printf "  -d \"audience=\${TARGET_AUDIENCE}\" \\\\\n"
    printf "  -d \"scope=\${EXCHANGE_SCOPE}\")\n"
    printf "echo \"\$EXCHANGE_RESPONSE\" | jq .\n"
    printf "export EXCHANGED_ACCESS_TOKEN=\$(echo \"\$EXCHANGE_RESPONSE\" | jq -r '.access_token')\n\n"
    printf "================================================================================\n\n"
}

# ==============================================================================
# Main Execution
# ==============================================================================
timestamp=$(date '+%s')

# PKCE is ENABLED by default (set IS_PKCE_ENABLED=false to disable)
DEFAULT_IS_PKCE_ENABLED="true"
IS_PKCE_ENABLED="${IS_PKCE_ENABLED:-$DEFAULT_IS_PKCE_ENABLED}"
export IS_PKCE_ENABLED

set_pkce_config "$IS_PKCE_ENABLED"

echo "[INFO] Deploying Identity Facade (identity-facade-v1) via apigeecli"

APIGEE_X_ORG="${APIGEE_X_ORG:-${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}}"
APIGEE_X_ENV="${APIGEE_X_ENV:-$APIGEE_ENV}"

ensure_apigeecli

APIGEE_TOKEN="${APIGEE_TOKEN:-$(gcloud auth application-default print-access-token 2>/dev/null || gcloud auth print-access-token 2>/dev/null)}"

# Auto-discover APIGEE_X_HOSTNAME from the environment group attached to APIGEE_X_ENV if not explicitly provided
if [ -z "$APIGEE_X_HOSTNAME" ] && [ -n "$APIGEE_X_ORG" ] && [ -n "$APIGEE_X_ENV" ] && [ -n "$APIGEE_TOKEN" ]; then
    echo "[INFO] APIGEE_X_HOSTNAME not set. Discovering hostname for environment '$APIGEE_X_ENV'..."
    for eg_name in $(apigeecli envgroups list --org "$APIGEE_X_ORG" --token "$APIGEE_TOKEN" --disable-check 2>/dev/null | jq -r '.environmentGroups[].name // empty'); do
        attached_env=$(apigeecli envgroups attach list --name "$eg_name" --org "$APIGEE_X_ORG" --token "$APIGEE_TOKEN" --disable-check 2>/dev/null | jq -r --arg env "$APIGEE_X_ENV" '.environmentGroupAttachments[]? | select(.environment == $env) | .environment // empty')
        if [ "$attached_env" = "$APIGEE_X_ENV" ]; then
            APIGEE_X_HOSTNAME=$(apigeecli envgroups get --name "$eg_name" --org "$APIGEE_X_ORG" --token "$APIGEE_TOKEN" --disable-check 2>/dev/null | jq -r '.hostnames[0] // empty')
            if [ -n "$APIGEE_X_HOSTNAME" ]; then
                echo "[INFO] Discovered APIGEE_X_HOSTNAME: $APIGEE_X_HOSTNAME (from envgroup: $eg_name)"
                break
            fi
        fi
    done
fi

if [ -z "$APIGEE_X_ORG" ] || [ -z "$APIGEE_X_ENV" ] || [ -z "$APIGEE_X_HOSTNAME" ]; then
    echo "[ERROR] Missing required environment variables for Apigee deployment."
    echo "Please export:"
    echo "  export APIGEE_X_ORG=<your-apigee-org>"
    echo "  export APIGEE_X_ENV=<your-apigee-env>"
    echo "  export APIGEE_X_HOSTNAME=<your-apigee-env-group-hostname>"
    exit 1
fi

# Optional: Deploy OIDC Mock IdP if IDP_DISCOVERY_DOCUMENT is not set and ../oidc-mock exists
if [ -z "${IDP_DISCOVERY_DOCUMENT+x}" ] && [ -d "$SCRIPTPATH/../oidc-mock/apiproxy" ]; then
    echo "[INFO] IDP_DISCOVERY_DOCUMENT not set. Deploying oidc-mock via apigeecli..."
    apigeecli apis create bundle \
        --name "oidc-mock" \
        --proxy-folder "$SCRIPTPATH/../oidc-mock/apiproxy" \
        --env "$APIGEE_X_ENV" \
        --org "$APIGEE_X_ORG" \
        --token "$APIGEE_TOKEN" \
        --ovr \
        --wait \
        --disable-check
    (cd "$SCRIPTPATH/../oidc-mock" && npm i --no-fund && TEST_HOST="$APIGEE_X_HOSTNAME" npm test)
fi

DISCOVERY_DOCUMENT_URI="${IDP_DISCOVERY_DOCUMENT:-https://$APIGEE_X_HOSTNAME/v1/openid-connect/.well-known/openid-configuration}"
CALLBACK_URL="https://$APIGEE_X_HOSTNAME/v1/oauth20/callback"
set_idp_env_var "$DISCOVERY_DOCUMENT_URI" "$CALLBACK_URL"

set_functional_test_env_var "$timestamp"

deploy_with_apigeecli "$APIGEE_X_ORG" "$APIGEE_X_ENV" "$APIGEE_TOKEN"

if [ -z "${IDP_DISCOVERY_DOCUMENT+x}" ] && [ -f "$SCRIPTPATH/package.json" ]; then
    if [ "$IS_PKCE_ENABLED" = "true" ]; then
        (cd "$SCRIPTPATH" && npm i --no-fund && TEST_HOST="$APIGEE_X_HOSTNAME" IS_PKCE_ENABLED="$IS_PKCE_ENABLED" npm run testPkce)
    else
        (cd "$SCRIPTPATH" && npm i --no-fund && TEST_HOST="$APIGEE_X_HOSTNAME" IS_PKCE_ENABLED="$IS_PKCE_ENABLED" npm run test)
    fi
else
    echo "[INFO] Skipping mock IdP functional tests (using OIDC Discovery Document: $DISCOVERY_DOCUMENT_URI)"
fi

generate_authz_url "$APIGEE_X_HOSTNAME" "$TEST_APP_CONSUMER_KEY" "$TEST_APP_PKCE_CODE_CHALLENGE" "$IS_PKCE_ENABLED"
