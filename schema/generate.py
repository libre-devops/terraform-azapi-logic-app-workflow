#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6"]
# ///
"""Build the annotated Azure Logic Apps workflow definition schema, as JSON and YAML.

The published schema validates a definition but does not teach one: 147 KB of machine-generated
JSON with no `definitions` section, everything inlined through allOf/oneOf, and descriptions that
restate the property name. It also says nothing about the behaviours that pass validation and then
fail at run time.

This merges `annotations.yaml` into the upstream schema's `description` fields and writes:

    workflowdefinition.annotated.schema.json    the validator, with the notes inside descriptions
    workflowdefinition.annotated.schema.yaml    the same document, readable, notes as block scalars

Both remain valid JSON Schema draft-04 and still validate a real workflow definition, because the
only thing added is `description`, which carries no validation semantics.

Every annotation pointer is asserted to exist. If Microsoft reshapes the schema, this fails loudly
rather than dropping notes on the floor.

Usage:
    uv run schema/generate.py             # refresh from the live upstream schema
    uv run schema/generate.py --offline   # rebuild from the committed upstream copy
    uv run schema/generate.py --check     # fail if the committed outputs are stale

Exit codes: 0 clean, 1 stale or a fetch failed, 2 a pointer no longer resolves.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

import yaml


class _BlockDumper(yaml.SafeDumper):
    """Dump multi-line strings as literal blocks, so the annotations stay readable in YAML."""


def _str_representer(dumper: yaml.SafeDumper, data: str):
    if "\n" in data:
        # Trailing whitespace on a line makes a literal block unparseable, so strip it.
        cleaned = "\n".join(line.rstrip() for line in data.split("\n"))
        return dumper.represent_scalar("tag:yaml.org,2002:str", cleaned, style="|")
    return dumper.represent_scalar("tag:yaml.org,2002:str", data)


_BlockDumper.add_representer(str, _str_representer)

HERE = Path(__file__).resolve().parent
ANNOTATIONS = HERE / "annotations.yaml"
UPSTREAM_COPY = HERE / "workflowdefinition.schema.json"
OUT_JSON = HERE / "workflowdefinition.annotated.schema.json"
OUT_YAML = HERE / "workflowdefinition.annotated.schema.yaml"

UPSTREAM_URL = (
    "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/"
    "2016-06-01/workflowdefinition.json"
)


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "libre-devops-schema-annotator"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def resolve(document: object, pointer: str) -> object:
    """Resolve a JSON Pointer (RFC 6901). The empty pointer is the document itself."""
    if pointer == "":
        return document
    node = document
    for raw in pointer.lstrip("/").split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(node, list):
            node = node[int(token)]
        elif isinstance(node, dict):
            node = node[token]
        else:
            raise KeyError(pointer)
    return node


def annotate(schema: dict, notes: dict[str, str]) -> int:
    """Merge each note into the description at its pointer. Returns the count applied."""
    applied = 0
    for pointer, note in notes.items():
        try:
            node = resolve(schema, pointer)
        except (KeyError, IndexError, ValueError):
            print(f"error: pointer no longer resolves: {pointer!r}", file=sys.stderr)
            print("       the upstream schema has been reshaped; fix annotations.yaml", file=sys.stderr)
            raise SystemExit(2)
        if not isinstance(node, dict):
            print(f"error: pointer does not address an object: {pointer!r}", file=sys.stderr)
            raise SystemExit(2)

        upstream = (node.get("description") or "").strip()
        body = note.strip()
        # Keep Microsoft's own wording first where it says anything, then the annotation. The
        # upstream text is often a bare restatement, so it is dropped when the note subsumes it.
        if upstream and upstream.rstrip(".").lower() not in body.lower():
            node["description"] = f"{upstream}\n\n{body}"
        else:
            node["description"] = body
        applied += 1
    return applied


def correct(schema: dict, corrections: list[dict]) -> list[dict]:
    """Apply each widening correction. Returns a record of what was applied."""
    applied = []
    for fix in corrections:
        pointer, op = fix["pointer"], fix["op"]
        try:
            node = resolve(schema, pointer)
        except (KeyError, IndexError, ValueError):
            print(f"error: correction {fix['id']!r} pointer no longer resolves: {pointer}", file=sys.stderr)
            raise SystemExit(2)

        if op == "enum_add":
            missing = [v for v in fix["values"] if v not in node.get("enum", [])]
            node.setdefault("enum", []).extend(missing)
        elif op == "type_union":
            node["type"] = list(fix["values"])
        elif op == "oneof_add":
            node.setdefault("oneOf", []).append(fix["value"])
        elif op == "remove_key":
            for key in fix["values"]:
                node.pop(key, None)
        else:
            print(f"error: unknown correction op {op!r} in {fix['id']!r}", file=sys.stderr)
            raise SystemExit(2)

        node["description"] = (
            (node.get("description") or "").strip()
            + f"\n\nCORRECTED BY LIBRE DEVOPS ({fix['id']}): {' '.join(fix['why'].split())} "
            + f"Rejected {fix['occurrences']} real action(s) upstream."
        ).strip()
        applied.append({k: fix[k] for k in ("id", "pointer", "op", "occurrences", "why") if k in fix})
    return applied


def build(schema: dict, meta: dict, notes: dict[str, str], corrections: list[dict]) -> dict:
    annotated = json.loads(json.dumps(schema))  # deep copy, keeps ordering
    count = annotate(annotated, notes)
    fixes = correct(annotated, corrections)
    annotated["x-annotation"] = {
        **meta,
        "notes_applied": count,
        "corrections": fixes,
        "generated_by": "schema/generate.py",
        "warning": (
            "Generated file. Edit schema/annotations.yaml and regenerate; edits here are lost. "
            "Validation differs from upstream ONLY by the corrections listed above, each of which "
            "widens what is accepted so that definitions Azure itself emits stop being rejected."
        ),
    }
    return annotated


def yaml_header(meta: dict, count: int) -> str:
    return (
        "# Azure Logic Apps workflow definition schema, annotated.\n"
        "#\n"
        f"# Upstream: {meta['upstream']}\n"
        f"# Annotations by {meta['annotated_by']}, checked {meta['annotations_checked']}.\n"
        f"# {count} annotations applied.\n"
        "#\n"
        "# CORRECTED: the upstream schema rejects definitions Azure itself emits. See\n"
        "# x-annotation.corrections at the end of this file for each change and why.\n"
        "#\n"
        "# GENERATED FILE. Edit schema/annotations.yaml and run schema/generate.py.\n"
        "#\n"
        "# This is the SCHEMA in YAML, for readability and for tools that accept a YAML schema.\n"
        "# A workflow definition itself is JSON: Workflow Definition Language has no YAML dialect.\n"
        "#\n"
        "# Validation differs from upstream only by those corrections, each of which WIDENS what\n"
        "# is accepted. Nothing here makes the schema stricter.\n"
        "---\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="rebuild from the committed upstream copy")
    parser.add_argument("--check", action="store_true", help="fail if the committed outputs are stale")
    args = parser.parse_args()

    spec = yaml.safe_load(ANNOTATIONS.read_text(encoding="utf-8"))
    meta, notes, corrections = spec["meta"], spec["notes"], spec.get("corrections", [])

    if args.offline or args.check:
        if not UPSTREAM_COPY.exists():
            print(f"error: {UPSTREAM_COPY.name} is missing; run without --offline first", file=sys.stderr)
            return 1
        raw = UPSTREAM_COPY.read_text(encoding="utf-8")
    else:
        try:
            raw = fetch(UPSTREAM_URL)
        except (urllib.error.URLError, TimeoutError) as exc:
            print(f"error: fetching the upstream schema failed: {exc}", file=sys.stderr)
            return 1

    schema = json.loads(raw)
    annotated = build(schema, meta, notes, corrections)

    out_json = json.dumps(annotated, indent=2, ensure_ascii=False) + "\n"
    out_yaml = yaml_header(meta, annotated["x-annotation"]["notes_applied"]) + yaml.dump(
        annotated,
        Dumper=_BlockDumper,
        sort_keys=False,
        default_flow_style=False,
        allow_unicode=True,
        width=100,
    )

    if args.check:
        stale = [
            path.name
            for path, want in ((OUT_JSON, out_json), (OUT_YAML, out_yaml))
            if not path.exists() or path.read_text(encoding="utf-8") != want
        ]
        if stale:
            print("stale: " + ", ".join(stale), file=sys.stderr)
            print("run: uv run schema/generate.py --offline", file=sys.stderr)
            return 1
        print(f"clean: {OUT_JSON.name}, {OUT_YAML.name}")
        return 0

    if not args.offline:
        UPSTREAM_COPY.write_text(raw if raw.endswith("\n") else raw + "\n", encoding="utf-8")
    OUT_JSON.write_text(out_json, encoding="utf-8")
    OUT_YAML.write_text(out_yaml, encoding="utf-8")

    print(f"{annotated['x-annotation']['notes_applied']} annotations applied, "
          f"{len(annotated['x-annotation']['corrections'])} corrections applied")
    for path in (UPSTREAM_COPY, OUT_JSON, OUT_YAML):
        if path.exists():
            print(f"  {path.name:46} {path.stat().st_size:>9,} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
