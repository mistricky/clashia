# AGENTS.md — Clashia Plugin (Noctalia Shell)

## Project Overview

A Noctalia Shell plugin built with QML (Qt Quick) on the Quickshell runtime.
Installed via symlink or copy to `~/.config/noctalia/plugins/clashia/`.

**No build step. No tests. No linter.** QML is interpreted at runtime by Quickshell.

## Validation

There is no compile or build command. Validation is done by reloading the shell:

```bash
# Restart Quickshell to pick up QML changes
killall quickshell; quickshell -c noctalia-shell &

# Or with systemd (if configured)
systemctl --user restart noctalia-shell
```

After editing any `.qml` file, verify syntax by checking brace matching:

```bash
python3 -c "
with open('FILE.qml') as f:
    c = f.read()
s = []
for i, ch in enumerate(c):
    if ch == '{': s.append(i)
    elif ch == '}':
        if not s: print(f'ERROR: unmatched }} at line {c[:i].count(chr(10))+1}'); break
        s.pop()
for p in s: print(f'ERROR: unclosed {{ at line {c[:p].count(chr(10))+1}')
if not s: print('OK')
"
```

Runtime errors appear in the journal or stdout as `ERROR qml:` lines.

## File Structure

```
manifest.json              # Plugin manifest (id, version, entryPoints, defaultSettings)
Main.qml                   # Plugin entry — IPC handlers
BarWidget.qml              # Status bar icon button
Panel.qml                  # Panel UI (opened from bar/control center)
ControlCenterWidget.qml    # Control center quick-access button
DesktopWidget.qml          # Draggable desktop widget
DesktopWidgetSettings.qml  # Per-instance desktop widget settings
Settings.qml               # Global plugin settings UI
i18n/*.json                # Translation files (en.json is the base)
logo.svg / logo_dark.svg   # Theme-aware logo assets
```

## Entry Points (manifest.json)

Each entry point maps to a QML file. The shell injects `pluginApi` into every component.

| Key                      | File                       | Root Type                |
|--------------------------|----------------------------|--------------------------|
| `main`                   | Main.qml                   | Item                     |
| `barWidget`              | BarWidget.qml              | NIconButton              |
| `panel`                  | Panel.qml                  | Item                     |
| `controlCenterWidget`    | ControlCenterWidget.qml    | NIconButtonHot           |
| `desktopWidget`          | DesktopWidget.qml          | DraggableDesktopWidget   |
| `desktopWidgetSettings`  | DesktopWidgetSettings.qml  | ColumnLayout             |
| `settings`               | Settings.qml               | ColumnLayout             |

## QML Code Style

### Indentation & Formatting

- **2-space indentation**, no tabs.
- Blank line between property blocks, signal handlers, and child elements.
- No trailing whitespace.

### Component Structure Order

1. `id` declaration
2. Injected properties (`property var pluginApi: null`)
3. Widget/screen properties
4. Computed/readonly properties
5. Visual properties (color, size, radius, etc.)
6. `Component.onCompleted` / lifecycle
7. Child elements
8. Signal handlers (`onClicked`, etc.)
9. Functions (`function saveSettings()`)

### Property Declarations

```qml
// Injected — always nullable
property var pluginApi: null

// Config shorthand — use ?? for null-coalescing, || for falsy-coalescing
property var cfg: pluginApi?.pluginSettings || ({})
property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

// Derived — use readonly when not reassigned
readonly property string iconColorKey: cfg.iconColor ?? defaults.iconColor
```

### Imports

Order: Qt modules → Quickshell → qs.Commons → qs.Services.* → qs.Modules.* → qs.Widgets

```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets
```

### Naming

- Component ids: `camelCase` (`id: root`, `id: panelContainer`)
- Properties: `camelCase` (`contentPreferredWidth`)
- Functions: `camelCase` (`saveSettings()`)
- i18n keys: `dot.separated.kebab-case` (`"settings.iconColor.label"`)

## Noctalia Plugin API

Every component receives `pluginApi` via injection. Key members:

```
pluginApi.pluginId           — Plugin identifier string
pluginApi.pluginDir          — Absolute path to plugin directory
pluginApi.pluginSettings     — Read/write settings object
pluginApi.manifest           — Parsed manifest.json
pluginApi.saveSettings()     — Persist settings to disk
pluginApi.tr("key")          — Plugin-scoped i18n translation
pluginApi.openPanel(screen, anchor?)   — Open the panel
pluginApi.togglePanel(screen, anchor?) — Toggle the panel
pluginApi.panelOpenScreen    — Screen where panel is currently open
pluginApi.withCurrentScreen(callback)  — Execute with current screen
```

## Noctalia Framework Modules

| Import             | Key Singletons / Types                                    |
|--------------------|-----------------------------------------------------------|
| `qs.Commons`       | `Style`, `Color`, `Logger`, `Settings`, `I18n`            |
| `qs.Services.UI`   | `BarService`, `PanelService`, `ToastService`              |
| `qs.Widgets`       | `NText`, `NButton`, `NIcon`, `NIconButton`, `NComboBox`, `NTextInput`, `NPopupContextMenu` |

### Theme Detection

```qml
Settings.data.colorSchemes.darkMode  // bool — true if dark mode active
```

### Common Style Tokens

```
Style.marginS / marginM / marginL        — Spacing
Style.radiusM / radiusL                   — Border radius
Style.fontSizeS / fontSizeM / fontSizeL / fontSizeXXL — Font sizes
Style.uiScaleRatio                        — Display scaling factor
Style.capsuleColor / capsuleBorderColor   — Bar capsule theming
Color.mSurface / mSurfaceVariant          — Surface colors
Color.mOnSurface / mOnSurfaceVariant      — Text colors
Color.mPrimary                            — Accent color
```

## IPC

Defined via `IpcHandler` in Main.qml. Target format: `plugin:<plugin-id>`.

```bash
# Call a function
qs -c noctalia-shell ipc call plugin:clashia setMessage "Hello"
qs -c noctalia-shell ipc call plugin:clashia toggle

# List all IPC targets
qs -c noctalia-shell ipc show
```

## i18n

- Base language: `i18n/en.json`
- Key format: nested dot-path (`"settings.message.label"`)
- Access: `pluginApi?.tr("key")` for plugin strings, `I18n.tr("key")` for system strings
- Partial translations are fine — missing keys fall back to `en.json`

## Common Pitfalls

- **Always null-check `pluginApi`** — it's injected asynchronously and may be null on first render.
- **Brace matching** — QML has no compile step; mismatched braces produce cryptic runtime errors.
- **SVG rendering** — Use `sourceSize.width/height` matching the display size to avoid aliasing. Add `smooth: true` and `antialiasing: true`.
- **File references** — Use `pluginApi.pluginDir + "/filename"` for assets; relative paths don't work reliably.
- **Settings persistence** — Mutate `pluginApi.pluginSettings.*` then call `pluginApi.saveSettings()`. Don't forget the save call.
