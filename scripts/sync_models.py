#!/usr/bin/env python3
"""
sync_models.py — Generate Swift Codable structs from Pydantic schemas.

Source of truth : backend/app/schemas/   (Pydantic BaseModel subclasses)
Generated output: ios/StarterApp/StarterApp/Models/GeneratedModels.swift

The script discovers every public BaseModel subclass in the schemas package,
calls .model_json_schema() on it, maps JSON-Schema types to Swift types, and
writes a single Swift file that Tuist automatically picks up via its
`sources: ["StarterApp/**/*.swift"]` glob.

Usage (from repo root):
  make sync-models          # generate
  make check-models         # dry-run: exit 1 if output would change (use in CI)

  # Or directly (backend venv must be active):
  cd backend && uv run python ../scripts/sync_models.py [--check]
"""

from __future__ import annotations

import argparse
import importlib
import inspect
import pkgutil
import re
import sys
from pathlib import Path
from textwrap import indent

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parent.parent
BACKEND_DIR = REPO_ROOT / "backend"
SCHEMAS_PACKAGE = "app.schemas"
OUTPUT_FILE = (
    REPO_ROOT / "ios/StarterApp/StarterApp/Models/GeneratedModels.swift"
)

# Schema names to skip (FastAPI / Pydantic internal error types).
SKIP_SCHEMAS: set[str] = {
    "HTTPValidationError",
    "ValidationError",
}


# ---------------------------------------------------------------------------
# Schema discovery
# ---------------------------------------------------------------------------

def discover_schema_classes() -> dict[str, type]:
    """
    Import every module under app/schemas/ and return a dict of
    {ClassName: PydanticModelClass} for all public BaseModel subclasses.
    """
    sys.path.insert(0, str(BACKEND_DIR))

    try:
        from pydantic import BaseModel
    except ImportError:
        sys.exit(
            "Error: pydantic not found.\n"
            "Run this script via: cd backend && uv run python ../scripts/sync_models.py"
        )

    schemas_dir = BACKEND_DIR / "app" / "schemas"
    if not schemas_dir.is_dir():
        sys.exit(f"Error: schemas directory not found at {schemas_dir}")

    found: dict[str, type] = {}
    for module_info in pkgutil.iter_modules([str(schemas_dir)]):
        module_name = f"{SCHEMAS_PACKAGE}.{module_info.name}"
        try:
            module = importlib.import_module(module_name)
        except Exception as exc:  # noqa: BLE001
            print(f"  ⚠  Skipping {module_name}: {exc}")
            continue

        for attr_name, obj in vars(module).items():
            if (
                inspect.isclass(obj)
                and issubclass(obj, BaseModel)
                and obj is not BaseModel
                and not attr_name.startswith("_")
                and attr_name not in SKIP_SCHEMAS
                # Only include classes defined in this module (not re-imports)
                and obj.__module__ == module_name
            ):
                found[attr_name] = obj

    return found


# ---------------------------------------------------------------------------
# JSON Schema → Swift type mapping
# ---------------------------------------------------------------------------

def _resolve_defs(schema: dict, defs: dict) -> dict:
    """Resolve a $ref inside the same schema's $defs."""
    if "$ref" in schema:
        ref_key = schema["$ref"].split("/")[-1]
        return defs.get(ref_key, schema)
    return schema


def json_schema_to_swift_type(
    prop: dict,
    required: bool,
    defs: dict,
) -> str:
    """
    Recursively map a JSON Schema property dict to a Swift type string.

    `required` indicates whether the parent object lists this field as required.
    Optional Swift types (String?) are used when:
      - the field is not required, OR
      - the type is a Pydantic nullable (anyOf: [{…}, {type: null}])
    """
    prop = _resolve_defs(prop, defs)

    # anyOf — Pydantic v2 emits anyOf:[{type:X},{type:null}] for T | None
    if "anyOf" in prop:
        non_null = [p for p in prop["anyOf"] if p.get("type") != "null"]
        has_null = any(p.get("type") == "null" for p in prop["anyOf"])
        if len(non_null) == 1:
            inner = json_schema_to_swift_type(non_null[0], required=True, defs=defs)
            return f"{inner}?" if has_null else inner
        # Multiple non-null variants — fall through to AnyCodable
        return "AnyCodable?"

    t = prop.get("type", "")
    fmt = prop.get("format", "")

    if t == "string":
        if fmt == "uuid":
            swift = "UUID"
        elif fmt == "date-time":
            swift = "Date"
        else:
            swift = "String"
    elif t == "integer":
        swift = "Int"
    elif t == "number":
        swift = "Double"
    elif t == "boolean":
        swift = "Bool"
    elif t == "array":
        item_swift = json_schema_to_swift_type(
            prop.get("items", {}), required=True, defs=defs
        )
        swift = f"[{item_swift}]"
    elif t == "object":
        # Typed dict-like → best effort
        swift = "[String: String]"
    else:
        swift = "AnyCodable"

    return swift if required else f"{swift}?"


# ---------------------------------------------------------------------------
# Swift struct codegen
# ---------------------------------------------------------------------------

