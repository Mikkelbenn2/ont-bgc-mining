#!/usr/bin/env bash
#
# run_pipeline.sh — Nanopore genome mining pipeline
#
# Steps per sample:
#   1. NanoPlot   — QC of raw long reads
#   2. Flye       — de novo assembly
#   3. antiSMASH  — biosynthetic gene cluster detection (on assembly)
#   4. RGI/CARD   — antibiotic resistance gene detection (on assembly)
#
# Requires conda or mamba on PATH. Creates one isolated env per tool
# the first time it runs (skip with --skip-env-setup).
#
# Expected layout on this machine:
#   /home/student.aau.dk/ml12pe/Bioinformatics/
#     Data/       <- nanopore fastq(.gz) files go here, one per sample
#     Scripts/    <- this script lives here
#     project/    <- created automatically, all results go here
#
# By default the script needs no arguments: it reads from Data/ and
# writes to project/ next to it. Override with -i/-o if needed.
#
# Usage:
#   ./run_pipeline.sh [-i RAW_READS_DIR] [-o RESULTS_DIR] [options]
#
# Options:
#   -i DIR    Input directory of nanopore reads, one file per sample
#             (*.fastq / *.fq / *.fastq.gz / *.fq.gz)   [default: Bioinformatics/Data]
#   -o DIR    Output/results directory                  [default: Bioinformatics/project]
#   -t INT    Threads per tool                                  [default: 8]
#   -g SIZE   Estimated genome size for Flye, e.g. 5m (optional; Flye
#             can auto-estimate without it)
#   --taxon TAXON       antiSMASH taxon: bacteria|fungi          [default: bacteria]
#   --skip-env-setup    Assume conda envs already exist
#   --skip-db-setup     Assume antiSMASH + CARD databases already installed
#   -h                  Show this help
#
set -uo pipefail

# ---------- base paths ----------
# Resolve relative to this script's location, so it works whether Scripts/
# lives under the path below or the whole project folder gets moved/renamed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"          # .../Bioinformatics
DEFAULT_INPUT_DIR="$BASE_DIR/Data"
DEFAULT_OUTPUT_DIR="$BASE_DIR/project"

# ---------- defaults ----------
THREADS=8
GENOME_SIZE=""
TAXON="bacteria"
SKIP_ENV_SETUP=0
SKIP_DB_SETUP=0
INPUT_DIR="$DEFAULT_INPUT_DIR"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"

NANOPLOT_ENV="np_nanoplot"
FLYE_ENV="np_flye"
ANTISMASH_ENV="np_antismash"
RGI_ENV="np_rgi"

usage() { sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

# ---------- arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) INPUT_DIR="$2"; shift 2 ;;
    -o) OUTPUT_DIR="$2"; shift 2 ;;
    -t) THREADS="$2"; shift 2 ;;
    -g) GENOME_SIZE="$2"; shift 2 ;;
    --taxon) TAXON="$2"; shift 2 ;;
    --skip-env-setup) SKIP_ENV_SETUP=1; shift ;;
    --skip-db-setup) SKIP_DB_SETUP=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

[[ -d "$INPUT_DIR" ]] || { echo "Error: input dir '$INPUT_DIR' not found. Put your fastq files in Bioinformatics/Data, or pass -i."; exit 1; }

mkdir -p "$OUTPUT_DIR"/{logs,card_data}
LOG_DIR="$OUTPUT_DIR/logs"
MAIN_LOG="$LOG_DIR/pipeline.log"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MAIN_LOG"; }
die()  { log "FATAL: $*"; exit 1; }

log "Input dir:  $INPUT_DIR"
log "Output dir: $OUTPUT_DIR"

# ---------- pick conda/mamba ----------
if command -v mamba &>/dev/null; then
  CONDA_BIN=mamba
elif command -v conda &>/dev/null; then
  CONDA_BIN=conda
else
  die "Neither mamba nor conda found on PATH. Install one first."
fi

env_exists() { conda env list | awk '{print $1}' | grep -qx "$1"; }

create_env_if_missing() {
  local env_name=$1 pkg_spec=$2
  if env_exists "$env_name"; then
    log "Env '$env_name' already exists, skipping."
  else
    log "Creating env '$env_name' ($pkg_spec)..."
    "$CONDA_BIN" create -y -n "$env_name" -c bioconda -c conda-forge $pkg_spec \
      >>"$LOG_DIR/env_setup.log" 2>&1 || die "Failed to create env '$env_name' (see $LOG_DIR/env_setup.log)"
  fi
}

run_in_env() {
  local env_name=$1; shift
  conda run --no-capture-output -n "$env_name" "$@"
}

# ---------- 0. environment setup ----------
if [[ "$SKIP_ENV_SETUP" -eq 0 ]]; then
  log "=== Setting up conda environments ==="
  create_env_if_missing "$NANOPLOT_ENV"   "nanoplot"
  create_env_if_missing "$FLYE_ENV"       "flye"
  create_env_if_missing "$ANTISMASH_ENV"  "antismash"
  create_env_if_missing "$RGI_ENV"        "rgi"
else
  log "Skipping env setup (--skip-env-setup)."
fi

