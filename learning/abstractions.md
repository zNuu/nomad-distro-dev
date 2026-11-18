# Key abstractions

> A map, not ground truth. Verify against the cited source before repeating.

## Plugin / entry-point model (verified)

| Concept | Where | Meaning |
|---|---|---|
| Plugin declaration | `[project.entry-points.'nomad.plugin']` in a plugin's `pyproject.toml` | name -> `module:attribute`; the group is what nomad enumerates (`nomad/config/models/config.py:2696`) |
| Registry key | `key = entry_point.value` (`config.py:2700`) | nomad identifies a plugin by `module:attribute` (e.g. `nomad_hysprint.parsers:hysprint_parser`), **not** by the `pyproject.toml` key |
| Base config model | `EntryPoint` (`nomad/config/models/plugins.py:59`) | `id` (set from the entry point name, `:62-66`), `id_url_safe` (validated at `:75-89`), `entry_point_type`, `name`, `description`, `plugin_package` |
| Parser entry point | `ParserEntryPoint` (`nomad/config/models/plugins.py:185`) | `entry_point_type: 'parser'` (`:188-192`); `.load()` must return a `Parser`. `execution_order` (`:193-200`) controls execution order within an upload, **not** matching order |
| Normalizer entry point | `NormalizerEntryPoint.load()` (`nomad/config/models/plugins.py:178-182`) | returns a `NormalizerBaseClass` |
| App entry point | `AppEntryPoint` (`nomad/config/models/plugins.py:114`) | `entry_point_type: 'app'` (`:117-120`) |
| Include/exclude | `Options.filtered_keys` (`nomad/config/models/common.py:153-167`) | `include is None` or `'*' in include` -> all keys of `options`; then subtract `exclude`. `exclude: ['*']` -> nothing (`:162-163`) |

Invariant: entry-point subclasses keep imports **inside** `load()` (see the
docstring at `plugins.py:179-181`) precisely so that a broken optional dependency
does not kill module import. A plugin that imports at module scope breaks every
worker at startup.

## Plugin packages in this workspace

| Package | Declares entry points | Notes |
|---|---|---|
| `nomad-hysprint` | yes (`pyproject.toml:130-141`) | parsers, 4 schema packages, 3 apps |
| `nomad-tfsc-general` | yes (`pyproject.toml:122-124`) | **installed and enabled** since 2026-11 (`pyproject.toml:14`, `:23`; `nomad.yaml:37-42`). `nomad-hysprint` is the one now commented out (`pyproject.toml:11`, `:24`; `nomad.yaml:32-36`) |
| `nomad-baseclasses` | **none** — table at `pyproject.toml:137` is empty | acts as a library the other plugins import, not as a nomad plugin. Unknown whether intentional. |

`nomad-hysprint` depends on packages this repo never pins: `nomad-baseclasses`
(git), `nomad-luqy-plugin` (git), `nomad-measurements`, `pynxtools-xps` (git),
`httpx==0.27.2` (`packages/nomad-hysprint/pyproject.toml:31-37`). Their entry
points are also enumerated and imported by `load_plugins()`, so they are part of
our startup risk surface even though we never name them.

## Built-in parsers that always exist

`TabularDataParser` (`nomad/parsing/tabular.py:975`) and `ArchiveParser`
(`nomad/parsing/parser.py:554`) are core `MatchingParser`s. Everything else —
including any `.xlsx`/spreadsheet handling beyond core tabular — must come from a
plugin that is installed *and* included.

## Archive / files layer (verified)

- `UploadFiles` (`nomad/files/uploads.py:182-183`) is the abstract base for upload
  file access; `UploadFiles.get(upload_id)` is what plugins use. Our call sites:
  `packages/nomad-hysprint/.../hysprint_measurement_parser.py:85`,
  `packages/nomad-baseclasses/src/baseclasses/helper/utilities.py:454`,
  `packages/nomad-tfsc-general/.../tfsc_general_measurement_parser.py:76`.
  The same call shape works in 2.0.0 — this API did not break.
- Archive format is decided by magic bytes, not extension: v3 = msglc
  `LazyWriter.magic`, v2 = `b'nomad-archive-v2023'`
  (`nomad/archive/utils.py:29`, `:46-50`).
