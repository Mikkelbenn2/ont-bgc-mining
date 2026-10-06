# shellcheck shell=bash
# =============================================================================
# Steps 00-02: get the reads into one file, look at them, filter them
# =============================================================================

# --- 00_reads ----------------------------------------------------------------
# MinKNOW/Dorado write many small FASTQ files per barcode (fastq_pass/barcode01/
# *.fastq.gz). Tools want one file per isolate, so we join them.
# Joining gzip files with plain `cat` is allowed: a gzip file may contain
# several compressed blocks back to back.
step_prepare_reads() {
  local src=$READS_IN out=$READS_RAW
  if [[ -d "$src" ]]; then
    local files=()
    mapfile -t files < <(find "$src" -maxdepth 1 -type f \
      \( -name '*.fastq.gz' -o -name '*.fq.gz' -o -name '*.fastq' -o -name '*.fq' \) | sort)
    [[ ${#files[@]} -gt 0 ]] || { log "    no FASTQ files in folder $src"; return 1; }
    log "    joining ${#files[@]} FASTQ files from $src"
    [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
    : >"$out"                                      # start with an empty file
    local f
    for f in "${files[@]}"; do
      if [[ "$f" == *.gz ]]; then cat "$f" >>"$out"; else gzip -c "$f" >>"$out"; fi
    done
  elif [[ -f "$src" ]]; then
    [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
    if [[ "$src" == *.gz ]]; then ln -sf "$src" "$out"; else gzip -c "$src" >"$out"; fi
  else
    log "    reads path does not exist: $src"
    return 1
  fi
  require_file "$out" "joined reads"
}

# --- 01_read_qc ----------------------------------------------------------------
# NanoPlot draws read-length and read-quality plots. Look at:
#   * read length N50 — longer reads span repeats -> fewer, more complete contigs
#   * mean/median read quality — tells you if FLYE_READ_MODE=nano-hq is right
#   * total bases / genome size = coverage (aim for >= 40x after filtering)
step_read_qc() {
  local d="${SDIR}/01_read_qc"
  run_in_env reads NanoPlot \
    --fastq "$READS_RAW" \
    --outdir "$d" \
    --threads "$THREADS" \
    --tsv_stats \
    --loglength
}

# --- 02_read_filter -----------------------------------------------------------
# Filtlong removes very short reads and the lowest-quality reads. Fewer, better
# reads give Flye an easier job and the polisher cleaner evidence.
# Filtlong writes plain FASTQ to the screen ("stdout"), so we pipe it into gzip.
# Because that needs a pipe "|", we run it through `bash -c '...'`, passing the
# values in as $1, $2, ... — this avoids quoting problems with odd file names.
step_read_filter() {
  local d="${SDIR}/02_read_filter"
  local args=(--min_length "$FILTLONG_MIN_LEN" --keep_percent "$FILTLONG_KEEP_PERCENT")
  [[ -n "${FILTLONG_TARGET_BASES:-}" ]] && args+=(--target_bases "$FILTLONG_TARGET_BASES")

  run_in_env reads bash -c 'set -o pipefail; out=$1; shift; filtlong "$@" | gzip -c > "$out"' \
    _ "$READS_FILT" "${args[@]}" "$READS_RAW" || return 1
  require_file "$READS_FILT" "filtered reads" || return 1

  # Before/after numbers in one small table (used by the final summary).
  run_in_env reads bash -c 'seqkit stats -a -T -j "$1" "$2" "$3" > "$4"' \
    _ "$THREADS" "$READS_RAW" "$READS_FILT" "$d/read_stats.tsv"
}
