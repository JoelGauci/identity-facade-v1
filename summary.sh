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
# Script: summary.sh
# Purpose: Strictly read-only, POSIX-compliant script that inspects an existing
#          Apigee Identity Facade (identity-facade-v1) deployment via apigeecli
#          and recreates the exact deployment summary and end-to-end test commands
#          generated at the end of pipeline.sh.
#          Performs ZERO creation/modification actions on Apigee or Google Cloud.
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
# Function: generate_authz_url
# Prints the comprehensive deployment summary, IdP callback requirements,
# KVM & Developer App attributes, Authorization URL, and ready-to-run curl
# commands for Authorization Code + PKCE, Protected API, Refresh Token, and
# RFC 8693 Token Exchange (identical to pipeline.sh).
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
# Main Read-Only Inspection & Summary Generation
# ==============================================================================
ensure_apigeecli

APIGEE_X_ORG="${APIGEE_X_ORG:-${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}}"
APIGEE_X_ENV="${APIGEE_X_ENV:-$APIGEE_ENV}"
APIGEE_TOKEN="${APIGEE_TOKEN:-$(gcloud auth application-default print-access-token 2>/dev/null || gcloud auth print-access-token 2>/dev/null)}"

if [ -z "$APIGEE_X_ORG" ] || [ -z "$APIGEE_TOKEN" ]; then
    echo "[ERROR] Unable to determine APIGEE_X_ORG or Google Cloud access token."
    echo "Please export the necessary environment variables:"
    echo "  export APIGEE_X_ORG=\"<your-apigee-org>\""
    echo "  export APIGEE_X_ENV=\"<your-apigee-env>\""
    exit 1
fi

echo "[INFO] Checking Identity Facade (identity-facade-v1) deployment status in Apigee Organization '$APIGEE_X_ORG'..."

