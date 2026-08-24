# Upstream issue: the published WDL schema rejects definitions Azure emits

Drafted 24 August 2026, ready to file at <https://github.com/Azure/logicapps/issues/new>.
Not filed automatically: the CI token is scoped to this organisation and cannot open issues
on external repositories.

The five defects below are the same ones `annotations.yaml` corrects, with the evidence.

---

### Summary

The published Workflow Definition Language schema at

`https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json`

rejects workflow definitions that Azure itself emits. A portal **code view** export, pasted unchanged, fails validation against the schema that the same export's own `$schema` points at.

The practical consequence is that the schema cannot be used as an editor schema: pointing VS Code at it redlines correct, deployed workflows, which is presumably why almost nobody does.

### How this was found

Validating 87 real workflow definitions (portal exports and definitions deployed via ARM) against the published schema with a draft-04 validator. **13 of the 35 whole definitions passed.** After applying the five corrections below, all 35 pass. Occurrence counts are the number of real actions each defect rejected.

### The defects

**1. `retryPolicy.type` enum is PascalCase; everything real is lowercase** (39 occurrences)

The schema declares:

```json
"type": { "type": "string", "enum": ["None", "Fixed", "Exponential"] }
```

The designer, the documentation examples and every deployed definition use `"none"`, `"fixed"`, `"exponential"`. Across the sample: 516 lowercase, 1 PascalCase.

**2. `authentication` has no `ManagedServiceIdentity` branch** (28 occurrences)

The `authentication` union on an action's `inputs` carries `Basic`, `ClientCertificate`, `None`, `ActiveDirectoryOAuth` and `Raw`, but not `ManagedServiceIdentity`:

```json
{ "type": "ManagedServiceIdentity", "audience": "https://management.azure.com" }
```

That is the recommended authentication for an Http action calling an Azure endpoint, and the 2016-06-01 schema predates it. This is the most impactful of the five.

**3. `retryPolicy.count` is typed `integer`, rejecting an expression** (5 occurrences)

```json
"count": { "type": "integer" }
```

rejects `"count": "@parameters('retry_count')"`. Any WDL value may be an expression string, so a typed scalar that does not also accept `string` is wrong wherever an expression is legal. `count` is where it bites most often.

**4. `InitializeVariable` / `SetVariable` variable type enum is PascalCase** (3 occurrences)

```json
"FlowVariableDataType": { "enum": ["Array", "Boolean", "Float", "Integer", "Object", "String"] }
```

The designer emits `"string"`, `"integer"`, and so on.

Worth noting that this is a *different* enum from the workflow **parameter** type enum (`Array`, `Bool`, `Float`, `Int`, `Object`, `SecureObject`, `SecureString`, `String`), which really is PascalCase. A single portal export contains both casings, correctly:

```json
"parameters": { "window_hours": { "type": "Int" } }
"variables":  [ { "name": "windowEnd", "type": "string" } ]
```

The schema models the parameter enum correctly and the variable enum incorrectly.

**5. `InitializeVariable` caps `variables` at `maxItems: 1`** (1 occurrence)

A portal code view export taken from a live workflow carries three variables in one `InitializeVariable` action, so the platform both emits and accepts more than one.

### Also worth flagging

`staticResults` is documented as a definition-level attribute (referenced by `runtimeConfiguration.staticResult.name` on an action) but is not declared in the schema's root `properties`. It validates only because the root does not forbid unknown properties.

Separately, the trigger `oneOf` contains a branch with no `type` and no properties, which accepts anything the eight typed branches do not. `ApiConnectionWebhook`, a documented managed API trigger type and the shape of the Sentinel incident trigger, passes only because that catch-all exists, not because it is checked.

### Reproduction

```bash
curl -s https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json -o schema.json
# export any workflow using a retry policy or managed identity auth from the portal code view
python -c "
import json, jsonschema
s = json.load(open('schema.json')); d = json.load(open('export.json'))
for e in jsonschema.Draft4Validator(s).iter_errors(d.get('definition', d)): print(e.message[:200])
"
```

### Ask

Fix the enums and add the `ManagedServiceIdentity` branch, or state that the schema is not intended to validate real definitions so people stop trying to use it that way. Either is fine; the current state is the worst of both, because the schema looks authoritative and is not.

Happy to raise a PR if the schema is generated from a source that accepts contributions, though it does not appear to live in [`azure-resource-manager-schemas`](https://github.com/Azure/azure-resource-manager-schemas) (which covers `schema.management.azure.com/schemas`, a different path).
