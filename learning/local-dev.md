# Running and debugging it locally

> A map, not ground truth. Ports, flags and paths below were verified on
> 2026-11-11 against this checkout; re-check before repeating.

## Two GUIs, two ports (verified)

| GUI | Served by | URL | Assets from |
|---|---|---|---|
| legacy (React/CRA) | `yarn start` dev server, `poe gui` (`pyproject.toml:90-102`) | `http://localhost:3000` | `packages/nomad-FAIR/gui` source, hot reload |
| new ("v2", React build) | the **API**, via the `nomad-gui` plugin | `http://localhost:8000/nomad-oasis/gui/v2/` | `nomad_gui/apis/static` (prebuilt, shipped in the wheel) |

`README.md:298-300` states the same split. The legacy GUI still calls the API on
`:8000` for everything except its own bundle, so **the API must be up even when you
only open `:3000`** — see the `env.js` note below.

`nomad-gui>=2.0.0b2` is a hard dependency of the distro (`pyproject.toml:10`); the
installed wheel is `2.0.0` and holds **no schema packages of interest, only `apis/`
+ `schema_packages/{demo,exercise,values_test}_schema.py`**. The new GUI is an *API
entry point*, not a `nomad/app/static` folder:

- `GUIAPIEntryPoint(prefix='gui/v2')` — `nomad_gui/apis/__init__.py:498-502`
- mount path = `config.services.api_base_path` + `/gui/v2`
  (`get_api_mount_path`, `nomad_gui/apis/__init__.py:352-355`)
- on `load()` it copies `nomad_gui/apis/static` -> `run/gui` and rewrites the
  `/prefix-to-replace` placeholder with the public base path
  (`prepare_gui_runtime_files`, `:51-101`; `static/index.html` contains it 51
  times), guarded by `run/gui.prepare.lock` + `run/gui.prepare.stamp`
  (`:56-64`). The stamp currently reads `/nomad-oasis/gui/v2`, so the plugin *has*
  been loaded (i.e. `nomad.app.main` imported with it included) at least once in this
  checkout — but see the include-filter caveat below.
- `config.js` and `metainfo.js` are generated in memory and served by the plugin
  (`:390-403`); unknown routes fall back to `index.html` for the SPA (`:439-441`).

**Caveat:** API entry points are mounted only if they survive the include filter
(`nomad/app/main.py:246-259`, `nomad/config/models/common.py:153-177`). Our
`nomad.yaml:30-42` lists only `nomad_tfsc_general.*`, so **`gui/v2` is currently not
mounted** even though the wheel is installed — `/nomad-oasis/gui/v2/` would fall
through to the catch-all mount and 404. Tracked in `open-questions.md`.

## Legacy GUI needs `env.js` from the *running* API (the classic crash)

1. `gui/public/index.html:46-47` loads `<REACT_APP_BACKEND_URL>/gui/env.js` and
   `.../gui/artifacts.js`.
2. `REACT_APP_BACKEND_URL` is baked in at dev-server start from
   `gui/.env.development:1` = `http://localhost:8000/nomad-oasis`. That file is
   produced by `poe gui-env` = `python -m nomad.cli dev gui-env`
   (`pyproject.toml:72-74`), which just prints
   `REACT_APP_BACKEND_URL={config.ui.app_base}` (`nomad/cli/dev.py:429-433`).
   `app_base` is `{scheme}://{api_host}:{api_port}{route_prefix}`
   (`nomad/config/models/config.py:2586-2588`) from defaults
   `api_host: localhost`, `api_port: 8000`, `api_base_path: /nomad-oasis`
   (`nomad/config/defaults.yaml:195-197`), where `route_prefix` == `api_base_path`
   (`config.py:297-306`).
3. Both files are **synthesised in memory by the API's lifespan hook**, never read
   from disk: `GuiFiles.bootstrap(generate_gui_artifacts_js(), get_gui_config())`
   (`nomad/app/main.py:90`) -> `GuiFiles.get_response` answers exactly
   `env.js`/`artifacts.js` (`nomad/app/static/__init__.py:78-124`).
   `artifacts.js` is a **temp file** under `config.fs.tmp`, deleted on shutdown
   (`nomad/cli/dev.py:212-250`, `nomad/app/main.py:120-123`).
4. `get_gui_config()` emits `window.nomadEnv = {...}` with `appBase` first
   (`nomad/cli/dev.py:396-426`).

Consequence: **API down (or 500 because `GuiFiles.bootstrap` never ran,
`static/__init__.py:87-89`) => the two scripts never set `window.nomadEnv` =>
`window.nomadEnv.appBase.replace(...)` throws** (`gui/src/config.js:91-94`) and the
page stays blank. Symptom, not a GUI bug. Checks:

```bash
curl -s  http://localhost:8000/nomad-oasis/gui/env.js | head -3   # window.nomadEnv = {...
curl -sI http://localhost:8000/nomad-oasis/gui/artifacts.js | head -1
```

Changing `api_port`/`api_base_path` requires re-running `poe gui-env` **and**
restarting the yarn dev server (CRA inlines `.env.*` at start). Note
`poe start-info` (`pyproject.toml:51-53`) prints a hard-coded string: it is not a
readiness probe.

## What `nomad admin run app` actually does (verified)

`nomad/cli/admin/run.py:186-199`:

