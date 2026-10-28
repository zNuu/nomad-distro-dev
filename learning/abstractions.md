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
| `nomad-tfsc-general` | yes (`pyproject.toml:122-124`) | 2 parser entry points; **not installed** here (`pyproject.toml:14`, `:23`) |
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

## Still to explore (not opened in this session)

- Metainfo section / quantity classes used by the HZB plugins and their physical
  meaning (`baseclasses/solar_energy`, `catalysis`, `chemical_energy` exist under
  `packages/nomad-baseclasses/src/baseclasses/` but were not read).
- How those sections are subclassed by `nomad-hysprint` / `nomad-tfsc-general`.
- Experiment-entry / measurement classes and `mainfile` conventions.
- Quantity units and required-metadata invariants.
