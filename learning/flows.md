# Flows (call chains)

> A map, not ground truth. Verify against the cited source before repeating.

## Flow 1 — startup: how `plugins.entry_points` decides what loads (traced)

1. Any process imports `nomad.parsing.parsers`, which calls `config.load_plugins()`
   at **module import time** (`packages/nomad-FAIR/nomad/parsing/parsers.py:230`).
   Same pattern: `nomad/normalizing/__init__.py:111`,
   `nomad/datamodel/__init__.py:69`, `nomad/datamodel/metainfo/__init__.py:48`.
2. `Config.load_plugins()` (`nomad/config/models/config.py:2652`) reconciles the
   legacy `plugins.include/exclude` with `plugins.entry_points.include/exclude`;
   the legacy key wins (`config.py:2665-2685`).
3. It enumerates every installed entry point in group `nomad.plugin`
   (`config.py:2696`) and calls `entry_point.load()` on each one (`config.py:2710`)
   — **before any include/exclude filtering**. The registry key is the entry point's
   *value*, not its `pyproject.toml` key (`key = entry_point.value`,
   `config.py:2700`).
4. Loaded defaults are merged with `nomad.yaml` options and re-validated into the
   entry point's pydantic model (`config.py:2730-2736`).
5. Options whose key is not a registered entry point are popped with a warning
   (`config.py:2752-2760`).
6. Only now is the filter applied — `filtered_keys()` / `filtered_values()`
   (`nomad/config/models/common.py:153-177`). `include is None` or containing `'*'`
   means "all keys of `options`" (`common.py:157-158`), minus `exclude`.
7. `parsers.py:237-250` instantiates only the `ParserEntryPoint`s among the
   filtered values, asserts each `.load()` returns a `Parser`
   (`parsers.py:241-243`), copies `id`/`aliases`/`matching_order` onto the
   instance (`:239`, `:245-249`), and appends `TabularDataParser` +
   `ArchiveParser` unconditionally (`parsers.py:252`).

**The trap:** step 3 imports every *installed* plugin regardless of the include
list; steps 6-7 only decide what gets *instantiated*. So:

| State | Result |
|---|---|
| installed + in `include` | loads |
| installed, not in `include` | module imported, nothing instantiated — silently inactive |
| not installed, but in `include` | **silently absent** — never enumerated in step 3 |
| installed with a broken import | startup dies **even if the plugin is excluded** |

Declaration side: `[project.entry-points.'nomad.plugin']` in each plugin
(`packages/nomad-hysprint/pyproject.toml:130-141`,
`packages/nomad-tfsc-general/pyproject.toml:122-124`). The allowlist is
`nomad.yaml:30-36`.

## Flow 2 — reading an archive (traced)

1. `files.UploadFiles.get(upload_id)` — called by our plugins at
   `packages/nomad-hysprint/src/nomad_hysprint/parsers/hysprint_measurement_parser.py:85`
   and
   `packages/nomad-baseclasses/src/baseclasses/helper/utilities.py:454`.
2. `check_archive_version` sniffs magic bytes: v3 = msglc `LazyWriter.magic`,
   v2 = `b'nomad-archive-v2023'`, else v1 (`nomad/archive/utils.py:29-50`).
3. `read_archive` dispatches to the matching reader (`nomad/archive/utils.py:124-137`),
   so **v2 archives stay readable under 2.0.0**.
   `nomad/archive/converter.py:102` skips anything already v3 when repacking.

## Flow 3 — upload -> parse -> normalize -> publish (anchors verified, chain not closed)

- Parser matching during upload processing: `nomad/processing/data.py:2621`
  (target mainfile) and `nomad/processing/data.py:2918` (per mainfile).
- `match_parser` skips dot/~ files (`nomad/parsing/parsers.py:78-79`), then reads
  the first `config.process.parser_matching_size` bytes and matches on filename,
  mime type, and leading content (`parsers.py:81-95`; docstring `:63-75`).
- Normalizers are a module-level list built at import
  (`nomad/normalizing/__init__.py:111`); the domain-filtered loop is
  `nomad/client/processing.py:117-119`, CLI path `nomad/cli/parse.py:113-115`.
- Publishing is a Temporal workflow: `Upload.publish_upload`
  (`nomad/processing/data.py:2076-2090`); activity registration in
  `nomad/actions/activities/utils.py:44`, `:68`.
- Index target: `config.elastic.entries_index`, default `nomad_entries_v1`
  (`nomad/config/defaults.yaml:68`), bound as a metainfo index in
  `nomad/metainfo/elasticsearch_extension.py:719-721`; update/delete/refresh in
  `nomad/search.py:150`, `:186`, `:209`.
- **Gap:** the hop from "parsed" to `index_entries`, and the REST upload handler
  that starts the processing workflow, are not traced.

## Flow 4 — dev startup: who serves what (traced 2026-11-11)

