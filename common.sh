# shellcheck shell=bash
# =============================================================================
# lib/common.sh — shared helper functions used by every script in the pipeline
#
# This file is not run on its own. Other scripts load it with
#     source "$REPO_DIR/lib/common.sh"
# which makes the functions below available to them. Keeping helpers in one
# place means a fix here fixes every step at once.
# =============================================================================

# ---------- Logging -----------------------------------------------------------
# log "message"  -> prints "[2026-10-06 13:20:01] message" to screen AND main log
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${MAIN_LOG:-/dev/null}" >&2; }
warn() { log "WARNING: $*"; }
die()  { log "FATAL: $*"; exit 1; }

# ---------- Loading the config ------------------------------------------------
# load_config FILE : source the user's config, then make every path absolute.
# Relative paths in the config are taken relative to the repository folder, so
# the pipeline behaves the same no matter which folder you start it from.
abspath() {
  local p=$1
  [[ -z "$p" ]] && { echo ""; return; }
  [[ "$p" = /* ]] && { echo "$p"; return; }
  echo "${REPO_DIR}/${p}"
}

load_config() {
  local cfg=$1
  [[ -f "$cfg" ]] || die "Config file '$cfg' not found. Copy config/config.example.sh and edit it."
  # shellcheck disable=SC1090   # path is only known at run time
  source "$cfg"

  SAMPLES_TSV=$(abspath "$SAMPLES_TSV")
  OUTDIR=$(abspath "$OUTDIR")
  ENV_DIR=$(abspath "$ENV_DIR")
  DB_DIR=$(abspath "$DB_DIR")
  ANTISMASH_DB=$(abspath "$ANTISMASH_DB")
  BAKTA_DB=$(abspath "$BAKTA_DB")
  CHECKM2_DB_DIR=$(abspath "$CHECKM2_DB_DIR")
  CARD_DIR=$(abspath "$CARD_DIR")
  GTDBTK_DB=$(abspath "$GTDBTK_DB")
  PFAM_HMM=$(abspath "${PFAM_HMM:-}")

  # Inside a Slurm job, use exactly the CPUs Slurm gave us (never more).
  if [[ -n "${SLURM_CPUS_PER_TASK:-}" ]]; then
    THREADS=$SLURM_CPUS_PER_TASK
  fi
}

# ---------- Finding conda / mamba / micromamba --------------------------------
# All three understand "<tool> run -p <env-folder> <command>", so we just need
# to know which one is installed.
detect_conda() {
  if   command -v conda      &>/dev/null; then CONDA_RUNNER=conda
  elif command -v mamba      &>/dev/null; then CONDA_RUNNER=mamba
  elif command -v micromamba &>/dev/null; then CONDA_RUNNER=micromamba
  else
    [[ "${DRY_RUN:-0}" -eq 1 ]] && { CONDA_RUNNER=conda; return; }
    die "No conda, mamba or micromamba found on PATH (try: module load miniforge, or install Miniforge)."
  fi
  # Use the fastest available solver for creating environments.
  if   command -v mamba      &>/dev/null; then CONDA_CREATOR=mamba
  elif command -v micromamba &>/dev/null; then CONDA_CREATOR=micromamba
  else CONDA_CREATOR=conda
  fi
}

env_path() { echo "${ENV_DIR}/$1"; }

# ---------- Running a command inside a tool's environment ---------------------
# run_in_env ENV_NAME command arg1 arg2 ...
#   * prints the exact command into the step log (so you can copy-paste it later)
#   * runs it inside that tool's conda environment
#   * sends all screen output (stdout + stderr) to the step log
#   * in --dry-run mode it only prints the command
run_in_env() {
  local env_name=$1; shift
  local pretty
  pretty=$(printf '%q ' "$@")
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "    [dry-run] ($env_name) $pretty" >&2
    return 0
  fi
  echo "### $(date '+%F %T')  ($env_name)  $pretty" >>"${STEP_LOG:-/dev/null}"
  "$CONDA_RUNNER" run --no-capture-output -p "$(env_path "$env_name")" "$@" \
    >>"${STEP_LOG:-/dev/null}" 2>&1
}

# run_plain command ... : same idea for commands that need no conda env
run_plain() {
  local pretty
  pretty=$(printf '%q ' "$@")
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "    [dry-run] $pretty" >&2
    return 0
  fi
  echo "### $(date '+%F %T')  $pretty" >>"${STEP_LOG:-/dev/null}"
  "$@" >>"${STEP_LOG:-/dev/null}" 2>&1
}

# require_file FILE "what it is" : stop this step if an expected output is
# missing or empty. Skipped in dry-run (nothing is really produced then).
require_file() {
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  [[ -s "$1" ]] || { log "    expected ${2:-file} not found or empty: $1"; return 1; }
}

# ---------- Resumable steps ---------------------------------------------------
# run_step NAME OUTPUT_DIR FUNCTION
#   If OUTPUT_DIR/.done exists the step already finished on an earlier run and
#   is skipped. Otherwise the old (possibly half-written) folder is removed, the
#   function is run, and .done is written only if it succeeded.
#   --force STEP (or --force all) on the command line makes it run again.
#   This "marker file" trick is what lets you re-start a crashed run without
#   repeating hours of finished work.
should_force() {
  local name=$1 f
  for f in "${FORCE_STEPS[@]:-}"; do
    [[ "$f" == "all" || "$f" == "$name" ]] && return 0
  done
  return 1
}

step_selected() {
  local name=$1 s
  [[ ${#ONLY_STEPS[@]} -eq 0 ]] && return 0
  for s in "${ONLY_STEPS[@]}"; do [[ "$s" == "$name" ]] && return 0; done
  return 1
}

run_step() {
  local name=$1 dir=$2 func=$3 label=${4:-}
  if ! step_selected "$name"; then
    return 0
  fi
  if [[ -f "$dir/.done" ]] && ! should_force "$name"; then
    log "  [$label] $name: already done, skipping"
    return 0
  fi
  log "  [$label] $name: running"
  if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    rm -rf "$dir"
    mkdir -p "$dir"
  fi
  STEP_LOG="$dir/${name}.log"
  local t0=$SECONDS
  if "$func"; then
    [[ "${DRY_RUN:-0}" -eq 0 ]] && date '+%F %T' >"$dir/.done"
    log "  [$label] $name: finished in $(( (SECONDS - t0) / 60 )) min"
    return 0
  else
    log "  [$label] $name: FAILED — see $STEP_LOG"
    return 1
  fi
}

# ---------- Sample sheet --------------------------------------------------------
# read_samples : fills the arrays SAMPLE_IDS, SAMPLE_READS, SAMPLE_GSIZE from
# the tab-separated sample sheet (header line and # comments are ignored).
read_samples() {
  [[ -f "$SAMPLES_TSV" ]] || die "Sample sheet '$SAMPLES_TSV' not found."
  SAMPLE_IDS=(); SAMPLE_READS=(); SAMPLE_GSIZE=()
  local id reads gsize _rest
  while IFS=$'\t' read -r id reads gsize _rest || [[ -n "$id" ]]; do
    id=${id%$'\r'}; reads=${reads%$'\r'}; gsize=${gsize%$'\r'}   # tolerate Windows line endings
    [[ -z "$id" || "$id" == \#* || "$id" == "sample_id" ]] && continue
    [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || die "Sample id '$id' has spaces or odd characters; use letters, digits, . _ -"
    [[ -n "$reads" ]] || die "Sample '$id' has no reads path in $SAMPLES_TSV"
    SAMPLE_IDS+=("$id"); SAMPLE_READS+=("$(abspath "$reads")"); SAMPLE_GSIZE+=("${gsize:-}")
  done <"$SAMPLES_TSV"
  [[ ${#SAMPLE_IDS[@]} -gt 0 ]] || die "No samples found in $SAMPLES_TSV"
}
