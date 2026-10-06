#!/usr/bin/env bash
# =============================================================================
# slurm/submit.sh — run the whole pipeline on a Slurm cluster
#
# Usage (on the login node, from the repo folder):
#   slurm/submit.sh -c config/my_project.sh
#
# What it does:
#   1. submits a job ARRAY: one job per isolate, all running in parallel
#      (task 1 = first sample in the sheet, task 2 = second, ...)
#   2. submits ONE cohort job (GTDB-Tk, BiG-SCAPE, summary) that waits for the
#      whole array to end (--dependency=afterany) and then compares the samples.
# Resources come from the SLURM_* settings in your config file.
#
# Watch progress:   squeue --me
# Job output:       <OUTDIR>/logs/slurm/
# Cancel all:       scancel <jobid>
# =============================================================================
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/common.sh"

CONFIG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c) CONFIG="$2"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' | grep -v '^====='; exit 0 ;;
    *) echo "Unknown option $1" >&2; exit 1 ;;
  esac
done
[[ -n "$CONFIG" ]] || die "Usage: slurm/submit.sh -c CONFIG"
CONFIG=$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")   # absolute path
load_config "$CONFIG"
read_samples
command -v sbatch >/dev/null || die "sbatch not found — are you on the Slurm login node?"

LOGDIR="$OUTDIR/logs/slurm"
mkdir -p "$LOGDIR"
N=${#SAMPLE_IDS[@]}

# Optional settings become sbatch options only if they are filled in.
common=()
[[ -n "${SLURM_PARTITION:-}" ]] && common+=(--partition "$SLURM_PARTITION")
[[ -n "${SLURM_ACCOUNT:-}"   ]] && common+=(--account "$SLURM_ACCOUNT")

array_id=$(sbatch --parsable "${common[@]}" \
  --job-name "bgc_${PROJECT_NAME}" \
  --array "1-${N}" \
  --cpus-per-task "$SLURM_SAMPLE_CPUS" \
  --mem "$SLURM_SAMPLE_MEM" \
  --time "$SLURM_SAMPLE_TIME" \
  --output "$LOGDIR/sample_%A_%a.out" \
  "$REPO_DIR/slurm/sample_job.sh" "$REPO_DIR" "$CONFIG")
echo "Submitted sample array job $array_id ($N isolates)"

cohort_id=$(sbatch --parsable "${common[@]}" \
  --job-name "bgc_${PROJECT_NAME}_cohort" \
  --dependency "afterany:${array_id}" \
  --cpus-per-task "$SLURM_COHORT_CPUS" \
  --mem "$SLURM_COHORT_MEM" \
  --time "$SLURM_COHORT_TIME" \
  --output "$LOGDIR/cohort_%j.out" \
  --wrap "\"$REPO_DIR/bin/run_pipeline.sh\" -c \"$CONFIG\" --cohort-only")
echo "Submitted cohort job $cohort_id (starts when all samples are finished)"
echo "Check with: squeue --me"
