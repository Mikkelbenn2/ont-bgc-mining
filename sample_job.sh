#!/usr/bin/env bash
# =============================================================================
# slurm/sample_job.sh — one task of the Slurm job array = one isolate
# Submitted by slurm/submit.sh; not meant to be run by hand.
#   $1 = repository folder, $2 = config file
# Slurm copies job scripts to a spool folder before running them, so the repo
# location is passed in explicitly instead of being worked out from this file.
# =============================================================================
set -uo pipefail
REPO_DIR=$1
CONFIG=$2
source "$REPO_DIR/lib/common.sh"
load_config "$CONFIG"
read_samples

idx=$(( SLURM_ARRAY_TASK_ID - 1 ))          # Slurm counts from 1, bash arrays from 0
SAMPLE_ID=${SAMPLE_IDS[$idx]}
echo "Array task $SLURM_ARRAY_TASK_ID -> sample $SAMPLE_ID on $(hostname) with ${SLURM_CPUS_PER_TASK:-?} CPUs"

exec "$REPO_DIR/bin/run_pipeline.sh" -c "$CONFIG" --sample "$SAMPLE_ID" --samples-only
