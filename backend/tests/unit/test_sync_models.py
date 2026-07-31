"""
Unit tests for scripts/sync_models.py — json_schema_to_swift_type().

Specifically targets the nested-ref bug: $ref fields inside a schema's $defs
must emit the referenced struct's name (e.g. "NoteOut"), not "[String: String]".
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


def _load_sync_models():
    """Load scripts/sync_models.py by file path (it is not a package)."""
    repo_root = Path(__file__).resolve().parents[3]
    script_path = repo_root / "scripts" / "sync_models.py"
    spec = importlib.util.spec_from_file_location("sync_models", script_path)
    module = importlib.util.module_from_spec(spec)
    # Ensure backend/ is on sys.path so pydantic imports work inside the module
    backend_dir = str(repo_root / "backend")
    if backend_dir not in sys.path:
        sys.path.insert(0, backend_dir)
    spec.loader.exec_module(module)
    return module


sync_models = _load_sync_models()
json_schema_to_swift_type = sync_models.json_schema_to_swift_type


DEFS = {
    "NoteOut": {
        "type": "object",
        "properties": {"id": {"type": "string", "format": "uuid"}},
        "required": ["id"],
    },
    "ProfileOut": {
        "type": "object",
        "properties": {"id": {"type": "string", "format": "uuid"}},
        "required": ["id"],
    },
}


class TestRefResolution:
    def test_direct_ref_required_emits_struct_name(self):
        """A required $ref field → bare struct name (no '?')."""
        prop = {"$ref": "#/$defs/NoteOut"}
        result = json_schema_to_swift_type(prop, required=True, defs=DEFS)
        assert result == "NoteOut", (
            f"Expected 'NoteOut', got '{result}' — "
            "direct $ref is being inlined as [String: String]"
        )

    def test_array_of_ref_emits_typed_array(self):
        """An array of $ref items → '[NoteOut]'."""
        prop = {
            "type": "array",
            "items": {"$ref": "#/$defs/NoteOut"},
        }
        result = json_schema_to_swift_type(prop, required=True, defs=DEFS)
        assert result == "[NoteOut]", (
            f"Expected '[NoteOut]', got '{result}' — "
            "array-of-ref is not emitting the typed array"
        )

    def test_nullable_ref_via_any_of_emits_optional_struct(self):
        """anyOf: [{$ref: ProfileOut}, {type: null}] → 'ProfileOut?'."""
        prop = {
            "anyOf": [
                {"$ref": "#/$defs/ProfileOut"},
                {"type": "null"},
            ]
        }
        result = json_schema_to_swift_type(prop, required=True, defs=DEFS)
        assert result == "ProfileOut?", (
            f"Expected 'ProfileOut?', got '{result}' — "
            "nullable $ref via anyOf is not emitting the optional struct"
        )
