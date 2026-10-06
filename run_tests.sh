#!/usr/bin/env bash
# =============================================================================
# test/run_tests.sh — quick self-test, needs no tools or databases (~2 seconds)
#   1. every bash script parses (bash -n)
#   2. a full --dry-run prints every command for two fake samples
#   3. the summary script runs on fake tool outputs and finds the expected rows
# Run it after every change:  test/run_tests.sh
# =============================================================================
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "1) syntax check"
for f in "$REPO_DIR"/bin/*.sh "$REPO_DIR"/lib/*.sh "$REPO_DIR"/steps/*.sh "$REPO_DIR"/slurm/*.sh; do
  bash -n "$f" && echo "   ok  ${f#"$REPO_DIR"/}"
done

echo "2) dry run"
mkdir -p "$TMP/reads/barcode01"
: >"$TMP/reads/barcode01/a.fastq.gz"; : >"$TMP/reads/iso2.fastq.gz"
printf 'sample_id\treads\tgenome_size\nisoA\t%s\t8m\nisoB\t%s\t\n' \
  "$TMP/reads/barcode01" "$TMP/reads/iso2.fastq.gz" >"$TMP/samples.tsv"
sed -e "s#^SAMPLES_TSV=.*#SAMPLES_TSV=\"$TMP/samples.tsv\"#" \
    -e "s#^OUTDIR=.*#OUTDIR=\"$TMP/results\"#" \
    "$REPO_DIR/config/config.example.sh" >"$TMP/config.sh"
bash "$REPO_DIR/bin/run_pipeline.sh" -c "$TMP/config.sh" --dry-run 2>"$TMP/dry.txt"
grep -c '\[dry-run\]' "$TMP/dry.txt" | xargs echo "   commands printed:"
for tool in NanoPlot filtlong flye medaka_consensus quast.py checkm2 bakta antismash gecco "rgi main" gtdbtk "bigscape cluster" summarise_results.py; do
  grep -q -- "$tool" "$TMP/dry.txt" || { echo "   MISSING: $tool"; exit 1; }
done
echo "   ok  all 13 tools appear in the dry run"

echo "3) summary on mock data"
python3 "$REPO_DIR/test/make_mock_results.py" "$TMP/mock" >/dev/null
python3 "$REPO_DIR/scripts/summarise_results.py" --outdir "$TMP/mock" --samples isoA,isoB \
  --out "$TMP/mock/summary"
if command -v column >/dev/null; then column -t -s $'\t' "$TMP/mock/summary/bgc_summary.tsv"
else cat "$TMP/mock/summary/bgc_summary.tsv"; fi | cut -c1-150
top=$(awk -F'\t' 'NR==2{print $3"|"$4"|"$5}' "$TMP/mock/summary/bgc_summary.tsv")
[[ "$top" == "novel_candidate|isoA|contig_1.region001" || "$top" == "novel_candidate|isoB|contig_1.region001" ]] \
  || { echo "   unexpected top BGC: $top"; exit 1; }
grep -q $'known' "$TMP/mock/summary/bgc_summary.tsv" || { echo "   known BGC not detected"; exit 1; }
echo "   ok  ranking as expected"
echo "All tests passed."
