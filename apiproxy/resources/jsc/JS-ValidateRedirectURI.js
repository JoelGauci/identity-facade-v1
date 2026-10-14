/**
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// ============================================================================
// JavaScript Policy - Validate OAuth Redirect URI (Parametrized version)
// Language: ECMA Script 5 (ES5)
// ============================================================================

// 1. Retrieve the names of the context variables from the policy properties
var allowedUrisVarName = properties.allowedUrisVar;
var requestedUriVarName = properties.requestedUriVar;
var outputVarName = properties.outputVar;

// 2. Fetch the actual values of those context variables using dynamic lookup
var allowedUrisList = context.getVariable(allowedUrisVarName);
var requestedUri = context.getVariable(requestedUriVarName);

// Initialize validation flag as false
var isRedirectUriValid = false;

if (allowedUrisList && requestedUri) {
    // Decode and trim the requested URI to normalize it
    var normalizedRequestedUri = "";
    try {
        normalizedRequestedUri = decodeURIComponent(requestedUri).trim();
    } catch (e) {
        normalizedRequestedUri = requestedUri.trim();
    }

    // Split the allowed URIs list by comma
    var allowedUrisArray = allowedUrisList.split(",");

    // Iterate through allowed URIs, decode and compare
    for (var i = 0; i < allowedUrisArray.length; i++) {
        var currentUri = allowedUrisArray[i].trim();
        var normalizedCurrentUri = "";
        
        try {
            normalizedCurrentUri = decodeURIComponent(currentUri).trim();
        } catch (e) {
            normalizedCurrentUri = currentUri.trim();
        }

        // Compare the normalized URIs
        if (normalizedCurrentUri === normalizedRequestedUri) {
            isRedirectUriValid = true;
            break; // Valid URI found, exit loop
        }
    }
}

// 3. Store the final result in the dynamically specified context variable
context.setVariable(outputVarName, isRedirectUriValid);