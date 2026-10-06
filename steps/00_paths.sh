# shellcheck shell=bash
# =============================================================================
# steps/00_paths.sh — where every file of one sample lives
#
# set_sample_paths SAMPLE_ID  defines variables that all later steps use, so a
# file name is written in exactly one place. If you rename a folder, do it here.
# =============================================================================

set_sample_paths() {
  SAMPLE=$1
  SDIR="${OUTDIR}/samples/${SAMPLE}"

  READS_RAW="${SDIR}/00_reads/${SAMPLE}.fastq.gz"            # all reads, one file
  READS_FILT="${SDIR}/02_read_filter/${SAMPLE}.filtered.fastq.gz"
  DRAFT="${SDIR}/03_assembly/assembly.fasta"                  # Flye output
  ASSEMBLY="${SDIR}/04_polish/${SAMPLE}.fasta"                # final genome used downstream
  GBFF="${SDIR}/06_annotation/${SAMPLE}.gbff"                 # Bakta annotation
  ANTISMASH_DIR="${SDIR}/07_antismash/antismash"           # antiSMASH output (html, json, region gbks)
}
