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
