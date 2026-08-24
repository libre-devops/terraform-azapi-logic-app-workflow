# The workflow definition schema, annotated

The Azure Logic Apps workflow definition schema, version `2016-06-01`, with Libre DevOps
annotations and five corrections, published as **JSON and YAML**.

| File | What it is |
|---|---|
| `workflowdefinition.schema.json` | the upstream schema, committed verbatim so a rebuild needs no network |
| `workflowdefinition.annotated.schema.json` | the deliverable: annotated and corrected |
| `workflowdefinition.annotated.schema.yaml` | the same document in YAML |
| `annotations.yaml` | the notes and corrections, hand authored, the only file to edit |
| `generate.py` | fetches upstream, applies both layers, writes the two outputs |

## Why this exists

The published schema is machine generated: 147 KB, no `definitions` section, everything inlined
through `allOf`/`oneOf`, and descriptions like `"The flow triggers."` that restate the property
name. It validates a definition but it does not teach one, and it says nothing about the
behaviours that pass validation and then fail at run time.

Worse, **it rejects definitions Azure itself emits**. Validating the 87 workflow definitions in
this workspace against it:

| | Whole definitions validating cleanly |
|---|---|
| upstream schema | **13 of 35** |
| this schema | **35 of 35** |

## The corrections

Every one was found by validating real definitions, not by reading. Each widens what is accepted;
none makes the schema accept less. The occurrence count is how many real actions upstream rejected.

| Correction | Occurrences | What upstream gets wrong |
|---|---:|---|
| `retry-policy-type-casing` | 39 | enum is `None`/`Fixed`/`Exponential`; the designer and every example emit lowercase |
| `authentication-managed-identity` | 28 | the `authentication` union has no `ManagedServiceIdentity` branch, which is the recommended auth for an Http action calling Azure |
| `retry-policy-count-expression` | 5 | `count` is typed `integer`, rejecting `"@parameters('retry_count')"`; any WDL value may be an expression string |
| `variable-type-casing` | 3 | `InitializeVariable` and `SetVariable` types are PascalCase upstream, lowercase in practice |
| `initialize-variable-multiple` | 1 | `variables` is capped at `maxItems: 1`; a portal export from a live workflow carries three |

Each correction is recorded in the output under `x-annotation.corrections`, with its pointer,
reason and occurrence count, and is called out in the `description` at the node it changed.

[`UPSTREAM-ISSUE.md`](./UPSTREAM-ISSUE.md) is the write-up ready to file with Microsoft, with the
evidence and a reproduction. File it, then delete a correction here when the upstream fix lands.

## Using it

**Point your editor at it** while authoring a `.json.tftpl` template, and you get hover
documentation and completion on every property, without false errors on correct workflows.

VS Code, in `.vscode/settings.json`:

```json
{
  "json.schemas": [
    {
      "fileMatch": ["templates/*.json.tftpl", "**/workflow.json"],
      "url": "./schema/workflowdefinition.annotated.schema.json"
    }
  ]
}
```

**Validate in CI** with any draft-04 validator, for example:

```bash
uv run --with check-jsonschema check-jsonschema \
  --schemafile schema/workflowdefinition.annotated.schema.json \
  templates/*.json
```

Note that a `.json.tftpl` template is not valid JSON until `templatefile` has rendered its
`${tokens}`, so validate the rendered output rather than the template, or substitute the tokens
first.

## Regenerating

```bash
uv run schema/generate.py             # refresh from the live upstream schema
uv run schema/generate.py --offline   # rebuild from the committed upstream copy
uv run schema/generate.py --check     # fail if the committed outputs are stale
```

Edit `annotations.yaml`, never the generated files. Every annotation and correction pointer is
asserted to resolve, so if Microsoft reshapes the schema the build fails loudly rather than
silently dropping notes.

## There is no YAML dialect of WDL

The YAML file here is **the schema** in YAML, for readability and for tools that accept a YAML
schema. A workflow definition itself is JSON. See the
[Libre DevOps Logic App standard](https://libredevops.org/docs/documents/azure-logic-app-standards).

## Sources

Annotations were written against these, all checked 24 August 2026:

- [Workflow Definition Language overview](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-workflow-definition-language)
- [Schema reference](https://learn.microsoft.com/en-us/azure/logic-apps/workflow-definition-language-schema)
- [Triggers and actions reference](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-workflow-actions-triggers)
- [Expression functions reference](https://learn.microsoft.com/en-us/azure/logic-apps/expression-functions-reference)
- [Libre DevOps Azure Logic App standard](https://libredevops.org/docs/documents/azure-logic-app-standards)
