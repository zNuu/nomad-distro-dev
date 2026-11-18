# Quiz log

> Append-only. Newest entry at the bottom. Never rewrite an earlier entry; if it
> was wrong, add a new one that supersedes it.

Entry format:

```markdown
## <YYYY-MM-DD> — <topic>
Q: <question>
A: <user's answer, summarized>
Verdict: correct | partly | wrong
Evidence: <path:line>, <path:line>
Follow-up: <one line>
```

## 2026-11-10 — metainfo: deleting `m_def`

Q: Delete `m_def` from `TFSC_General_JVmeasurement` — does the class break, and does
`self.m_def` become `None`?
A: Class still works; the ELN annotations would no longer appear alongside it in the GUI.
Verdict: partly
Evidence: `packages/nomad-FAIR/nomad/metainfo/metainfo.py:909-916`,
`packages/nomad-FAIR/nomad/metainfo/metainfo.py:920-930`,
`packages/nomad-FAIR/nomad/datamodel/data.py:96-100`
Follow-up: nothing is `None` — a bare `Section()` is synthesized on import and named after
the class; entry-ness comes from `EntryData` in the bases, not from `m_def`.

## 2026-11-10 — why nomad-hysprint is not active

Q: Why is `nomad-hysprint` "dropped" in this distro?
A: It is not configured in `pyproject.toml`.
Verdict: partly
Evidence: `pyproject.toml:11`, `pyproject.toml:24`, `uv.lock` (`[manifest] members`
still lists `nomad-hysprint`), `nomad.yaml:32-36`
Follow-up: the `packages/*` glob keeps it a workspace member (editable `.pth` present in
`.venv`), so the commented entry points in `nomad.yaml` are what actually switch it off.

## 2026-11-10 — `nomad-FAIR` submodule pin and version

Q: Running `git submodule update --init --recursive` — what happens to the `+` marker and
to the running `nomad-lab` version?
A: The `nomad-lab` version would change.
Verdict: partly
Evidence: `packages/nomad-FAIR/nomad/config/models/config.py:65`,
`.venv/.../__editable__.nomad_lab-2.0.1.dev3+g7b85ee7bb.pth`
Follow-up: checkout changes the *code* immediately (editable install), but the reported
version comes from dist metadata, so it only moves after `uv sync`.

## 2026-11-10 — ELN search facet vs. upload path

Q: Does an entry created only by a parser (no ELN form) still appear under the "Electronic
Lab Notebook" menu?
A: Yes — what shows up is dictated by the data schema, not by the upload.
Verdict: correct
Evidence: `packages/nomad-FAIR/nomad/datamodel/metainfo/basesections/v1.py:1988-1990`,
`packages/nomad-FAIR/nomad/datamodel/metainfo/eln/__init__.py:241-243`
Follow-up: it appends `self.m_def.name`, which ties back to the auto-generated `Section()`
name fallback at `metainfo.py:914-916`.

## 2026-12-11 — src layout: does `import` work without installing?

Q: Would `python -c "import nomad_tfsc_general"` succeed from
`packages/nomad-tfsc-general/` without installing, and which config line explains it?
A: Yes, it would succeed, because `[tool.setuptools.packages.find] where = ["src"]`
makes the package importable.
Verdict: wrong
Evidence: packages/nomad-tfsc-general/pyproject.toml:119-120 (packages.find is
build-time package discovery, not a sys.path entry), packages/nomad-tfsc-general/pyproject.toml:116-117 (package-dir="src"), src/nomad_tfsc_general.egg-info/top_level.txt:1 (import name only resolvable once the editable install is present)
Follow-up: `where`/`package-dir` control wheel building only; at runtime `src/` is not on
sys.path, so the import fails until installed. The `src/` layout exists precisely to
prevent an accidental cwd import that a flat layout would allow.

## 2026-11-18 — monkeypatching plugin code

Q: Why does patching the module-level import work, but patching baseclasses.helper.utilities.search would not?
A: Because tests run from the submodule and baseclasses is not on the path.
Verdict: wrong
Evidence: baseclasses/helper/utilities.py:330, :313, tfsc_general_measurement_parser.py:23-27
Follow-up: distinguish "not importable" from "name imported inside the function body".

## 2026-11-18 — where a sample link is visible

Q: On the entry page for `PERS_INX_BO_3_C-10_cell3_2.mpp`, which field tells you the
measurement got linked to its sample — and which field did the link actually fail on?
A: "I've no idea" — copied the JSON into an editor, ctrl-F'd `C-10`, and could not tell
whether it had worked.
Verdict: wrong
Evidence: `packages/nomad-tfsc-general/src/nomad_tfsc_general/parsers/tfsc_general_measurement_parser.py:76`
and `:118-121` (the raw `RawFileTFSCGeneral` entry only references
`data.processed_archive`), `packages/nomad-FAIR/nomad/datamodel/metainfo/basesections/v1.py:1298`
(`samples` on the structured entry), ES query in `learning/abstractions.md`
("Verifying a link").
Follow-up: the GUI page opened was the raw entry; the link field is `samples` on the
`*.archive.json` twin, and ctrl-F on the raw JSON can only ever hit the file name.