def _snake_to_camel(name: str) -> str:
    parts = name.split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def generate_swift_struct(class_name: str, schema: dict) -> str:
    """Return a Swift struct string for a single JSON Schema object."""
    defs = schema.get("$defs", {})
    properties: dict[str, dict] = schema.get("properties", {})
    required_set: set[str] = set(schema.get("required", []))
    description: str = schema.get("description", "")

    lines: list[str] = []

    # Doc-comment
    doc = description or f"Auto-generated from `{class_name}` (backend/app/schemas)."
    lines.append(f"/// {doc}")

    lines.append(f"struct {class_name}: Codable, Equatable {{")

    # Properties
    for prop_name, prop_schema in properties.items():
        is_required = prop_name in required_set
        swift_type = json_schema_to_swift_type(prop_schema, is_required, defs)
        camel = _snake_to_camel(prop_name)
        lines.append(f"    let {camel}: {swift_type}")

    # CodingKeys — only emit when at least one field name requires mapping
    snake_fields = [p for p in properties if "_" in p]
    if snake_fields:
        lines.append("")
        lines.append("    enum CodingKeys: String, CodingKey {")
        for prop_name in properties:
            camel = _snake_to_camel(prop_name)
            if "_" in prop_name:
                lines.append(f'        case {camel} = "{prop_name}"')
            else:
                lines.append(f"        case {camel}")
        lines.append("    }")

    lines.append("}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# SQL drift check (best-effort warning only, never blocks generation)
# ---------------------------------------------------------------------------

def check_sql_drift(schema_classes: dict[str, type]) -> None:
    """
    Parse SQL migrations and warn if a Pydantic field name cannot be found
    in any CREATE TABLE column list. This is a heuristic — it's intentionally
    lenient (computed fields, joins, etc. are fine to omit from SQL).
    """
    migrations_dir = REPO_ROOT / "supabase" / "migrations"
    if not migrations_dir.exists():
        return

    sql_text = "".join(f.read_text() for f in sorted(migrations_dir.glob("*.sql")))

    # Rough extraction of column names from CREATE TABLE blocks
    table_blocks = re.findall(
        r"CREATE TABLE[^(]*\((.+?)\);",
        sql_text,
        re.DOTALL | re.IGNORECASE,
    )
    sql_columns: set[str] = set()
    for block in table_blocks:
        for raw_line in block.splitlines():
            stripped = raw_line.strip().lstrip('"').split('"')[0].strip()
            parts = stripped.split()
            if not parts:
                continue
            col = parts[0].rstrip(",").lower()
            if col and not col.startswith(
                ("--", "constraint", "primary", "unique", "foreign", "check", ")", "(")
            ):
                sql_columns.add(col)

    if not sql_columns:
        return

    for class_name, cls in schema_classes.items():
        schema = cls.model_json_schema()
        for field_name in schema.get("properties", {}):
            if field_name not in sql_columns:
                print(
                    f"  ⚠  {class_name}.{field_name} has no matching SQL column "
                    f"(may be fine if it's computed or from a join)"
                )


# ---------------------------------------------------------------------------
# File header
# ---------------------------------------------------------------------------

SWIFT_HEADER = """\
// Generated by scripts/sync_models.py — DO NOT EDIT MANUALLY.
// Re-run `make sync-models` after changing any file in backend/app/schemas/.
//
// JSONDecoder setup required in your app (BackendAPIService or a shared decoder):
//   decoder.dateDecodingStrategy = .iso8601
//   (CodingKeys handle snake_case → camelCase; no keyDecodingStrategy override needed)

import Foundation

"""


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Swift Codable structs from Pydantic schemas."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Dry-run: exit 1 if the generated output differs from the current file.",
    )
    args = parser.parse_args()

    print("→ Discovering Pydantic schemas in backend/app/schemas/ …")
    schema_classes = discover_schema_classes()

    if not schema_classes:
        print("  No BaseModel subclasses found — nothing to generate.")
        return

    print(f"  Found: {', '.join(sorted(schema_classes))}")

    # SQL drift warning (best-effort, never fatal)
    print("→ Checking SQL migration alignment …")
    check_sql_drift(schema_classes)

    # Generate Swift structs
    print("→ Generating Swift structs …")
    struct_blocks: list[str] = []
    for class_name in sorted(schema_classes):
        cls = schema_classes[class_name]
        try:
            schema = cls.model_json_schema()
            if schema.get("type") != "object":
                print(f"  ⚠  Skipping {class_name}: not an object schema")
                continue
            struct_blocks.append(generate_swift_struct(class_name, schema))
        except Exception as exc:  # noqa: BLE001
            print(f"  ⚠  Skipping {class_name}: {exc}")

    if not struct_blocks:
        print("  Nothing to write.")
        return

    output = SWIFT_HEADER + "\n\n".join(struct_blocks) + "\n"

    rel_path = OUTPUT_FILE.relative_to(REPO_ROOT)

    if args.check:
        current = OUTPUT_FILE.read_text() if OUTPUT_FILE.exists() else ""
        if output == current:
            print(f"✓ {rel_path} is up to date.")
        else:
            print(
                f"✗ {rel_path} is out of sync.\n"
                "  Run `make sync-models` to regenerate."
            )
            sys.exit(1)
        return

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(output)
    print(f"✓ Written → {rel_path}")
    print()
    print("  Next: if this is the first run, re-run `tuist generate` in ios/StarterApp/")
    print("  so Xcode picks up the new Models/ folder.")


if __name__ == "__main__":
    main()
