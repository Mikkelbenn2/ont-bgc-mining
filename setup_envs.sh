#!/usr/bin/env bash
# =============================================================================
# setup_envs.sh — create one conda environment per tool (run once per server)
#
# Usage:  bin/setup_envs.sh -c config/my_project.sh [--only antismash,gecco]
#
# Why one environment per tool? Bioinformatics tools pin conflicting versions
# of Python, BLAST, HMMER etc. Installing them all together usually fails or
# silently breaks one of them. Separate environments never interfere.
# The recipes are the envs/*.yml files; existing environments are skipped.
# Run this on a LOGIN node (compute nodes often have no internet).
# =============================================================================
set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/common.sh"

CONFIG=""; ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c) CONFIG="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' | grep -v '^====='; exit 0 ;;
    *) echo "Unknown option $1" >&2; exit 1 ;;
  esac
done
[[ -n "$CONFIG" ]] || die "Usage: bin/setup_envs.sh -c CONFIG"
load_config "$CONFIG"
detect_conda
mkdir -p "$ENV_DIR"
MAIN_LOG="$ENV_DIR/setup_envs.log"

fail=0
for yml in "$REPO_DIR"/envs/*.yml; do
  name=$(basename "$yml" .yml)
  [[ -n "$ONLY" && ",$ONLY," != *",$name,"* ]] && continue
  prefix=$(env_path "$name")
  if [[ -d "$prefix/conda-meta" ]]; then
    log "env '$name' already exists at $prefix — skipping"
    continue
  fi
  log "creating env '$name' with $CONDA_CREATOR (this can take several minutes)..."
  if [[ "$CONDA_CREATOR" == micromamba ]]; then
    cmd=(micromamba create -y -p "$prefix" -f "$yml")
  else
    cmd=("$CONDA_CREATOR" env create -p "$prefix" -f "$yml")
  fi
  if "${cmd[@]}" >>"$ENV_DIR/setup_envs.log" 2>&1; then
    log "  ok: $name"
  else
    warn "  failed: $name (details in $ENV_DIR/setup_envs.log)"; fail=1
  fi
done

[[ $fail -eq 0 ]] && log "All environments ready in $ENV_DIR. Next: bin/setup_databases.sh -c $CONFIG"
exit $fail
