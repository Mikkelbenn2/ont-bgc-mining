# Changelog

## v2.0.0 — 2026-10-06
Complete rewrite of the v1 script (kept in `legacy/`).
- Added: read filtering (Filtlong), polishing (Medaka or Dorado, bacterial models),
  assembly QC (QUAST, CheckM2), annotation (Bakta), ML BGC detection (GECCO),
  taxonomy (GTDB-Tk), BGC families with MIBiG (BiG-SCAPE 2), ranked summary tables.
- Changed: Flye read mode is configurable and defaults to `--nano-hq` (v1 used
  `--nano-raw`, which is meant for older/noisier reads).
- Changed: antiSMASH now runs MIBiG comparisons (KnownClusterBlast, ClusterCompare)
  and reads Bakta's annotation.
- Fixed: RGI could not find the CARD database (`--local` looks in ./localDB).
- New: config file + sample sheet, resumable steps, --dry-run, Slurm job array,
  software version log, self-test (test/run_tests.sh).

## v1.0 — 2026-09-11
NanoPlot → Flye → antiSMASH → RGI, one sample after another.
