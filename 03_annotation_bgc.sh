# shellcheck shell=bash
# =============================================================================
# Steps 06-09: annotate genes, find BGCs (two ways), find resistance genes
# =============================================================================

# --- 06_annotation --------------------------------------------------------------
# Bakta finds every gene (Pyrodigal for proteins, plus tRNA/rRNA/ncRNA/CRISPR
# finders) and names them using a large, regularly updated database.
# We use Bakta instead of Prokka because Prokka is no longer maintained and
# Bakta's database-backed annotation gives more, and more consistent, names.
# The .gbff file (GenBank format) carries both the DNA and the gene features and
# is what antiSMASH reads next.
#   --keep-contig-headers keeps Flye's short names (contig_1 ...) so every tool
#   uses the same contig names, which the summary script relies on.
step_annotation() {
  local d="${SDIR}/06_annotation"
  run_in_env bakta bakta \
    --db "$BAKTA_DB" \
    --output "$d" \
    --prefix "$SAMPLE" \
    --threads "$THREADS" \
    --keep-contig-headers \
    --skip-plot \
    --force \
    "$ASSEMBLY" || return 1
  require_file "$GBFF" "Bakta GenBank file"
}

# --- 07_antismash -----------------------------------------------------------------
# antiSMASH is the reference tool for BGC detection. It uses hand-curated rules
# ("a region with a PKS-KS domain AND an AT domain = T1PKS") based on profile
# HMMs of core biosynthetic enzymes, then extends each hit to a "region".
# Comparison modules (set in ANTISMASH_EXTRA_ARGS):
#   --cb-knownclusters  compare each region to MIBiG (experimentally
#                       characterised BGCs) -> "Most similar known cluster" + %
#   --cc-mibig          ClusterCompare against MIBiG (protein-level)
#   --cb-subclusters    look for known sub-pathways (e.g. a precursor operon)
#   --asf / --rre / --tfbs  active sites, RiPP recognition elements, binding sites
# We give antiSMASH Bakta's genes (--genefinding-tool none). If antiSMASH
# rejects the GenBank file it falls back to the FASTA + its own Prodigal run.
step_antismash() {
  # antiSMASH refuses to write into a folder that already holds other files
  # (our step log lives in 07_antismash/), so its results go into a subfolder.
  local d=$ANTISMASH_DIR
  # shellcheck disable=SC2206
  local extra=($ANTISMASH_EXTRA_ARGS)
  local common=(--cpus "$THREADS" --taxon bacteria --databases "$ANTISMASH_DB"
                --output-basename "$SAMPLE" "${extra[@]}")

  if ! run_in_env antismash antismash "${common[@]}" \
         --output-dir "$d" --genefinding-tool none "$GBFF"; then
    warn "antiSMASH failed on the Bakta GenBank for $SAMPLE; retrying on FASTA with Prodigal"
    rm -rf "$d"
    run_in_env antismash antismash "${common[@]}" \
      --output-dir "$d" --genefinding-tool prodigal "$ASSEMBLY" || return 1
  fi
  require_file "$d/${SAMPLE}.json" "antiSMASH JSON"
}

# --- 08_gecco ---------------------------------------------------------------------
# GECCO is a machine-learning detector (a Conditional Random Field over the
# Pfam domains of consecutive genes). Unlike antiSMASH it uses no hand-written
# rules, so it can flag clusters of unusual architecture that the rules miss
# — and it gives a probability per cluster. We use it as a second opinion:
# a region found by BOTH tools is well supported; one found only by GECCO is
# worth a look as a possibly unconventional BGC.
step_gecco() {
  local d="${SDIR}/08_gecco"
  run_in_env gecco gecco run --genome "$ASSEMBLY" --output-dir "$d" --jobs "$THREADS"
}

# --- 09_resistance ------------------------------------------------------------------
# RGI compares predicted proteins against CARD (Comprehensive Antibiotic
# Resistance Database). Two reasons this matters for antibiotic discovery:
#   1) a resistance gene INSIDE a BGC is often the producer's self-resistance
#      gene -> hints at the compound's target and that it is an antibiotic
#      (the idea behind the ARTS tool);
#   2) the isolate's overall resistance profile (biosafety, One Health angle).
# `rgi --local` looks for the database in ./localDB, so we link the shared copy
# (made once by setup_databases.sh) into this step's folder and run from there.
step_resistance() {
  local d="${SDIR}/09_resistance"
  run_plain ln -sfn "${CARD_DIR}/localDB" "$d/localDB" || return 1
  ( [[ "${DRY_RUN:-0}" -eq 1 ]] || cd "$d" || exit 1
    run_in_env rgi rgi main \
      --input_sequence "$ASSEMBLY" \
      --output_file "$d/${SAMPLE}_rgi" \
      --input_type contig \
      --alignment_tool DIAMOND \
      --num_threads "$THREADS" \
      --local --clean )
}
