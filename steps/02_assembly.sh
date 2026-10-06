# shellcheck shell=bash
# =============================================================================
# Steps 03-05: assemble the genome, polish it, check its quality
# =============================================================================

# --- 03_assembly --------------------------------------------------------------
# Flye builds a "repeat graph" from read overlaps and walks through it to make
# contigs. For a good bacterial isolate you hope for 1 circular chromosome
# (or 1 LINEAR one — Streptomyces chromosomes are linear!) plus any plasmids.
#   --nano-hq   reads from R10.4.1 + Dorado hac/sup (~Q15-20+)
#   --nano-raw  older/noisier reads
# Flye also polishes its own result once; assembly_info.txt lists every contig
# with its length, coverage and whether Flye found it to be circular.
step_assembly() {
  local d="${SDIR}/03_assembly"
  local args=("--${FLYE_READ_MODE}" "$READS_FILT" --out-dir "$d" --threads "$THREADS")
  [[ -n "$GSIZE" ]] && args+=(--genome-size "$GSIZE")
  # shellcheck disable=SC2206   # we WANT word-splitting of the extra-args string
  [[ -n "${FLYE_EXTRA_ARGS:-}" ]] && args+=($FLYE_EXTRA_ARGS)

  run_in_env flye flye "${args[@]}" || return 1
  require_file "$DRAFT" "Flye assembly"
}

# --- 04_polish ----------------------------------------------------------------
# Polishing maps the reads back onto the draft and uses a neural network to
# fix the remaining small errors (mostly 1-base insertions/deletions in
# homopolymers like AAAAAA). Each indel inside a gene shifts the reading frame
# and splits the protein — fatal for the huge NRPS/PKS genes antiSMASH reads.
# The "--bacteria" models were trained on native bacterial DNA, whose
# methylation otherwise confuses basecalling at certain motifs.
#
# Caution (Wick 2024): if a small plasmid is missing from the assembly, its
# reads can pile onto a similar chromosomal region and the polisher "fixes" it
# wrongly. We therefore keep the unpolished draft and QUAST compares both.
step_polish() {
  local d="${SDIR}/04_polish"
  case "$POLISHER" in
    medaka)
      run_in_env medaka medaka_consensus \
        -i "$READS_FILT" -d "$DRAFT" -o "$d/medaka" -t "$THREADS" --bacteria || return 1
      run_plain cp "$d/medaka/consensus.fasta" "$ASSEMBLY" || return 1
      ;;
    dorado)
      # 1) align reads to draft, sort + index (samtools comes from the medaka env)
      run_in_env medaka bash -c \
        'set -o pipefail; "$1" aligner "$2" "$3" | samtools sort -@ "$4" -o "$5" - && samtools index "$5"' \
        _ "$DORADO_BIN" "$DRAFT" "$READS_FILT" "$THREADS" "$d/reads_to_draft.bam" || return 1
      # 2) polish with the bacterial model
      run_plain "$DORADO_BIN" polish "$d/reads_to_draft.bam" "$DRAFT" \
        --bacteria --threads "$THREADS" -o "$d/dorado" || return 1
      run_plain cp "$d/dorado/consensus.fasta" "$ASSEMBLY" || return 1
      ;;
    none)
      log "    POLISHER=none: using the Flye assembly as the final genome"
      run_plain cp "$DRAFT" "$ASSEMBLY" || return 1
      ;;
    *) log "    unknown POLISHER '$POLISHER' (use medaka, dorado or none)"; return 1 ;;
  esac
  require_file "$ASSEMBLY" "polished assembly"
}

# --- 05_assembly_qc -------------------------------------------------------------
# QUAST: contiguity — number of contigs, total length, N50, GC%.
#        Draft and polished are compared side by side.
# CheckM2: completeness and contamination, estimated from which conserved
#        genes are present (machine-learning model). Rule of thumb for an
#        isolate genome: completeness > 95 %, contamination < 5 %.
#        High contamination = your "isolate" may be a mixed culture.
step_assembly_qc() {
  local d="${SDIR}/05_assembly_qc"
  run_in_env quast quast.py -o "$d/quast" -t "$THREADS" \
    --labels "draft,polished" "$DRAFT" "$ASSEMBLY" || return 1

  local dmnd
  dmnd=$(find "$CHECKM2_DB_DIR" -name '*.dmnd' 2>/dev/null | head -n 1)
  [[ -n "$dmnd" || "${DRY_RUN:-0}" -eq 1 ]] || { log "    CheckM2 database (.dmnd) not found in $CHECKM2_DB_DIR"; return 1; }
  run_in_env checkm2 checkm2 predict --threads "$THREADS" \
    --input "$ASSEMBLY" --output-directory "$d/checkm2" \
    --database_path "${dmnd:-CHECKM2_DB.dmnd}" --force || return 1

  # Keep Flye's per-contig table (circular? coverage?) next to the QC results.
  run_plain cp "${SDIR}/03_assembly/assembly_info.txt" "$d/flye_assembly_info.txt"
}