# 1. Check deployments of identity-facade-v1 across the organization (Read-Only)
deploy_json=$(apigeecli apis listdeploy --name "identity-facade-v1" --org "$APIGEE_X_ORG" --token "$APIGEE_TOKEN" --disable-check 2>/dev/null || true)
all_deployed_envs=$(printf '%s' "$deploy_json" | jq -r '.deployments[]?.environment // empty' 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')

# If APIGEE_X_ENV is not explicitly set, auto-select if deployed in an environment
if [ -z "$APIGEE_X_ENV" ] && [ -n "$all_deployed_envs" ]; then
    APIGEE_X_ENV=$(printf '%s' "$deploy_json" | jq -r '.deployments[0].environment // empty' 2>/dev/null)
    echo "[INFO] APIGEE_X_ENV not set. Auto-detected deployed environment: $APIGEE_X_ENV"
fi

# Determine if identity-facade-v1 is deployed in the target environment
deployed_rev=""
if [ -n "$APIGEE_X_ENV" ]; then
    deployed_rev=$(printf '%s' "$deploy_json" | jq -r --arg env "$APIGEE_X_ENV" '.deployments[]? | select(.environment == $env) | .revision // empty' 2>/dev/null | head -n 1)
fi

if [ -z "$deployed_rev" ]; then
    printf "\n"
    printf "================================================================================\n"
    printf "  [WARNING] NO IDENTITY FACADE DEPLOYED ON APIGEE\n"
    printf "  Aucune facade d'identité ('identity-facade-v1') n'est déployée sur Apigee !\n"
    printf "================================================================================\n"
    printf "  - Apigee Organization : %s\n" "$APIGEE_X_ORG"
    printf "  - Target Environment  : %s\n" "${APIGEE_X_ENV:-<not specified>}"
    printf "  - API Proxy Status    : NOT DEPLOYED (identity-facade-v1)\n"
    if [ -n "$all_deployed_envs" ]; then
        printf "  - Note                : 'identity-facade-v1' is deployed in environment(s): %s\n" "$all_deployed_envs"
        printf "                          Run: export APIGEE_X_ENV=\"%s\" && ./summary.sh\n" "$all_deployed_envs"
    else
        printf "\n  To deploy the Identity Facade and provision all required Apigee resources,\n"
        printf "  run ./pipeline.sh first:\n\n"
        printf "    export APIGEE_X_ORG=\"%s\"\n" "$APIGEE_X_ORG"
        printf "    export APIGEE_X_ENV=\"%s\"\n" "${APIGEE_X_ENV:-<your-apigee-env>}"
        printf "    export APIGEE_X_HOSTNAME=\"<your-apigee-env-group-hostname>\"\n"
        printf "    export IDP_DISCOVERY_DOCUMENT=\"https://<your-idp>/.well-known/openid-configuration\"\n"
        printf "    ./pipeline.sh\n"
    fi
    printf "================================================================================\n\n"
    exit 1
fi

echo "[INFO] Found deployed proxy 'identity-facade-v1' (revision $deployed_rev) in '$APIGEE_X_ORG / $APIGEE_X_ENV'."

# 2. Auto-discover APIGEE_X_HOSTNAME from Environment Group if not set
if [ -z "$APIGEE_X_HOSTNAME" ]; then
    for eg_name in $(apigeecli envgroups list --org "$APIGEE_X_ORG" --token "$APIGEE_TOKEN" --disable-check 2>/dev/null | jq -r '.environmentGroups[].name // empty'); do
        attached_env=$(apigeecli envgroups attach list --name "$eg_name" --org "$APIGEE_X_ORG" --token "$APIGEE_TOKEN" --disable-check 2>/dev/null | jq -r --arg env "$APIGEE_X_ENV" '.environmentGroupAttachments[]? | select(.environment == $env) | .environment // empty')
        if [ "$attached_env" = "$APIGEE_X_ENV" ]; then
            APIGEE_X_HOSTNAME=$(apigeecli envgroups get --name "$eg_name" --org "$APIGEE_X_ORG" --token "$APIGEE_TOKEN" --disable-check 2>/dev/null | jq -r '.hostnames[0] // empty')
            if [ -n "$APIGEE_X_HOSTNAME" ]; then
                break
            fi
        fi
    done
fi

# 3. Fetch Environment KVM (idpConfigIdentityProxy) entries (Read-Only)
kvm_json=$(apigeecli kvms entries list --map "idpConfigIdentityProxy" --env "$APIGEE_X_ENV" --org "$APIGEE_X_ORG" --token "$APIGEE_TOKEN" --disable-check 2>/dev/null || true)

get_kvm_val() {
    k_name="$1"
    printf '%s' "$kvm_json" | jq -r --arg k "$k_name" '.keyValueEntries[]? | select(.name == $k) | .value // empty' 2>/dev/null | head -n 1
}

TEST_IDP_ISSUER="${TEST_IDP_ISSUER:-$(get_kvm_val "idp.issuer")}"
TEST_IDP_AZ_HOSTNAME="${TEST_IDP_AZ_HOSTNAME:-$(get_kvm_val "idp.az.hostname")}"
TEST_IDP_AZ_URI="${TEST_IDP_AZ_URI:-$(get_kvm_val "idp.az.uri")}"
TEST_IDP_TOKEN_HOSTNAME="${TEST_IDP_TOKEN_HOSTNAME:-$(get_kvm_val "idp.token.hostname")}"
TEST_IDP_TOKEN_URI="${TEST_IDP_TOKEN_URI:-$(get_kvm_val "idp.token.uri")}"
TEST_IDP_JWKS_HOSTNAME="${TEST_IDP_JWKS_HOSTNAME:-$(get_kvm_val "idp.jwks.hostname")}"
TEST_IDP_JWKS_URI="${TEST_IDP_JWKS_URI:-$(get_kvm_val "idp.jwks.uri")}"
TEST_IDP_USERINFO_HOSTNAME="${TEST_IDP_USERINFO_HOSTNAME:-$(get_kvm_val "idp.userinfo.hostname")}"
TEST_IDP_USERINFO_URI="${TEST_IDP_USERINFO_URI:-$(get_kvm_val "idp.userinfo.uri")}"

kvm_client_id=$(get_kvm_val "idp.apigee.client_id")
kvm_redirect_uri=$(get_kvm_val "idp.apigee.redirect_uri")

# 4. Fetch Developer App (identityApp) attributes and credentials (Read-Only)
app_json=$(apigeecli apps get --name "identityApp" --org "$APIGEE_X_ORG" --token "$APIGEE_TOKEN" --disable-check 2>/dev/null || true)

get_app_attr() {
    attr_name="$1"
    printf '%s' "$app_json" | jq -r --arg a "$attr_name" '.[0].attributes[]? | select(.name == $a) | .value // empty' 2>/dev/null | head -n 1
}

app_key=$(printf '%s' "$app_json" | jq -r '( [ .[0].credentials[]? | select(.status == "approved" and (.apiProducts[]?.apiproduct == "IdentityFacade")) ] | (map(select(.consumerKey | startswith("xkey-"))) + .)[0] // .[0].credentials[0] ).consumerKey // empty' 2>/dev/null)
app_secret=$(printf '%s' "$app_json" | jq -r '( [ .[0].credentials[]? | select(.status == "approved" and (.apiProducts[]?.apiproduct == "IdentityFacade")) ] | (map(select(.consumerKey | startswith("xkey-"))) + .)[0] // .[0].credentials[0] ).consumerSecret // empty' 2>/dev/null)

app_redirect_attr=$(get_app_attr "redirect_uris")
if [ -z "$app_redirect_attr" ]; then
    app_redirect_attr=$(get_app_attr "redirection_uris")
fi
if [ -z "$app_redirect_attr" ]; then
    app_redirect_attr=$(printf '%s' "$app_json" | jq -r '.[0].callbackUrl // empty' 2>/dev/null)
fi

app_idp_client_id=$(get_app_attr "idp_client_id")
app_idp_redirect_uri=$(get_app_attr "idp_redirect_uri")

TEST_APP_CONSUMER_KEY="${TEST_APP_CONSUMER_KEY:-${app_key:-<NOT_FOUND_IN_APIGEE>}}"
TEST_APP_CONSUMER_SECRET="${TEST_APP_CONSUMER_SECRET:-${app_secret:-<NOT_FOUND_IN_APIGEE>}}"
APP_REDIRECT_URI="${APP_REDIRECT_URI:-${app_redirect_attr:-https://mocktarget.apigee.net/echo}}"
TEST_IDP_APIGEE_CLIENT_ID="${TEST_IDP_APIGEE_CLIENT_ID:-${app_idp_client_id:-${kvm_client_id:-dummy-client_id-apigee123}}}"
TEST_IDP_APIGEE_REDIRECT_URI="${TEST_IDP_APIGEE_REDIRECT_URI:-${app_idp_redirect_uri:-${kvm_redirect_uri:-https://$APIGEE_X_HOSTNAME/v1/oauth20/callback}}}"

if [ -n "$IDP_DISCOVERY_DOCUMENT" ]; then
    DISCOVERY_DOCUMENT_URI="$IDP_DISCOVERY_DOCUMENT"
elif [ -n "$TEST_IDP_ISSUER" ]; then
    DISCOVERY_DOCUMENT_URI="${TEST_IDP_ISSUER%/}/.well-known/openid-configuration"
else
    DISCOVERY_DOCUMENT_URI="https://$APIGEE_X_HOSTNAME/v1/openid-connect/.well-known/openid-configuration"
fi

# 5. Determine PKCE mode and PKCE test parameters
if [ -z "$IS_PKCE_ENABLED" ]; then
    if [ -f "$SCRIPTPATH/apiproxy/policies/AM-SetPKCEMode.xml" ]; then
        detected_pkce=$(sed -n 's|.*<Value>\(.*\)</Value>.*|\1|p' "$SCRIPTPATH/apiproxy/policies/AM-SetPKCEMode.xml" | head -n 1)
    fi
    IS_PKCE_ENABLED="${detected_pkce:-true}"
fi

TEST_APP_PKCE_CODE_CHALLENGE="hoLP4vNbBccHkhNAbk_jbyLhlGwgeoRyo53A-Luiirg"
TEST_APP_PKCE_CODE_VERIFIER="iloveapis1234567890"

# 6. Print the exact deployment summary and test commands
generate_authz_url "$APIGEE_X_HOSTNAME" "$TEST_APP_CONSUMER_KEY" "$TEST_APP_PKCE_CODE_CHALLENGE" "$IS_PKCE_ENABLED"
