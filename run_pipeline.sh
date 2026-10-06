#!/usr/bin/env bash
# =============================================================================
# run_pipeline.sh — ONT isolate genomes -> BGCs -> novelty ranking
#
# Per sample (isolate):
#   00_reads        join FASTQ files                       (bash)
#   01_read_qc      read length / quality plots            (NanoPlot)
#   02_read_filter  drop short + low-quality reads         (Filtlong, SeqKit)
#   03_assembly     de novo assembly                       (Flye)
#   04_polish       fix small errors                       (Medaka | Dorado polish)
#   05_assembly_qc  contiguity, completeness, contamination (QUAST, CheckM2)
#   06_annotation   find and name all genes                (Bakta)
#   07_antismash    rule-based BGC detection + MIBiG comparison (antiSMASH)
#   08_gecco        machine-learning BGC detection         (GECCO)
#   09_resistance   antibiotic resistance genes            (RGI / CARD)
# Once over all samples ("cohort"):
#   10_taxonomy     genome-based species assignment        (GTDB-Tk)
#   11_bigscape     gene cluster families incl. MIBiG      (BiG-SCAPE 2)
#   12_summary      genome table + ranked BGC table        (python)
#
# Usage:
#   bin/run_pipeline.sh -c CONFIG [options]
#
# Options:
#   -c FILE          config file (required), e.g. config/my_project.sh
#   --sample ID      run only this sample (used by the Slurm array jobs)
#   --samples-only   run the per-sample steps, not the cohort steps
#   --cohort-only    run only the cohort steps (10-12)
#   --steps LIST     run only these steps, comma-separated (e.g. 07_antismash,12_summary)
#   --force LIST     re-run these steps even if done ("all" = everything)
#   --dry-run        print every command without running anything
#   -h, --help       show this help
#
# Re-running is safe: finished steps are skipped (they leave a .done file).
# =============================================================================
set -uo pipefail
# -u        : using an unset variable is an error (catches typos)
# pipefail  : a pipe fails if ANY command in it fails
# (no -e on purpose: one failing sample must not stop the others; every step
#  reports its own success or failure instead)

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/common.sh"
for f in "$REPO_DIR"/steps/*.sh; do source "$f"; done

usage() { sed -n '3,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ---------- command-line options ----------------------------------------------
CONFIG=""; ONLY_SAMPLE=""; DO_SAMPLES=1; DO_COHORT=1; DRY_RUN=0
ONLY_STEPS=(); FORCE_STEPS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)    CONFIG="$2"; shift 2 ;;
    --sample)       ONLY_SAMPLE="$2"; shift 2 ;;
    --samples-only) DO_COHORT=0; shift ;;
    --cohort-only)  DO_SAMPLES=0; shift ;;
    --steps)        IFS=',' read -r -a ONLY_STEPS <<<"$2"; shift 2 ;;
    --force)        IFS=',' read -r -a FORCE_STEPS <<<"$2"; shift 2 ;;
    --dry-run)      DRY_RUN=1; shift ;;
    -h|--help)      usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done
[[ -n "$CONFIG" ]] || { echo "Error: -c CONFIG is required." >&2; usage 1; }

load_config "$CONFIG"
mkdir -p "$OUTDIR/logs"
MAIN_LOG="$OUTDIR/logs/pipeline_$(date +%Y%m%d_%H%M%S)${ONLY_SAMPLE:+_$ONLY_SAMPLE}.log"
detect_conda
read_samples

log "ONT BGC-mining pipeline — project '$PROJECT_NAME'"
log "Repo:    $REPO_DIR ($(git -C "$REPO_DIR" describe --always --dirty 2>/dev/null || echo 'not a git checkout'))"
log "Config:  $CONFIG"
log "Output:  $OUTDIR"
log "Threads: $THREADS    Samples in sheet: ${#SAMPLE_IDS[@]}    Dry run: $DRY_RUN"
# Keep a copy of the exact config next to the results (reproducibility).
[[ "$DRY_RUN" -eq 0 ]] && cp "$CONFIG" "$OUTDIR/logs/config_used.sh"

# Record the exact version of every tool (asked from conda, so it works the same
# for every tool). This table is what you cite in the Methods section.
write_versions() {
  local out="$OUTDIR/logs/software_versions.tsv" yml env pkg ver
  printf 'environment\tpackage\tversion\n' >"$out"
  for yml in "$REPO_DIR"/envs/*.yml; do
    env=$(basename "$yml" .yml)
    [[ -d "$(env_path "$env")" ]] || { printf '%s\t-\tNOT INSTALLED\n' "$env" >>"$out"; continue; }
    # package names = the dependency lines of the yml, without version pins
    for pkg in $(sed -n 's/^  - \([A-Za-z0-9_.-]*\).*/\1/p' "$yml"); do
      ver=$("$CONDA_RUNNER" list -p "$(env_path "$env")" 2>/dev/null \
            | awk -v p="$pkg" '$1==p {print $2; exit}')
      printf '%s\t%s\t%s\n' "$env" "$pkg" "${ver:-?}" >>"$out"
    done
  done
}
[[ "$DRY_RUN" -eq 0 ]] && write_versions

