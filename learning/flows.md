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

## Not traced yet

- GUI query -> app worker API handler -> Elasticsearch.
