# Open questions

> Unresolved mysteries and places where these notes disagreed with the code.

Format: `- <date> — <question> (context: <path:line>)`. Add a correction line
here when a note turned out to be wrong, then fix the note.

- 2026-10-28 — Which plugin entry points are actually enabled in this
  deployment, and what happens to uploads that match no parser?
  (context: `nomad.yaml:25`)
- 2026-10-28 — **Correction.** Earlier notes claimed plugin-level `nomad.yaml`
  files are merged into deployment config. They are **not**: config files come only
  from `NOMAD_CONFIG` or CWD `nomad.yaml`
  (`packages/nomad-FAIR/nomad/config/__init__.py:52`, `:69`), and `NOMAD_CONFIG`
  *replaces* the default instead of extending it
  (`packages/nomad-FAIR/nomad/config/__init__.py:61-64`). So
  `packages/nomad-baseclasses/nomad.yaml` is dead config today. Fixed in
  `overview.md`.
- 2026-10-28 — `packages/nomad-baseclasses/nomad.yaml:6-11` references entry point
  `schemas/baseclasses` with option `python_package: baseclasses`, but (a) that file
  is not loaded (above), (b) `nomad-baseclasses` declares **no** entry points
  (`packages/nomad-baseclasses/pyproject.toml:137`), and (c) no `python_package`
  field exists on any 2.0.0 entry-point model (only hits are that yaml, a built GUI
  asset, and `.cline/skills/update-distro/SKILL.md:150`). Is baseclasses meant to be
  a library only, and should that yaml be deleted?
- 2026-10-28 — `pyproject.toml:25-28` lists four git packages under
  `[tool.uv.sources]` (`nomad-aitoolkit`, `nomad-porous-materials`,
  `perovskite-solar-cell-database`, `nomad-external-eln-integrations`) that appear
  in no dependency list. `[tool.uv.sources]` only says *where* to fetch something
  already required, so these are dangling. Deliberate park-or-drop?
- 2026-10-28 — Which plugin entry points are actually enabled? **Partly answered:**
  the allowlist is `nomad.yaml:31-36` (hysprint parsers/schema packages/2 apps) and
  the filter is `nomad/config/models/common.py:153-167`. Since `nomad-hysprint`
  declares 10 entry points (`packages/nomad-hysprint/pyproject.toml:130-141`),
  `solai_package`, `solartab_package`, `solartab_sim_parser`,
  `ink_recycling_package`, and `solar_cell_overview_entry_point` are currently off.
  Still open: confirm at runtime with
  `uv run --no-sync python -c "from nomad.config import config; config.load_plugins(); print(sorted(config.plugins.entry_points.options))"`.
- 2026-10-28 — What happens to an upload whose mainfile matches no parser?
  `match_parser` returns `(None, None)` (docstring
  `packages/nomad-FAIR/nomad/parsing/parsers.py:74-75`), but what the pipeline does
  next (missing-parser entry vs. failure) is untraced. Relevant because
  `nomad-tfsc-general` is not installed, so its `.xlsx` mainfiles fall here.
  (context: `nomad.yaml:25`)
- 2026-10-28 — Why is `nomad-tfsc-general` commented out of the workspace deps?
  (context: `pyproject.toml:14`, `pyproject.toml:23`) Still open. Note it is *also*
  commented out of the entry-point include list (`nomad.yaml:37-44`), so re-enabling
  it needs both edits — and `SKILL.md` shows it being tested via a separate
  `NOMAD_CONFIG` file, which would *replace* `nomad.yaml`.
- 2026-10-28 — `defaults.yaml:464-467` ships a default
  `plugins.entry_points.exclude` (`nomad_porous_materials.normalizers:porositynormalizer`).
  Our `nomad.yaml` sets `include` but no `exclude` — does that default exclusion
  still apply, or does our `include` override the whole filter object?
- 2026-10-28 — Temporal server `temporalio/temporal:1.6.1`
  (`docker-compose.yaml:57`) vs the `temporalio` Python SDK version pinned by
  nomad-lab 2.0.0: unverified offline. If upload processing stalls rather than
  errors, check here first.