# ---------- one sample, all per-sample steps ------------------------------------
# Each line: run_step STEP_NAME OUTPUT_FOLDER FUNCTION LABEL
# "|| return 1" stops this sample at the first failure (later steps need the
# earlier outputs). Optional steps only stop themselves.
process_sample() {
  local i=$1
  set_sample_paths "${SAMPLE_IDS[$i]}"
  READS_IN=${SAMPLE_READS[$i]}
  GSIZE=${SAMPLE_GSIZE[$i]:-$GENOME_SIZE}
  log "=== Sample $SAMPLE ==="
  [[ "$DRY_RUN" -eq 0 ]] && mkdir -p "$SDIR"

  run_step 00_reads       "$SDIR/00_reads"       step_prepare_reads "$SAMPLE" || return 1
  run_step 01_read_qc     "$SDIR/01_read_qc"     step_read_qc       "$SAMPLE" || warn "read QC failed for $SAMPLE (continuing)"
  run_step 02_read_filter "$SDIR/02_read_filter" step_read_filter   "$SAMPLE" || return 1
  run_step 03_assembly    "$SDIR/03_assembly"    step_assembly      "$SAMPLE" || return 1
  run_step 04_polish      "$SDIR/04_polish"      step_polish        "$SAMPLE" || return 1
  run_step 05_assembly_qc "$SDIR/05_assembly_qc" step_assembly_qc   "$SAMPLE" || warn "assembly QC failed for $SAMPLE (continuing)"
  run_step 06_annotation  "$SDIR/06_annotation"  step_annotation    "$SAMPLE" || return 1
  run_step 07_antismash   "$SDIR/07_antismash"   step_antismash     "$SAMPLE" || return 1
  if [[ "$RUN_GECCO" -eq 1 ]]; then
    run_step 08_gecco      "$SDIR/08_gecco"       step_gecco        "$SAMPLE" || warn "GECCO failed for $SAMPLE (continuing)"
  fi
  if [[ "$RUN_RGI" -eq 1 ]]; then
    run_step 09_resistance "$SDIR/09_resistance"  step_resistance   "$SAMPLE" || warn "RGI failed for $SAMPLE (continuing)"
  fi
  log "=== Sample $SAMPLE done ==="
}

FAILED=()
if [[ "$DO_SAMPLES" -eq 1 ]]; then
  found=0
  for i in "${!SAMPLE_IDS[@]}"; do
    [[ -n "$ONLY_SAMPLE" && "${SAMPLE_IDS[$i]}" != "$ONLY_SAMPLE" ]] && continue
    found=1
    process_sample "$i" || FAILED+=("${SAMPLE_IDS[$i]}")
  done
  [[ "$found" -eq 1 ]] || die "Sample '$ONLY_SAMPLE' is not in $SAMPLES_TSV"
fi

# ---------- cohort steps --------------------------------------------------------
if [[ "$DO_COHORT" -eq 1 && -z "$ONLY_SAMPLE" ]]; then
  log "=== Cohort steps (all samples) ==="
  C="$OUTDIR/cohort"
  if [[ "$RUN_GTDBTK" -eq 1 ]]; then
    run_step 10_taxonomy "$C/10_taxonomy" step_taxonomy cohort || warn "GTDB-Tk failed (continuing)"
  fi
  if [[ "$RUN_BIGSCAPE" -eq 1 ]]; then
    run_step 11_bigscape "$C/11_bigscape" step_bigscape cohort || warn "BiG-SCAPE failed (continuing)"
  fi
  # The summary is cheap and should always reflect the latest results.
  FORCE_STEPS+=(12_summary)
  run_step 12_summary "$C/12_summary" step_summary cohort || FAILED+=("summary")
fi

# ---------- final report ----------------------------------------------------------
log "=== Pipeline finished ==="
if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "Failed: ${FAILED[*]} — check the step logs inside each sample folder."
  exit 1
fi
log "All done. Start with: $OUTDIR/cohort/12_summary/"
