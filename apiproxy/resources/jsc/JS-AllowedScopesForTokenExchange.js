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

var allowedScopes = context.getVariable('accesstoken.idp.scope');
var listScope = context.getVariable('request.formparam.scope');

function getScopeForExchange(listScope, allowedScopes) {
    // Sécurité : on s'assure que les variables ne sont pas vides
    if (!listScope || !allowedScopes) {
        return "";
    }

    // 1. Transformer les chaînes de caractères en tableaux (arrays)
    var listArray = listScope.split(' ');
    var allowedArray = allowedScopes.split(' ');

    // 2. Filtrer le premier tableau
    var filteredArray = listArray.filter(function(scope) {
        // On ignore les espaces vides éventuels dus à des doubles espaces
        if (scope === "") {
            return false;
        }
        // indexOf retourne -1 si l'élément n'est pas trouvé dans le tableau
        return allowedArray.indexOf(scope) !== -1;
    });

    // 3. Reconstruire une chaîne de caractères séparée par des espaces
    var scopeForExchange = filteredArray.join(' ');

    return scopeForExchange;
}

context.setVariable('flow.apigee.scopesForExchange',getScopeForExchange(listScope,allowedScopes));