1. `poe start` (`pyproject.toml:46-49`) runs `start-info` (a hard-coded URL print,
   `:51-53`) and then `NOMAD_SERVICES_MODE=development nomad admin run appworker
   --dev`.
2. `run_appworker(dev=True)` (`nomad/cli/admin/run.py:347-384`) forces 1 FastAPI
   worker and 1 temporal worker (`:359-361`) and starts **two
   `multiprocessing.Process`es**: `run_action_internal_worker` (`:163-183`) and
   `run_app` (`:186-317`). Nothing runs in the supervisor process; if a child exits
   non-zero the other is terminated and the parent exits (`:375-384`).
3. `run_app` binds `0.0.0.0:8000` (port = `--port` or the literal 8000;
   `config.services.api_port` is ignored, `:196-199`) and runs uvicorn on
   `nomad.app.main:app` (`:300-317`).
4. `import nomad.app.main` imports `nomad.app.static`, which mounts `/docs` and
   `/gui` (`nomad/app/static/__init__.py:73-75`, `:123-124`); the GUI folder is
   `app/static/gui` — or `run/gui_configured` if that exists (`:44-48`).
5. `config.load_plugins()` (Flow 1 step 3) calls `load()` on every installed
   `nomad.plugin` entry point — including whichever one serves the new GUI. The
   `nomad-gui` wheel registers `GUIAPIEntryPoint(prefix='gui/v2')`
   (`nomad_gui/apis/__init__.py:498-502`); its `load()` copies the packaged build
   `nomad_gui/apis/static` -> `run/gui` rewriting `/prefix-to-replace`
   (`:51-101`, `:413-427`) and returns a FastAPI app.
6. **Mounting is filtered**: `nomad/app/main.py:246-259` iterates
   `config.plugins.entry_points.filtered_values()` and mounts each `APIEntryPoint`
   at `join_path(prefix)`. `filtered_values()` returns exactly our `include` list
   when it is concrete (`nomad/config/models/common.py:153-177`). Since
   `nomad.yaml:30-42` lists only `nomad_tfsc_general.*`, the v2 GUI app is **not
   mounted in this deployment** even though the wheel is installed. Whatever is
   not mounted falls through to `app.mount(app_base, static_files_app)`
   (`main.py:282`) and the generic 404 handler (`:285-336`).
7. Startup/lifespan (`nomad/app/main.py:69-123`): `import_all_parsers()`,
   `entry_type.reload_quantities_dynamic()`,
   `GuiFiles.bootstrap(generate_gui_artifacts_js(), get_gui_config())` (`:90`),
   `infrastructure.setup()` (Mongo/ES), async Mongo client, `FastAPICache`,
   `apps_router.initialize_search_quantities()`, `check_api_secret()`, then
   `get_client()` + `setup_server_stats()` for Temporal (`:104-107`). If Temporal is
   unreachable the hook **raises** and uvicorn exits.
8. Step 7 is what materialises `/gui/env.js` and `/gui/artifacts.js`
   (`nomad/app/static/__init__.py:78-124`); `artifacts.js` is a temp file in
   `config.fs.tmp` (`nomad/cli/dev.py:212-250`) deleted on shutdown
   (`main.py:120-123`).

Only the *internal* temporal worker runs here; parsers/normalizers live in
`poe cpuworker` / `poe gpuworker` (`pyproject.toml:55-61`).

## Flow 5 — legacy GUI dev server -> `env.js` (traced 2026-11-11)

1. `poe gui` -> `yarn run start` with `cwd=packages/nomad-FAIR/gui`, `HOST=""`
   (`pyproject.toml:90-102`) -> CRA dev server on `:3000`.
2. `gui/public/index.html:46-47` loads `%REACT_APP_BACKEND_URL%/gui/env.js` and
   `.../gui/artifacts.js`.
3. `REACT_APP_BACKEND_URL` comes from `gui/.env.development:1`, generated by
   `poe gui-env` from `config.ui.app_base` (`nomad/cli/dev.py:429-433`,
   `nomad/config/models/config.py:2586-2588`), i.e. CRA-baked at start — changing
   the API port means regenerating + restarting.
4. Those two URLs hit the running API, where `GuiFiles.get_response` answers from
   memory (Flow 4 step 8) with `window.nomadEnv = {...}` /
   `window.nomadArtifacts = {...}` (`nomad/cli/dev.py:396-426`, `:186-250`).
5. `gui/src/config.js:91-95` then reads `window.nomadEnv.appBase` — **if the API is
   unreachable (or answers 500 because `GuiFiles.bootstrap` never ran, `static/__init__.py:87-89`),
   the two scripts never set `window.nomadEnv`, it stays `{}` and the app throws**
   (`:94`). This is the only reason the legacy GUI needs the API.

## Not traced yet

- GUI query -> app worker API handler -> Elasticsearch.
- `apps` (Voila) entry points: `nomad/app/v1/routers/apps.py:457-459` caches
  `AppEntryPoint`s, but the request -> notebook execution path is unread.
