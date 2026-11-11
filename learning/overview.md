# Overview

> A map, not ground truth. Read the cited source before repeating any claim
> here. If the code disagrees, the code wins — fix this file.

## What this repo is

A NOMAD "dev distribution": a uv workspace that installs NOMAD (nomad-lab) plus
plugin packages in editable mode, so local edits take effect without reinstall
(`README.md:3-11`).

## Versions (resolved, not declared)

- `nomad-lab[parsing, infrastructure]>=1.4.2` (`pyproject.toml:12`) is a **floor,
  not a pin**. `nomad-lab = { workspace = true }` (`pyproject.toml:22`) makes the
  local submodule win, and `packages/nomad-FAIR/CHANGELOG.md:1` is
  **2.0.0 (2026-10-18)**. So this repo runs nomad-lab **2.0.0**, not 1.4.x — do not
  reason from the 1.4.3 changelog.
- `[parsing]` is an **empty extra** in 2.0.0
  (`packages/nomad-FAIR/pyproject.toml:64`), so every non-core parser must come
  from a plugin package that is an actual dependency.
- Interpreter: `.python-version` = `3.12.8`. Every package here declares
  `requires-python = ">=3.10"` (`pyproject.toml:6`,
  `packages/nomad-FAIR/pyproject.toml:14`).
- `uv` resolves the whole workspace into `uv.lock` + one shared `.venv/`
  (`pyproject.toml:17-18`). Task runner: `poethepoet` (`pyproject.toml:40-61`).

## Infra (pinned images in `docker-compose.yaml`)

| Service | Image | Port |
|---|---|---|
| Elasticsearch | `elasticsearch:7.17.27` (`docker-compose.yaml:24`) | 9200 |
| MongoDB | `mongo:5.0.6` (`docker-compose.yaml:42`) | 27017 |
| Temporal | `temporalio/temporal:1.6.1` (`docker-compose.yaml:57`) | 7233 (UI 8233) |

Keycloak is not run locally; the config points at realm `fairdi_nomad_test`
(`nomad.yaml:5-6`).

ES 7.17 here is **deprecated but working**, by design: nomad-lab ships two clients
(`elasticsearch>=9,<10` **and** `elasticsearch7>=7.17,<8`,
`packages/nomad-FAIR/pyproject.toml:22-23`) and picks one via
`config.elastic.version`, which defaults to `'7'`
(`packages/nomad-FAIR/nomad/config/defaults.yaml:73`) — matching the container.
Moving to ES 9 means changing the image **and** that key.

## Entry points (how you start things)

| Task | Command | Notes |
|---|---|---|
| `poe start` | `nomad admin run appworker --dev` | app + internal temporal worker as **two child processes**; `NOMAD_SERVICES_MODE=development` (`pyproject.toml:46-49`). API on `:8000` |
| `poe start-info` | `python -c "print('NOMAD GUI: ...')"` | hard-coded URL print, not a health check (`pyproject.toml:51-53`) |
| `poe cpuworker` | `nomad admin run action-cpu-worker` | **parsers and normalizers run here**, not in the app worker (`pyproject.toml:55-57`) |
| `poe gpuworker` | `nomad admin run action-gpu-worker` | (`pyproject.toml:59-61`) |
| `poe hub` | `nomad admin run hub` | JupyterHub (`pyproject.toml:86-88`) |
| `poe gui` | `yarn run start` in `packages/nomad-FAIR/gui` | legacy GUI dev server on `:3000` (`pyproject.toml:90-102`); `poe gui build` builds it |
| `poe gui-env` | `python -m nomad.cli dev gui-env` -> `gui/.env.development` | writes `REACT_APP_BACKEND_URL={config.ui.app_base}` (`pyproject.toml:72-74`) |
| `poe gui-setup` | `gui-env` + `gui-install` (yarn) | one-time (`pyproject.toml:104-117`) |
| `poe docker` / `poe config` | compose up / write a minimal `nomad.yaml` | (`pyproject.toml:42-43`, `63-70`) |

Ports, the `env.js`/`artifacts.js` generation, the swallowed uvicorn banner and the
VSCodium debug configs are written up in `local-dev.md`; the traced call chain is
`flows.md` Flow 4 (API/v2 GUI) and Flow 5 (legacy GUI).

## Config resolution (verified; contradicts the obvious guess)

- Config files come from `NOMAD_CONFIG` (pathsep-separated) or `nomad.yaml` in the
  CWD (`packages/nomad-FAIR/nomad/config/__init__.py:52`, `:69`).