- `config.meta.service = 'app'`
- host = `--host` or `config.services.api_host` or `0.0.0.0`
- **port = `--port` or literally `8000`** — `config.services.api_port` is *ignored*,
  with a `TODO` at `:197-199`. An `api_port: 8001` in `nomad.yaml` changes only the
  GUI/env URLs, not the bind port.
- `--with-gui` copies `nomad/app/static/gui` -> `run/gui_configured`, rewriting
  `/nomad-oasis` in every js/html/json/css file, then sets
  `config.ui.app_base = config.services.route_prefix` (`:201-242`). In this checkout
  `nomad/app/static/gui` is **empty**, so `--with-gui` copies nothing; the GUI to
  serve is the v2 one from the plugin. `static/__init__.py:44-48` prefers
  `run/gui_configured` over `app/static/gui` when it exists.
- uvicorn: `Config('nomad.app.main:app', log_level='info', ...)` + `Server.run()`
  (`:300-317`).

`nomad admin run appworker --dev` (`:347-384`) does **not** run the app in-process:
it starts two `multiprocessing.Process`es — `run_action_internal_worker` and
`run_app` — and supervises them; `--dev` only forces `fastapi_workers=1` and
`temporal_pool_size=1` (`:359-361`). So breakpoints in API code there need
child-process debugging.

## Logging gotcha: the uvicorn banner is swallowed

- `cli.py:88-94` sets `config.services.console_log_level` to `DEBUG`/`INFO`/
  **`WARNING` (the default)** and applies it to the root handlers
  (`nomad/utils/__init__.py:164-177`; default `30` in `defaults.yaml:200`).
- uvicorn's loggers get level INFO from `Config(log_level='info')`
  (`run.py:305-313`) but have **no handlers of their own** (`log_config` stays
  `None` without `--log-config`), so their records propagate to the root handler,
  whose *handler* level still filters at WARNING.
- Net effect: "Uvicorn running on http://0.0.0.0:8000" and the startup/shutdown
  lines never show for a plain `nomad admin run app`. NOMAD's own `get_logger`
  output is filtered the same way.

Pass `-v` (or `--debug`) **before** the subcommand: `nomad -v admin run app`.

## `.vscode/launch.json` in this workspace (verified)

| Config | Shape | Notes |
|---|---|---|
| `app`, `worker`, `appworker`, `hub` | `program: .venv/bin/nomad` | no `-v`, no `cwd`, `justMyCode: false` |
| `API debug (uvicorn)` | `nomad -v admin run app`, `justMyCode: true`, `PYDEVD_DISABLE_FILE_VALIDATION=1`, `DEBUGPY_LOG_DIR=/tmp/debugpy-logs` | the config to use for API breakpoints (`launch.json:84-98`) |
| `API debug (appworker, incl. worker)` | `appworker --dev` + `subProcess: true` | marked UNTESTED (`launch.json:99-113`); API runs in a child process |
| upstream default (replaced) | `"module": "uv"`, `"args": ["run","poe","start"]` | still visible in `git diff .vscode/launch.json`; that debugs `uv`, not Python |

`program: .venv/bin/nomad` is the same console script `poe start` calls, so little
is lost by skipping `uv run` (uv only does `sync` + `PATH` there). What you lose
from `poe start`: the `NOMAD_SERVICES_MODE=development` env (set explicitly in the
debug configs) and the hard-coded URL print.

## debugpy noise seen here (observed, root cause open)

`FileNotFoundError: [Errno 2] ... '/home/a4864/.local/lib/python3.12'` when a
client attaches. Verified facts:

- that path is the `posix_user`-scheme stdlib dir, i.e. the parent of
  `site.getusersitepackages()`; the venv disables user site and the dir does not
  exist;
- pydevd's `FilesFiltering._get_default_library_roots()` adds
  `site.getusersitepackages()` / `site.getsitepackages()` **without checking they
  exist** (`pydevd_filtering.py:142-197`, Kylin-bundled debugpy 1.8.1) — but it adds
  the `.../site-packages` path, *not* the parent, so it is not the exact source;
- `python -m debugpy --listen ... --wait-for-client .venv/bin/nomad admin run app`
  reaches `wait_for_client()` without that error, so it only appears once a real
  client pushes its configuration.

Safe mitigations: `PYDEVD_DISABLE_FILE_VALIDATION=1` (honoured by pydevd in
`pydevd_file_utils.py`) and `DEBUGPY_LOG_DIR=<dir>` to capture the real traceback.
This workspace has **three** Python-ish extensions installed
(`ms-python.python`, `ms-python.debugpy`, `kylinideteam.kylin-python`); the Kylin
fork's older debugpy is the one that got loaded, so `"type": "python"` is not
guaranteed to behave like `"type": "debugpy"`.

## Preconditions before any of the above works

| Need | Check |
|---|---|
| MongoDB / Elasticsearch / Temporal up | `docker compose ps` (`docker-compose.yaml`) |
| `nomad.yaml` in CWD with `services.mode: development` | `nomad.yaml:2`; config comes from `NOMAD_CONFIG` **or** CWD (`nomad/config/__init__.py:52,69`) |
| plugin entry points enabled | `nomad.yaml:30-42` |
| `gui/.env.development` matches API port/prefix | `poe gui-env` |
| `gui/node_modules` | `poe gui-install` |
| Temporal reachable, or the API exits | `nomad/app/main.py:104-113` — a failed `get_client()` logs "Failed to connect to temporal" and **raises**, so uvicorn dies |
