import configparser
import json
import os
import re
import subprocess
import sys
from pathlib import Path


APP_PATHS = [Path("/usr/share/applications"), Path.home() / ".local/share/applications"]
ICON_ROOTS = [Path.home() / ".local/share/icons", Path("/usr/share/icons"), Path("/usr/share/pixmaps")]
ICON_EXTS = (".png", ".svg", ".xpm")
GENERIC_PARTS = {"app", "application", "bin", "desktop", "http", "https", "remote", "helper"}


def normalize(value: str) -> str:
    value = (value or "").strip().lower()
    value = re.sub(r"\.(desktop|bin|appimage|exe)$", "", value)
    value = re.sub(r"[^a-z0-9]+", "", value)
    return value


def split_keys(text: str) -> list[str]:
    keys: list[str] = []
    for part in re.split(r"[\\/. _-]+", text or ""):
        part_norm = normalize(part)
        if part_norm and part_norm not in keys:
            keys.append(part_norm)
    return keys


def resolve_icon(icon: str) -> str:
    icon = (icon or "").strip()
    if not icon:
        return ""

    path = Path(icon)
    if path.is_absolute() and path.exists():
        return str(path)

    for root in ICON_ROOTS:
        if not root.exists():
            continue

        if root.name == "pixmaps":
            for ext in ICON_EXTS:
                candidate = root / f"{icon}{ext}"
                if candidate.exists():
                    return str(candidate)
            continue

        try:
            result = subprocess.run(
                [
                    "find",
                    str(root),
                    "(",
                    "-path",
                    f"*/apps/{icon}.*",
                    "-o",
                    "-path",
                    f"*/{icon}.*",
                    ")",
                    "-print",
                    "-quit",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
        except Exception:
            continue

        found = [line for line in result.stdout.splitlines() if line.strip()]
        if found:
            return found[0]

    return ""


def lookup_process_icon(raw: str) -> dict:
    target_primary = normalize(raw)
    target_parts = [part for part in split_keys(raw) if len(part) >= 4 and part not in GENERIC_PARTS]
    tried_keys = [target_primary] if target_primary else []
    for part in target_parts:
        if part not in tried_keys:
            tried_keys.append(part)

    best = {
        "process": raw,
        "icon": "",
        "matchedKey": "",
        "matchedBy": "",
        "triedKeys": tried_keys,
        "score": -1,
    }

    for base in APP_PATHS:
        if not base.exists():
            continue

        for file in base.glob("*.desktop"):
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                parser.read(file, encoding="utf-8")
            except Exception:
                continue

            if "Desktop Entry" not in parser:
                continue

            entry = parser["Desktop Entry"]
            exec_value = entry.get("Exec", "")
            first = exec_value.replace("\\ ", " ").split()[0].strip('"').strip("'") if exec_value else ""
            values = [entry.get("Name", ""), file.stem, os.path.basename(first), first]

            matched_key = ""
            matched_by = ""
            score = -1

            for value in values:
                exact = normalize(value)
                if target_primary and exact == target_primary:
                    matched_key = target_primary
                    matched_by = "exact"
                    score = 3
                    break

                for part in split_keys(value):
                    if target_primary and part == target_primary:
                        matched_key = target_primary
                        matched_by = "part-exact"
                        score = 2
                        break
                    if part in target_parts:
                        matched_key = part
                        matched_by = "segment"
                        score = max(score, 1)

                if score >= 2:
                    break

            if score < 0:
                continue

            icon = resolve_icon(entry.get("Icon", ""))
            if not icon:
                continue

            if score > best["score"]:
                best = {
                    "process": raw,
                    "icon": icon,
                    "matchedKey": matched_key,
                    "matchedBy": matched_by,
                    "triedKeys": tried_keys,
                    "score": score,
                }
                if score == 3:
                    result = dict(best)
                    result.pop("score", None)
                    return result

    result = dict(best)
    result.pop("score", None)
    return result


def main() -> None:
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    print(json.dumps(lookup_process_icon(raw), ensure_ascii=False))


if __name__ == "__main__":
    main()