- Setting `NOMAD_CONFIG` **replaces** the default `nomad.yaml`; to layer you must
  name both files (docstring at `.../config/__init__.py:61-64`).
- Named files merge in order, later wins (`.../config/__init__.py:94-99`);
  precedence is env > yaml > defaults (`.../config/__init__.py:30-32`).
- **`packages/<plugin>/nomad.yaml` is not auto-discovered** — it does nothing
  unless named in `NOMAD_CONFIG`. See `open-questions.md`.
- Defaults are also filtered from here: `defaults.yaml:464-467` ships a default
  `plugins.entry_points.exclude`.

## Directory map

| Path | Purpose |
|---|---|
| `packages/nomad-FAIR` | upstream nomad-lab submodule: Python backend (`nomad/`) + GUI (`gui/`) |
| `packages/nomad-baseclasses` | local HZB plugin: shared base sections/schemas |
| `packages/nomad-hysprint` | local HZB plugin: HySprint parsers/experiments — **commented out** of deps (`pyproject.toml:11`, `:24`) and of the include list (`nomad.yaml:32-36`), so currently inactive |
| `packages/nomad-tfsc-general` | local HZB plugin: TFSC general parsers — an active dependency (`pyproject.toml:14`, `:23`) with its entry points enabled (`nomad.yaml:37-42`) |
| `nomad.yaml` | this deployment's NOMAD config, incl. plugin entry points |
| `scripts/prep.sh` | environment prep helper |
| `run/`, `data/`, `.volumes/` | runtime state / container volumes; `run/gui` is the rendered **v2 GUI build** (copied by the `nomad-gui` plugin, see `local-dev.md`), `run/gui.prepare.stamp` records the base path it was rendered for, `run/gui_configured` is the `--with-gui` copy of `nomad/app/static/gui` |
| `.cline/skills/update-distro/SKILL.md` | our documented fork-update workflow (merge rules, per-plugin test commands, known pre-existing failures) |
| `nomad.yaml2`, `pyproject.toml2` | *gone as of 2026-11-11* — the earlier stale copies of the older upstream template have been deleted; only `nomad.yaml` + `pyproject.toml` remain at the root |
| `learning/` | these notes: `overview.md` (what/where), `abstractions.md` (models), `flows.md` (call chains), `local-dev.md` (running + debugging), `open-questions.md`, `quiz-log.md` |

## Composition, in one paragraph

The repo root contains **no application code**. A plugin is active only if
(a) it is installed via `pyproject.toml` deps + `uv.lock`, and (b) its entry point
survives the `plugins.entry_points.include` filter in `nomad.yaml`. `nomad-lab`
never imports our plugins. See `flows.md` Flow 1 for the traced mechanism and the
silent-failure table that follows from it.

## Deployment quirks worth remembering (verified 2026-11-11)

- The distro depends on `nomad-gui>=2.0.0b2` (`pyproject.toml:10`). That wheel is not
  a schema plugin: it registers `GUIAPIEntryPoint(prefix='gui/v2')`
  (`nomad_gui/apis/__init__.py:498-502`), whose `load()` renders its bundled build
  into `run/gui`. API entry points are mounted from
  `entry_points.filtered_values()` (`nomad/app/main.py:246-259`), and our `include`
  list holds only `nomad_tfsc_general.*` (`nomad.yaml:30-42`) — so **the v2 GUI is
  currently not mounted**, installed or not. Enabling it needs
  `nomad_gui.apis:gui_api` in that include list.
- `packages/nomad-FAIR/nomad/app/static/gui` is **empty** in this checkout, so
  `nomad admin run app --with-gui` copies an empty tree
  (`nomad/cli/admin/run.py:201-216`); the legacy GUI can only be reached through the
  yarn dev server (`poe gui`) on `:3000` against a running API.
- The API's HTTP port is not configurable via `nomad.yaml` (`api_port` is ignored,
  `run.py:196-199`), while the GUI's `.env.development`/`env.js` URLs *are* derived
  from it (`config.py:2586-2588`) — regenerate with `poe gui-env` if you ever move
  the port.

## Not explored yet

- Which schema sections the HZB plugins extend, and the physical meaning of each.
- Experiment-entry / measurement classes and `mainfile` conventions.
- The GUI query -> API handler -> Elasticsearch path.
- The last hop of the pipeline: archive write -> `index_entries` call site.