# ---------- 0b. database setup (one-time) ----------
CARD_DIR="$OUTPUT_DIR/card_data"
CARD_MARKER="$CARD_DIR/.card_loaded"

if [[ "$SKIP_DB_SETUP" -eq 0 ]]; then
  log "=== Setting up databases (one-time) ==="

  # antiSMASH reference databases
  log "Ensuring antiSMASH databases are installed..."
  run_in_env "$ANTISMASH_ENV" download-antismash-databases \
    >>"$LOG_DIR/antismash_db.log" 2>&1 || die "antiSMASH database download failed (see $LOG_DIR/antismash_db.log)"

  # CARD database for RGI
  if [[ -f "$CARD_MARKER" ]]; then
    log "CARD database already loaded, skipping."
  else
    log "Downloading and loading CARD database..."
    ( cd "$CARD_DIR" \
      && curl -sSL https://card.mcmaster.ca/latest/data -o card_data.tar.bz2 \
      && tar -xjf card_data.tar.bz2 \
    ) >>"$LOG_DIR/card_setup.log" 2>&1 || die "CARD download/extract failed (see $LOG_DIR/card_setup.log)"

    run_in_env "$RGI_ENV" rgi load --card_json "$CARD_DIR/card.json" \
      >>"$LOG_DIR/card_setup.log" 2>&1 || die "rgi load failed (see $LOG_DIR/card_setup.log)"

    touch "$CARD_MARKER"
    log "CARD database loaded."
  fi
else
  log "Skipping database setup (--skip-db-setup)."
fi

# ---------- gather samples ----------
mapfile -t READ_FILES < <(find "$INPUT_DIR" -maxdepth 1 -type f \
  \( -name '*.fastq' -o -name '*.fq' -o -name '*.fastq.gz' -o -name '*.fq.gz' \) | sort)

[[ ${#READ_FILES[@]} -eq 0 ]] && die "No .fastq/.fq(.gz) files found in '$INPUT_DIR'."

log "Found ${#READ_FILES[@]} sample(s) in '$INPUT_DIR'."

FAILED_SAMPLES=()

sample_name_from_file() {
  local f base
  base=$(basename "$1")
  base="${base%.gz}"
  base="${base%.fastq}"
  base="${base%.fq}"
  echo "$base"
}

run_sample() {
  local reads=$1 sample outdir slog
  sample=$(sample_name_from_file "$reads")
  outdir="$OUTPUT_DIR/$sample"
  slog="$LOG_DIR/${sample}.log"
  mkdir -p "$outdir"

  log "----- [$sample] Starting -----"

  # 1. NanoPlot QC
  log "[$sample] Step 1/4: NanoPlot QC"
  run_in_env "$NANOPLOT_ENV" NanoPlot \
    --fastq "$reads" \
    --outdir "$outdir/01_nanoplot" \
    --threads "$THREADS" \
    >>"$slog" 2>&1 || { log "[$sample] NanoPlot FAILED"; return 1; }

  # 2. Flye assembly
  log "[$sample] Step 2/4: Flye assembly"
  local flye_args=(--nano-raw "$reads" --out-dir "$outdir/02_flye" --threads "$THREADS")
  [[ -n "$GENOME_SIZE" ]] && flye_args+=(--genome-size "$GENOME_SIZE")
  run_in_env "$FLYE_ENV" flye "${flye_args[@]}" \
    >>"$slog" 2>&1 || { log "[$sample] Flye FAILED"; return 1; }

  local assembly="$outdir/02_flye/assembly.fasta"
  [[ -s "$assembly" ]] || { log "[$sample] No assembly.fasta produced, aborting sample"; return 1; }

  # 3. antiSMASH on the assembly
  log "[$sample] Step 3/4: antiSMASH"
  run_in_env "$ANTISMASH_ENV" antismash \
    --cpus "$THREADS" \
    --taxon "$TAXON" \
    --genefinding-tool prodigal \
    --output-dir "$outdir/03_antismash" \
    "$assembly" \
    >>"$slog" 2>&1 || { log "[$sample] antiSMASH FAILED"; return 1; }

  # 4. RGI / CARD on the assembly
  log "[$sample] Step 4/4: RGI (CARD)"
  mkdir -p "$outdir/04_rgi"
  ( cd "$outdir/04_rgi" && run_in_env "$RGI_ENV" rgi main \
      --input_sequence "$assembly" \
      --output_file rgi_output \
      --input_type contig \
      --num_threads "$THREADS" \
      --clean \
      --local ) \
    >>"$slog" 2>&1 || { log "[$sample] RGI FAILED"; return 1; }

  log "----- [$sample] Done -----"
}

# ---------- main loop ----------
for reads in "${READ_FILES[@]}"; do
  if ! run_sample "$reads"; then
    FAILED_SAMPLES+=("$(sample_name_from_file "$reads")")
  fi
done

log "=== Pipeline finished ==="
if [[ ${#FAILED_SAMPLES[@]} -gt 0 ]]; then
  log "Failed samples: ${FAILED_SAMPLES[*]} (see per-sample logs in $LOG_DIR)"
  exit 1
else
  log "All samples completed successfully. Results in: $OUTPUT_DIR"
fi
