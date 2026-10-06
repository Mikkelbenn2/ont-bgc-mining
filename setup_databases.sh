#!/usr/bin/env bash
# =============================================================================
# setup_databases.sh — download the reference databases (run once per server)
#
# Usage:  bin/setup_databases.sh -c config/my_project.sh [--only antismash,bakta,...]
#
#   antismash  ~10 GB   Pfam, MIBiG, ClusterBlast data for antiSMASH (+ Pfam for BiG-SCAPE)
#   bakta      ~1.5 GB  (light) or ~40 GB (full) annotation database
#   checkm2    ~3 GB    DIAMOND database of reference proteins
#   card       <1 GB    CARD resistance database for RGI
#   gtdbtk     ~110 GB  GTDB reference data (only if RUN_GTDBTK=1)
#
# Run on a LOGIN node with internet. Each database is skipped if already present.
# Write down which versions you downloaded — they belong in your Methods section.
# =============================================================================
set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/common.sh"

CONFIG=""; ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c) CONFIG="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' | grep -v '^====='; exit 0 ;;
    *) echo "Unknown option $1" >&2; exit 1 ;;
  esac
done
[[ -n "$CONFIG" ]] || die "Usage: bin/setup_databases.sh -c CONFIG"
load_config "$CONFIG"
detect_conda
mkdir -p "$DB_DIR"
MAIN_LOG="$DB_DIR/setup_databases.log"
STEP_LOG="$MAIN_LOG"

want() { [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]]; }
fail=0

if want antismash; then
  if [[ -d "$ANTISMASH_DB/clusterblast" ]]; then log "antiSMASH databases present — skipping"
  else
    log "Downloading antiSMASH databases to $ANTISMASH_DB ..."
    mkdir -p "$ANTISMASH_DB"
    run_in_env antismash download-antismash-databases --database-dir "$ANTISMASH_DB" \
      && run_in_env antismash antismash --check-prereqs --databases "$ANTISMASH_DB" \
      || { warn "antiSMASH database setup failed"; fail=1; }
  fi
fi

if want bakta; then
  if [[ -d "$BAKTA_DB" ]]; then log "Bakta database present — skipping"
  else
    log "Downloading Bakta '$BAKTA_DB_TYPE' database ..."
    mkdir -p "$(dirname "$BAKTA_DB")"
    run_in_env bakta bakta_db download --output "$(dirname "$BAKTA_DB")" --type "$BAKTA_DB_TYPE" \
      || { warn "Bakta database download failed"; fail=1; }
  fi
fi

if want checkm2; then
  if find "$CHECKM2_DB_DIR" -name '*.dmnd' 2>/dev/null | grep -q .; then log "CheckM2 database present — skipping"
  else
    log "Downloading CheckM2 database ..."
    mkdir -p "$CHECKM2_DB_DIR"
    run_in_env checkm2 checkm2 database --download --path "$CHECKM2_DB_DIR" \
      || { warn "CheckM2 database download failed"; fail=1; }
  fi
fi

if want card; then
  if [[ -d "$CARD_DIR/localDB" ]]; then log "CARD database present — skipping"
  else
    log "Downloading CARD and loading it for RGI ..."
    mkdir -p "$CARD_DIR"
    ( cd "$CARD_DIR" \
      && curl -fsSL https://card.mcmaster.ca/latest/data -o card_data.tar.bz2 \
      && tar -xjf card_data.tar.bz2 \
      && run_in_env rgi rgi load --card_json "$CARD_DIR/card.json" --local ) \
      || { warn "CARD setup failed"; fail=1; }
    # `rgi load --local` writes ./localDB inside CARD_DIR; the pipeline links to it.
  fi
fi

if want gtdbtk && [[ "${RUN_GTDBTK:-1}" -eq 1 ]]; then
  if [[ -d "$GTDBTK_DB/taxonomy" ]]; then log "GTDB-Tk database present — skipping"
  else
    log "Downloading GTDB-Tk reference data (~110 GB, takes hours) ..."
    mkdir -p "$GTDBTK_DB"
    # download-db.sh ships with the conda package and fetches the GTDB release
    # that matches the installed GTDB-Tk version.
    run_in_env gtdbtk bash -c 'export GTDBTK_DATA_PATH="$1"; download-db.sh "$1"' _ "$GTDBTK_DB" \
      || { warn "GTDB-Tk download failed — see docs/03_setup.md for the manual route"; fail=1; }
  fi
fi

[[ $fail -eq 0 ]] && log "Databases ready in $DB_DIR"
exit $fail
