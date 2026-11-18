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

## Flow 6 — measurement upload: file name -> entry, sample link, structured entry (traced 2026-11-18)

Start: one file `PERS_INX_BO_3_C-10_cell3_2.mpp` in an upload that also contains the
sample whose `lab_id` is `PERS_INX_BO_3_C-10`.

1. `TFSCGeneralParser.parse` (`packages/nomad-tfsc-general/src/nomad_tfsc_general/parsers/tfsc_general_measurement_parser.py:89`)
   picks the section class from the extension (`:97-107`; `.mpp` ->
   `TFSC_General_SimpleMPPTracking` at `:106-107`).
2. `mainfile_split = os.path.basename(mainfile).split('.')` (`:90`) ->
   `search_id = mainfile_split[0]` (`:111`) = `PERS_INX_BO_3_C-10_cell3_2`.
   **Everything downstream keys on this string.**
3. `archive.metadata.entry_name = os.path.basename(mainfile)` (`:109`) -> the GUI
   "Name" column keeps the full name incl. extension (`entry_name` is a search
   quantity, `nomad-FAIR/nomad/datamodel/datamodel.py:621` on `EntryMetadata`; ES doc
   field built at `nomad/processing/data.py:281`).
4. `set_sample_reference(archive, entry, search_id, archive.metadata.upload_id)` (`:112`)
   -> `baseclasses/helper/utilities.py:339` -> `search_sampleid_in_upload` (`:329-336`)
   queries ES `{'results.eln.lab_ids': 'PERS_INX_BO_3_C-10_cell3_2', 'upload_id': ...}`
   -> 0 hits -> `return` at `:344`. **`entry.samples` stays None, nothing logged.**
5. `entry.name = f'{search_id} {".".join(mainfile_split[1:-1])}'` (`:114`) ->
   `"PERS_INX_BO_3_C-10_cell3_2 "` (extension dropped, trailing space kept). Core
   `BaseSection.normalize` then mirrors it: `entry_name` is overwritten by `self.name`
   when the section is `archive.data` and an `EntryData`
   (`nomad-FAIR/nomad/datamodel/metainfo/basesections/v1.py:253-255`), and `name` is
   appended to `results.eln.names` (`v1.py:277-280`). So the structured entry's GUI name
   replaces the raw basename from step 3 — and only the **trailing space** tells the two
   `.mpp` entries apart.
6. `file_name = f'{basename(mainfile)}.archive.json'` (`:118`),
   `eid = get_entry_id_from_file_name(file_name, archive)` (`:119`) ->
   `hash(archive.metadata.upload_id, file_name)` (`helper/utilities.py:281-284`), so the
   structured entry has its **own** `entry_id`, distinct from the raw-file entry.
7. `create_archive(entry, archive, file_name)` (`:121`, def `utilities.py:296-305`)
   writes `{'data': entry.m_to_dict(with_root_def=True)}` as a *new mainfile* and
   calls `process_updated_raw_file` (`:303`) -> nomad parses it on the next pass with
   `ArchiveParser` (`nomad/parsing/parser.py:554`). Only there do the section-level
   normalizers run: JV at `tfsc_general_package.py:721-741` (re-reads the `.iv`/`.jv`
   file and calls `get_jv_archive`) and MPPT at `:772+`.
7b. **The stem lookup is repeated, not shared**: the parser does it at `:112`, the JV
   normalizer re-derives `search_id = self.data_file.split('.')[0]` and calls
   `set_sample_reference` again at `:728-730`, and the MPPT normalizer a third time at
   `:785`. Any naming fix has to cover all three sites.
8. Sample side never sees the file name: `map_basic_sample`
   (`helper/solar_cell_batch_mapping.py:218-228`) sets `name` and `lab_id` from the
   Excel `Nomad ID` column; `TFSC_General_Sample.normalize`
   (`schema_packages/tfsc_general_package.py:286-296`) is the only code that strips
   suffixes, and only to build `batch_id` (`'_'.join(parts[:-2])`, `:292-293`) and
   `subbatch_id` (`'_'.join(parts[:-1])`, `:295-296`).

9. **Verify on the structured entry, not the raw one.** The raw `RawFileTFSCGeneral`
   entry only references `data.processed_archive` (`:118-121`); `samples` /
   `entry_references` appear on the `<file>.archive.json` twin. Checking the wrong
   entry yields a false negative (see abstractions "Verifying a link").

**Observed on a real upload** (`dkhJ7IaGSF6eyeEJ8vC0ig`, 2026-11-18): *both*
`PERS_INX_BO_3_C-10.iv.archive.json` and `PERS_INX_BO_3_C-10_cell3_2.mpp.archive.json`
ended with no `data.samples` and no `entry_references` — the `.iv` too, even though the
sample exists with `results.eln.lab_ids: ["PERS_INX_BO_3_C-10"]`. Re-running the exact
query from step 4 *now* returns exactly 1 hit, so the `.iv` miss was **ordering**, not
naming: the sample was not yet indexed when the measurement was parsed (file and sample
were uploaded together). The suffix fix is necessary but not sufficient — reprocess
after the sample exists.

**Why the naming still matters:** step 4 is an exact `lab_ids` match. Suffix-free file
-> stem == `lab_id` -> 1 hit -> linked (once the sample is searchable). Per-pixel file
-> stem carries `_cell3_2` -> 0 hits -> unlinked, silently, forever. A fix must keep the
exact stem as the first candidate (suffix-free files are the common case) and retry with
the suffix-stripped id; `set_sample_reference` is harmless to call twice because it only
writes on exactly one hit.

## Not traced yet

- GUI query -> app worker API handler -> Elasticsearch.
- `apps` (Voila) entry points: `nomad/app/v1/routers/apps.py:457-459` caches
  `AppEntryPoint`s, but the request -> notebook execution path is unread.
