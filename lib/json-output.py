#!/usr/bin/env python3
"""Encode NUL-delimited binbox records into versioned JSON envelopes."""

from __future__ import annotations

import json
import sys
from pathlib import Path


SCHEMA_VERSION = 1


def envelope(data, *, ok=True, warnings=None, error=None):
    return {
        "schema_version": SCHEMA_VERSION,
        "ok": ok,
        "data": data,
        "warnings": warnings or [],
        "error": error,
    }


def fields(width: int) -> list[list[str]]:
    raw = sys.stdin.buffer.read().split(b"\0")
    if raw and raw[-1] == b"":
        raw.pop()
    values = [value.decode("utf-8", errors="surrogateescape") for value in raw]
    if len(values) % width:
        raise SystemExit(f"invalid record stream: {len(values)} fields for width {width}")
    return [values[index : index + width] for index in range(0, len(values), width)]


def projects():
    items = [{"path": row[0], "name": Path(row[0]).name} for row in fields(1)]
    return envelope({"projects": items})


def sessions():
    items = []
    for session_id, name, windows, attached, created_at in fields(5):
        items.append(
            {
                "id": session_id,
                "name": name,
                "windows": int(windows),
                "attached": int(attached) > 0,
                "created_at_unix": int(created_at),
                "state_source": "tmux",
            }
        )
    return envelope({"sessions": items})


def agents():
    items = []
    for row in fields(11):
        (
            target,
            kind,
            state,
            path,
            title,
            uptime,
            context,
            request,
            current,
            pane_id,
            command,
        ) = row
        items.append(
            {
                "id": f"legacy:{pane_id}",
                "agent_kind": kind,
                "state": state,
                "backend": "tmux",
                "backend_ref": target,
                "pane_id": pane_id,
                "command": command,
                "path": path,
                "title": title,
                "uptime": uptime,
                "context": None if context == "-" else context,
                "request_summary": None if request == "-" else request,
                "current": current == "1",
                "state_source": "scrape",
            }
        )
    order = {"waiting": 0, "running": 1, "idle": 2}
    items.sort(key=lambda item: (order.get(item["state"], 9), item["agent_kind"], item["backend_ref"]))
    return envelope({"agents": items})


def doctor():
    items = []
    warnings = []
    missing_core = []
    for name, scope, description, available, path, hint in fields(6):
        is_available = available == "1"
        item = {
            "name": name,
            "scope": scope,
            "description": description,
            "available": is_available,
            "path": path or None,
            "recovery": hint or None,
        }
        items.append(item)
        if not is_available:
            if scope == "core":
                missing_core.append(name)
            else:
                warnings.append(f"optional capability unavailable: {name}")
    if missing_core:
        return envelope(
            {"capabilities": items},
            ok=False,
            warnings=warnings,
            error={
                "code": "CORE_DEPENDENCY_MISSING",
                "message": "required binbox dependencies are missing",
                "details": {"commands": missing_core},
            },
        )
    return envelope({"capabilities": items}, warnings=warnings)


COMMANDS = {
    "projects": projects,
    "sessions": sessions,
    "agents": agents,
    "doctor": doctor,
}


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        print("usage: json-output.py projects|sessions|agents|doctor", file=sys.stderr)
        return 2
    result = COMMANDS[sys.argv[1]]()
    json.dump(result, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
