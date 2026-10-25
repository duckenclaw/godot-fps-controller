# FPS Controller (`fps_controller`)

First-person character controller: movement states, camera (bob/tilt/FOV/shake), hands viewmodel, grab controller, projectile, props and gameplay UI.

Part of the **[godot-game-kit](https://github.com/duckenclaw/godot-game-kit)** modular
template ecosystem — a set of reusable Godot 4 addons shared across FPS,
third-person, 2D sidescroller and top-down game templates.

## Install

**Git submodule (recommended)** — this repo is root-layout, so it drops straight
into a project's `addons/`:

```bash
git submodule add https://github.com/duckenclaw/godot-fps-controller addons/fps_controller
git submodule update --init
```

Then enable **FPS Controller** in *Project → Project Settings → Plugins*.

**Godot Asset Library** — an Asset-Library-compatible release (files wrapped under
`addons/fps_controller/`) is published per tagged version; search for "FPS Controller" in the
editor's AssetLib tab.

## Dependencies

godot-core, godot-components-kit, godot-inventory-kit

## Versioning

Semantic versioning via git tags (`v1.0.0`). The Asset Library entry tracks tags.

## License

MIT — see [LICENSE](LICENSE).