- Invariant: go through `read_archive`/`write_archive` instead of opening `.msg`
  directly, because the reader class depends on the detected version
  (`nomad/archive/utils.py:124-139`) — v1 -> `ArchiveReader`, v2 -> storage_v2
  reader, v3 -> `LazyReader`.

## Dependency direction (invariant)

`nomad-lab` never imports our plugins; plugins import `nomad` and subclass its
abstractions. The repo root holds no app code — only composition (`pyproject.toml`,
`nomad.yaml`, `docker-compose.yaml`). A plugin becomes active only if it is
installed **and** its entry point survives the `include` filter.

## Measurement <-> sample linking (verified 2026-11-18)

| Rule | Where | Consequence |
|---|---|---|
| A section attribute is only stored if it is a declared `Quantity` | `MSection.__setattr__` (`nomad-FAIR/nomad/metainfo/metainfo.py:1021-1039`) only resolves aliases / variadic names, else `super().__setattr__`; `m_to_dict` (`:1702`) serializes from the section definition | `self.pixel_id = ...` on a section without a `pixel_id` `Quantity` is a **silent no-op** — no error, not in the archive, not in search |
| `lab_id` is mirrored into search | core `BaseSection.normalize` copies `self.lab_id` -> `results.eln.lab_ids` (`nomad-FAIR/nomad/datamodel/metainfo/basesections/v1.py:268-272`; class at `:205`) | every sample lookup searches `results.eln.lab_ids`, never `samples.name` |
| sample lookup must hit **exactly one** entry | `set_sample_reference` (`utilities.py:339-344`) -> `search_sampleid_in_upload` (`:329-336`) queries `{'results.eln.lab_ids': id, 'upload_id': upload_id}`; `len(data) != 1` -> plain `return` | 0 hits **and** 2+ hits both leave `entry.samples` unset with **no log line** |
| the link lives in the archive + ES, not Mongo | `entry.samples` -> `data.samples` in the `.archive.json`, mirrored to ES `entry_references` (`app/v1/routers/entries.py:1926`, `:2014`) | the mongo `entry` doc has no `results`, no `entry_references`, no `data` (`processing/data.py:975-994`, metadata-only copy at `:1195-1214`) — mongosh cannot prove a link |
| measurement naming is filename-derived, sample naming is Excel-derived | measurement `entry.name` from the stem (`tfsc_general_measurement_parser.py:114`), mirrored to `results.eln.names` by core `BaseSection.normalize` (`basesections/v1.py:277-280`); sample `name`/`lab_id` from the Excel `Nomad ID` column (`helper/solar_cell_batch_mapping.py:218-228`) | the two agree only if the measurement file is named exactly `<lab_id>.<ext>` |

Storage split for one entry — same `entry_id`, three places:

| Place | Content | Cite |
|---|---|---|
| Mongo `entry` (db default `nomad_v1`, `config/models/config.py:1764`) | `upload_id`, `entry_id`, `mainfile`, `mainfile_key`, `parser_name`, `process_status`, timestamps | `processing/data.py:943-1013` |
| ES index `nomad_entries_v1` (`config/defaults.yaml:68`, `config/models/config.py:1382-1384`, `services/elasticsearch_extension.py:719-721`) | whole archive flattened: `results.eln.lab_ids`, `entry_name`, `entry_references`, `results.properties.*` | `search/search.py:111-216` |
| `uploads/<upload_id>/archive/<entry_id>.archive.json` | the real archive; read with `files.UploadFiles.get(upload_id).read_archive(entry_id=...)` | used at `tfsc_general_measurement_parser.py:76` |

## Verifying a link: raw entry vs. structured entry (verified 2026-11-18)

Reading the wrong entry is the fastest way to a false "it didn't link".

- One measurement file produces **two** entries with **different** `entry_id`s: the
  raw-file entry (`RawFileTFSCGeneral`) and, one pass later, its structured
  `<file>.archive.json` twin (Flow 6 step 6).
- The **raw** entry can never show the link. It has one reference only,
  `data.processed_archive` -> the structured entry (`tfsc_general_measurement_parser.py:76`,
  `:118-121`), and no `samples` quantity at all. Ctrl-F'ing a sample id in its JSON
  matches the file *name* and proves nothing.