- 2026-11-11 — **Correction.** The rows above assume `nomad-tfsc-general` is
  commented out and `nomad-hysprint` enabled. Current state is the reverse:
  `nomad-tfsc-general` **is** a dependency and workspace source
  (`pyproject.toml:14`, `:23`) and its six entry points are enabled
  (`nomad.yaml:37-42`), while `nomad-hysprint` is commented out
  (`pyproject.toml:11`, `:24`; `nomad.yaml:32-36`). The *reason* for the swap is
  still open.
- 2026-11-11 — debugpy (Kylin `kylin-python-0.4.3`, bundled debugpy 1.8.1) raises
  `FileNotFoundError: '/home/a4864/.local/lib/python3.12'` once a client attaches.
  That path is the `posix_user` stdlib dir, parent of `site.getusersitepackages()`.
  `FilesFiltering._get_default_library_roots()` adds the *`site-packages`* path, not
  the parent, and does it without an existence check
  (`pydevd_filtering.py:142-197`), so it is not the exact source; a bare
  `python -m debugpy --listen ... --wait-for-client` run does not reproduce it.
  Next step: run the `API debug (uvicorn)` config and read
  `/tmp/debugpy-logs/debuggee-*.log` (`DEBUGPY_LOG_DIR`). (context:
  `.vscode/launch.json:84-98`)
- 2026-11-11 — Is it intentional that the installed `nomad-gui` wheel is *not*
  mounted? `GUIAPIEntryPoint(prefix='gui/v2')` (`nomad_gui/apis/__init__.py:498-502`)
  is only mounted if it survives `entry_points.filtered_values()`
  (`nomad/app/main.py:246-259`), and the include list (`nomad.yaml:30-42`) has no
  `nomad_gui.apis:gui_api`. Yet `README.md:298-300` advertises
  `http://localhost:8000/nomad-oasis/gui/v2/`, and `run/gui.prepare.stamp` reads
  `/nomad-oasis/gui/v2` — so the plugin *has* been loaded in this checkout at some
  point. Was the include list narrowed after that?
- 2026-11-11 — `nomad admin run app --with-gui` copies
  `nomad/app/static/gui` -> `run/gui_configured` (`nomad/cli/admin/run.py:201-242`),
  but `app/static/gui` is empty here. Can `--with-gui` ever serve anything in this
  checkout, or is it a dead path left over from before the v2 GUI became a plugin?
- 2026-11-18 — **Correction.** An earlier answer claimed the sample-level "best pixel"
  is picked by argmax over pixels. It is not: `solarcellsample.py:480-496` keeps the
  highest non-NaN efficiency across `result_data['JVs']` and writes
  `results.properties.optoelectronic.solar_cell.efficiency`. "Best pixel" is not a
  sample-level result at all: it is a bool on a pixel section
  (`solar_energy/mpp_tracking_hysprint_custom.py:76`) that only the hySprint MPPT
  section uses (`:236`, `:265`, `:269`, `:276-305`).
- 2026-11-18 — Per-pixel MPPT files (`<lab_id>_cell<n>[_<k>].mpp`) cannot link to their
  sample because `set_sample_reference` gets the whole stem
  (`tfsc_general_measurement_parser.py:111-112`). Agreed fix shape: try stem first, then
  the suffix-stripped id (see Flow 6). Must be applied at **all three** lookup sites
  (Flow 6 step 7b: parser `:112`, JV normalizer `tfsc_general_package.py:728-730`, MPPT
  normalizer `:785`). Open: should the suffix pattern live in one
  helper shared with `TFSC_General_Sample.normalize` batch/subbatch splitting
  (`tfsc_general_package.py:292-296`), which uses a different rule (`parts[:-2]`)?
- 2026-11-18 — Is `cell3` in an MPPT file name the same physical pixel as `Pixel_3`
  from JV curves (`jv_parser.py:110`, `:120`; 0-based index math at `jv_archive.py:56`)?
  Assumed yes so far; needs confirmation with the lab before `pixel_id` values are used
  to join JV and MPPT entries. Also open: `_<k>` in `_cell3_2` = repeat run, second
  channel, or something else?
- 2026-11-18 — `set_sample_reference` returns silently on 0 hits *and* on >1 hits
  (`utilities.py:339-344`) with no logger argument. Should it warn (which would need a
  `logger` parameter threaded from the parsers), or should callers log a missed link?
  Silent failure is what hid this bug across two uploads.
