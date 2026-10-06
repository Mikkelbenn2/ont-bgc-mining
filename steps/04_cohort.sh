# shellcheck shell=bash
# =============================================================================
# Steps 10-12: run once over ALL samples together
#   10_taxonomy  GTDB-Tk  — what species is each isolate?
#   11_bigscape  BiG-SCAPE — group BGCs into families, together with MIBiG
#   12_summary   one genome table + one ranked BGC table
# These run after every sample has finished, because they compare samples.
# =============================================================================

COHORT_DIR() { echo "${OUTDIR}/cohort"; }

# Lists the samples whose genome / antiSMASH output exists (skips failed ones).
finished_samples() {
  local id
  for id in "${SAMPLE_IDS[@]}"; do
    set_sample_paths "$id"
    if [[ "${DRY_RUN:-0}" -eq 1 || -s "$ASSEMBLY" ]]; then echo "$id"; fi
  done
}

# --- 10_taxonomy ----------------------------------------------------------------
# GTDB-Tk places each genome in the GTDB reference tree (120 bacterial marker
# genes) and checks average nucleotide identity (ANI) to reference genomes.
# ANI >= 95 % to a reference = same species. If no species is assigned
# ("s__" empty) the isolate may be a NEW species — interesting in itself,
# because new taxa tend to carry new BGCs.
# Genome-based taxonomy is much more precise than the 16S rRNA identification
# typically used in Tiny Earth, especially within Streptomyces.
step_taxonomy() {
  local d
  d="$(COHORT_DIR)/10_taxonomy"
  mkdir -p "$d/genomes"
  local id
  for id in $(finished_samples); do
    set_sample_paths "$id"
    run_plain ln -sf "$ASSEMBLY" "$d/genomes/${id}.fasta"
  done
  # GTDB-Tk finds its database through the variable GTDBTK_DATA_PATH. The conda
  # package sets its own value when the env activates, so we set ours inside.
  run_in_env gtdbtk bash -c 'export GTDBTK_DATA_PATH="$1"; shift; gtdbtk "$@"' _ "$GTDBTK_DB" \
    classify_wf \
    --genome_dir "$d/genomes" \
    --extension fasta \
    --out_dir "$d/gtdbtk" \
    --cpus "$THREADS" \
    --skip_ani_screen
}

# --- 11_bigscape ------------------------------------------------------------------
# BiG-SCAPE compares every BGC with every other BGC (shared protein domains,
# their order, and sequence identity) and groups similar ones into Gene Cluster
# Families (GCFs). We add the MIBiG reference BGCs to the comparison:
#   * a GCF that contains a MIBiG entry  -> your BGC resembles a KNOWN pathway
#   * a GCF with only your BGCs          -> no characterised relative = candidate novelty
#   * the same GCF in several isolates   -> the same pathway shared between strains
# antiSMASH names every region file "contig_1.region001.gbk", so files from
# different isolates would clash; we prefix each with the sample id.
step_bigscape() {
  local d
  d="$(COHORT_DIR)/11_bigscape"
  mkdir -p "$d/input"
  local id f n=0
  for id in $(finished_samples); do
    set_sample_paths "$id"
    [[ "${DRY_RUN:-0}" -eq 1 ]] && continue
    for f in "$ANTISMASH_DIR"/*.region*.gbk; do
      [[ -e "$f" ]] || continue
      cp "$f" "$d/input/${id}__$(basename "$f")"
      n=$((n + 1))
    done
  done
  log "    collected $n antiSMASH regions for BiG-SCAPE"
  [[ "${DRY_RUN:-0}" -eq 1 || $n -gt 0 ]] || { log "    no BGC regions found — nothing to cluster"; return 0; }

  local pfam=$PFAM_HMM
  if [[ -z "$pfam" ]]; then   # reuse the Pfam that antiSMASH already downloaded
    pfam=$(find "$ANTISMASH_DB" -name 'Pfam-A.hmm' 2>/dev/null | sort | tail -n 1)
  fi
  [[ -n "$pfam" || "${DRY_RUN:-0}" -eq 1 ]] || { log "    Pfam-A.hmm not found; set PFAM_HMM in the config"; return 1; }

  run_in_env bigscape bigscape cluster \
    -i "$d/input" \
    -o "$d/output" \
    -p "${pfam:-Pfam-A.hmm}" \
    --mibig-version "$BIGSCAPE_MIBIG_VERSION" \
    --gcf-cutoffs "$BIGSCAPE_CUTOFF" \
    --include-singletons \
    --label "$PROJECT_NAME" \
    -c "$THREADS"
}

# --- 12_summary -------------------------------------------------------------------
# Collects the key numbers from every tool into two tab-separated tables that
# open in Excel or R:  genome_summary.tsv  and  bgc_summary.tsv (ranked).
# Uses only the Python standard library, so no extra environment is needed.
step_summary() {
  local d
  d="$(COHORT_DIR)/12_summary"
  run_plain python3 "${REPO_DIR}/scripts/summarise_results.py" \
    --outdir "$OUTDIR" \
    --samples "$(finished_samples | paste -sd, -)" \
    --bigscape-cutoff "$BIGSCAPE_CUTOFF" \
    --known "$KNOWN_SIMILARITY" \
    --related "$RELATED_SIMILARITY" \
    --out "$d"
}