- The link lives on the **structured** entry as `data.samples`
  (`nomad-FAIR/nomad/datamodel/metainfo/basesections/v1.py:1298`) and reaches search
  as `entry_references[]` whose `source_quantity` ends in `.samples`. GUI route: open
  the raw entry, click `processed_archive`, look for `samples`.
- Settle "did it link?" with the exact query the code runs
  (`baseclasses/helper/utilities.py:329-338`: `{'results.eln.lab_ids': sample_id,
  'upload_id': upload_id}`, `owner='all'`) instead of reading archives:

  ```bash
  curl -s localhost:9200/nomad_entries_v1/_search -H 'Content-Type: application/json' -d '{
    "query": {"bool": {"must": [
      {"term": {"results.eln.lab_ids": "PERS_INX_BO_3_C-10"}},
      {"term": {"upload_id": "dkhJ7IaGSF6eyeEJ8vC0ig"}}]}},
    "_source": ["mainfile", "entry_type"], "size": 5}'
  ```

  To sweep a whole upload, swap the bool query for `{"term": {"upload_id":
  "<id>"}}` and request `_source: ["mainfile", "entry_type", "results.eln.lab_ids"]`.
- Live storage names in this checkout (2026-11-18): mongo db **`nomad_v1`**
  (`docker exec nomad_mongo mongosh --quiet --eval 'db.adminCommand({listDatabases:1})'`
  -> `admin,config,local,nomad_v1`); ES indices **`nomad_entries_v1`** (1964 docs),
  `nomad_materials_v1`, `.geoip_databases` (`curl localhost:9200/_cat/indices?v`).

## Pixel identity (verified 2026-11-18)

- JV side has it: `JVCurve.pixel_id` (`baseclasses/solar_energy/jvmeasurement.py:392`,
  format `pixel_<n>`) derived from `cell_name` by `parse_jv_curve_name` (`:87-126`,
  called at `:438`). Producers emit `Pixel_<1-based>_<reverse|forward>`
  (`file_parser/jv_parser.py:110`, `:120`) and `jv_archive.py:49`, `:56`
  (`pixel_num = int(curve['name'].split('_')[1]) - 1` -> 0-based array index).
- MPPT side: baseclasses carries **two** MPPT models. `MPPTracking`
  (`baseclasses/solar_energy/mpp_tracking.py:442`) — what TFSC uses — has no pixel
  field at all, and `TFSC_General_SimpleMPPTracking(MPPTracking, EntryData)`
  (`nomad_tfsc_general/schema_packages/tfsc_general_package.py:744`) adds only
  `data_file`, `datetime`, `series_resistance`. The hySprint one does:
  `MPPTrackingHsprintCustom(BaseMeasurement)`
  (`baseclasses/solar_energy/mpp_tracking_hysprint_custom.py:236`) nests
  `samples[].pixels[]` (`:265`, `:233`) where `PixelData` has `name` (inherited `:47`),
  `include_for_average` (`:72`) and `best_pixel: bool` (`:76`), and its normalize
  collects `best_pixels` (`:269`, filled at `:276-305`).
- So "best pixel" is a **per-pixel bool inside an MPPT entry**, not a sample-level
  result. The sample-level "best" is instead max-efficiency JV
  (`solar_energy/solarcellsample.py:480-496`: loop over `result_data['JVs']`, keep the
  highest non-NaN efficiency, write `results...solar_cell.efficiency`) — not a pixel id.
- The MPPT protocol says the run happens on the *best* pixel
  (`nomad_tfsc_general/schema_packages/file_parser/mppt_parser.py:16-20`), but the
  TFSC entry records nothing about which pixel that was.

## Still to explore (not opened in this session)

- Metainfo section / quantity classes used by the HZB plugins and their physical
  meaning (`baseclasses/solar_energy`, `catalysis`, `chemical_energy` exist under
  `packages/nomad-baseclasses/src/baseclasses/` but were not read).
- How those sections are subclassed by `nomad-hysprint` / `nomad-tfsc-general`.
- Experiment-entry / measurement classes and `mainfile` conventions.
- Quantity units and required-metadata invariants.