- 2026-11-18 — MPPT pixel identity is unrepresentable today: `MPPTracking`
  (`mpp_tracking.py:442`) has no pixel field, so a `self.pixel_id = ...` assignment is a
  no-op (see abstractions "Measurement <-> sample linking"). Open: add `pixel_id` +
  `measurement_no` quantities to `TFSC_General_SimpleMPPTracking`
  (`tfsc_general_package.py:744`) or upstream to `MPPTracking`, and normalize the value
  to `pixel_<n>` to match `JVCurve.pixel_id` (`jvmeasurement.py:392`)? Third option
  surfaced while writing Flow 6: adopt the hySprint shape — one entry with
  `samples[].pixels[]`, each `PixelData` carrying its own `series_resistance` and a
  `best_pixel` bool (`mpp_tracking_hysprint_custom.py:71-78`, `:236-305`) — which fits
  the "all pixels of one sample in one upload" reality better than N sibling entries.
- 2026-11-18 — **Unverifiable claim, dropped.** A note carried over from an earlier
  session claimed "`load_mpp_hysprint.py:254-259` filters MPPT rows by
  `Time_ms == start_time`" and "`:132` hardcodes `series_resistance = 1.2 * ohm`".
  Neither reproduces: the only such file is
  `packages/nomad-hysprint/src/nomad_hysprint/schema_packages/file_parser/load_mpp_hysprint.py`
  (not in `nomad-tfsc-general`), `:132` is a column-name string, and the file ends well
  before line 254. Treated as hallucinated until someone points at the real code;
  the hardcoded-series-R concern may still be real somewhere in
  `nomad-tfsc-general/.../file_parser/mppt_parser.py` — unread here.
- 2026-11-18 — Verification recipe settled: mongosh proves only that entries exist
  (mongo `entry` is metadata-only, `processing/data.py:975-994`); the sample link must be
  read from ES `nomad_entries_v1` (`entry_references`) or from the archive via
  `files.UploadFiles.get(upload_id).read_archive(entry_id=...)`. Open: confirm the live
  mongo db name and ES index name in this checkout with `show dbs` /
  `curl localhost:9200/_cat/indices` and record them here.

- 2026-11-18 — **Answered.** Live storage names in this checkout: mongo db
  `nomad_v1` only (`docker exec nomad_mongo mongosh --quiet --eval
  'db.adminCommand({listDatabases:1})'` -> `admin,config,local,nomad_v1`); ES indices
  `nomad_entries_v1` (1964 docs), `nomad_materials_v1`, `.geoip_databases`
  (`curl localhost:9200/_cat/indices?v`). Recipe recorded in `abstractions.md`
  ("Verifying a link"). Note the two `.mpp` entries in the GUI are easy to confuse:
  the raw one points at `data.processed_archive`, the structured one carries `samples`.
- 2026-11-18 — Same-upload ordering defeats the link even when the name is perfect.
  In upload `dkhJ7IaGSF6eyeEJ8vC0ig`, `PERS_INX_BO_3_C-10.iv.archive.json` has **no**
  `data.samples` and no `entry_references`, although its stem equals the sample's
  `results.eln.lab_ids` (`["PERS_INX_BO_3_C-10"]`, verified in ES) and re-running the
  exact query at `utilities.py:329-338` today returns exactly 1 hit. So the lookup ran
  before the sample entry was indexed. Open: does the pipeline guarantee
  sample-before-measurement order when both come from one upload, or is reprocessing
  the only remedy? This matters because the `_cell<n>_<k>` fix alone will still leave
  same-upload measurements unlinked.
- 2026-11-18 — **New bug (dispatch case-sensitivity).** `TFSCGeneralParser.parse`
  routes case-insensitively via `filename_lower`
  (`tfsc_general_measurement_parser.py:94-107`), but
  `read_mppt_file` then re-decides with `if 'MPP' in filename.split('.')[-1]`
  (`file_parser/mppt_parser.py:100`) on the original-case name. A lowercase `.mpp`
  misses the 'MPP' branch, falls through the `'Time (s)'` sniff and can raise
  `TypeError('mppt file not recognized')`. Fix: compare `filename.lower()` (or reuse
  the already-lowercased name).

