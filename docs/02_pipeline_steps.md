# 2. The pipeline, step by step

Each section covers **what** the step does, **why** it's there, **why this tool**, the **key settings**, and **what to check** in the output. Folder names match the output: `results/<project>/samples/<isolate>/<step>/`. Every step folder has a `<step>.log` with the exact command that was run and everything the tool printed.

---

## 00_reads — gather the reads

**What.** MinKNOW/Dorado writes many small `fastq.gz` files per barcode. They are joined into `<isolate>.fastq.gz`.
**Why.** Every later tool expects one read file per isolate.
**Check.** If an isolate has suspiciously few reads, check that the sample sheet points at the right barcode folder.

## 01_read_qc — NanoPlot

**What.** Plots and statistics of read length and quality (`NanoPlot-report.html`, `NanoStats.txt`).
**Why.** It catches bad runs *before* you spend hours assembling them.
**Check.**

- **Read length N50.** For Streptomyces, aim for > 10 kb. Long reads resolve the repeats inside PKS/NRPS genes.
- **Mean read quality.** About Q15–20+ means R10.4.1 hac/sup reads, so keep `FLYE_READ_MODE="nano-hq"`. If it's around Q10, the reads are older or noisier and `nano-raw` fits better.
- **Total bases ÷ expected genome size = coverage.** Below about 30x is a reason to sequence again.

**Alternatives.** NanoQ (faster, text only) and pycoQC (needs the sequencing summary file).

## 02_read_filter — Filtlong (+ SeqKit stats)

**What.** Removes reads shorter than `FILTLONG_MIN_LEN` (1 kb) and the worst 5 % of bases (`--keep_percent 95`). Optionally it can also cap total data with `--target_bases`.
**Why.** Very short and very low-quality reads add noise and little information, so Flye and the polisher work better without them. Very deep data (> 150x) only slows Flye, which is what `FILTLONG_TARGET_BASES` is for: for example, about 100x = 100 × genome size.
**Why Filtlong.** It scores reads by length *and* quality together and keeps the best ones, which is exactly what an assembler wants. Chopper is a fine alternative that filters by thresholds.
**Note.** No separate adapter trimming (Porechop) is done. Dorado trims adapters during basecalling by default, and Porechop is no longer maintained.
**Check.** `read_stats.tsv` compares reads and bases before and after filtering. Usually more than 90 % of bases are kept.

## 03_assembly — Flye

**What.** De novo assembly. The output is `assembly.fasta` plus `assembly_info.txt` (length, depth, circular yes/no for each contig).
**Why Flye.** It is accurate, fast, handles repeats well, is the most widely used long-read assembler for bacteria, and is easy to run. The current gold standard for a *perfect* genome is to build several assemblies with different tools and merge them (**Autocycler**, Wick et al. 2025). That gives the best structural accuracy, especially for small plasmids, but costs more time and a manual check. It's a good upgrade for the 2–3 most interesting isolates.
**Key settings.**

- `--nano-hq` vs `--nano-raw` must match your basecalling (see 01).
- `--genome-size` is optional and only used with `--asm-coverage`.

**Check.**

- The chromosome should be one long contig. Linear is normal for *Streptomyces*.
- Depth should be even across the chromosome. A contig with 2–5x the chromosome's depth is usually a plasmid (several copies per cell).
- Many short contigs at low depth can mean contamination.

## 04_polish — Medaka (default) or Dorado polish

**What.** Maps the reads to the draft and corrects small errors (mainly homopolymer indels).
**Why.** One indel = a frameshift = a broken gene. BGC genes are among the longest in the genome, so they collect the most errors.
**Why the bacterial models (`--bacteria`).** Native bacterial DNA is methylated, and methylated motifs cause systematic basecalling errors. The bacterial model was trained to correct those.
**Medaka or Dorado?** Both come from ONT. In Ryan Wick's 2025–2026 benchmarks, `dorado polish --bacteria` is now the recommended polisher. Medaka is the default here because it installs from bioconda and accepts any FASTQ. Dorado polish needs the Dorado binary and reads that still carry Dorado's header tags. If you have both, try `POLISHER="dorado"`.
**Pitfall.** If a small plasmid is *missing* from the assembly, its reads may map to a similar chromosomal region, and the polisher then introduces errors there. The unpolished draft is kept, and QUAST compares both.
**Check.** In QUAST (step 05), draft and polished should be almost identical in length, typically differing by tens to hundreds of bp. A big difference is a red flag.

## 05_assembly_qc — QUAST + CheckM2

**What.**

- **QUAST** reports contiguity: number of contigs, total length, N50 and GC% for the draft and polished assembly side by side.
- **CheckM2** estimates completeness and contamination with a machine-learning model trained on conserved gene content.

**Why CheckM2 and not CheckM1.** It's faster and more accurate for novel lineages, and it doesn't need a marker set chosen by hand.
**Check.** See the table in `01_concepts.md`: completeness > 95 %, contamination < 5 %. Report both in your Results.

## 06_annotation — Bakta

**What.** Finds and names all genes (CDS, tRNA, rRNA, ncRNA, CRISPR, …). It writes `.gbff` (GenBank), `.gff3`, `.faa` (proteins), `.tsv` and a summary `.txt`.
**Why Bakta instead of Prokka.** Prokka (named in the P7 outline) is no longer actively maintained. Bakta is its successor in practice. It uses a large, versioned database with fast protein identification, which gives more and more consistent gene names, and it can write submission-ready (INSDC-compliant) files with `--compliant`. **→ Update section 6.2 of the report from Prokka to Bakta.**
**Key setting.** `--keep-contig-headers` keeps the contig names identical in every tool, which the summary relies on.
**Check.** The number of CDS should be roughly genome size ÷ 1 kb; for an 8 Mb Streptomyces that's about 7,000–8,000. Many short "hypothetical proteins" can point to frameshifts, which means polishing didn't work well.

## 07_antismash — antiSMASH 8

**What.** Detects BGC **regions**, assigns types (101 types in v8), analyses domains, predicts NRPS/PKS substrates, and compares each region to MIBiG 4.0 (KnownClusterBlast). The output is `index.html` (open in a browser), `<isolate>.json` (everything, machine-readable) and one `.region###.gbk` file per BGC.
**Why antiSMASH.** It's the community standard, actively developed, and its MIBiG comparison is the basis of the novelty call.
**Input.** It reads Bakta's GenBank file (`--genefinding-tool none`), so gene calls are identical across all tools. If antiSMASH rejects that file, the step automatically retries on the FASTA using Prodigal.
**Key settings** (`ANTISMASH_EXTRA_ARGS`):

- `--cb-knownclusters`: closest MIBiG BGC plus % similarity. **Most important.**
- `--cc-mibig`: ClusterCompare, a protein-level comparison with MIBiG.
- `--cb-subclusters`: known sub-pathways (for example a precursor operon).
- `--asf --rre --tfbs`: active sites, RiPP recognition elements, regulator binding sites.
- `--cb-general` is *off*. It compares against the whole antiSMASH database, which is informative but slow.

**Check.** In `index.html`, the overview table lists each region with its type and "Most similar known cluster (%)". Click into the top candidates from `bgc_summary.tsv`. Regions marked as being on a **contig edge** may be incomplete.

## 08_gecco — GECCO (machine learning)

**What.** A Conditional Random Field over Pfam domains predicts BGC regions with a probability, plus a coarse type (polyketide, NRP, RiPP, terpene, …).
**Why.** It's a second, rule-free opinion (see `01_concepts.md`, section 5) and the ML/"AI" component of BGC *detection*.
**Check.** Clusters found by GECCO but not by antiSMASH appear in the summary as `gecco_only_check_manually`. Look at their genes in the Bakta annotation.

## 09_resistance — RGI + CARD

**What.** Finds known antibiotic resistance genes with "Perfect" and "Strict" hits only. The output is `<isolate>_rgi.txt` and `.json`.
**Why here.** (1) A resistance gene **inside** a BGC is often the producer's self-resistance gene, which hints at both activity and target. The summary flags this automatically. (2) It gives the isolate's overall resistome, which matters for biosafety and the One Health angle in your introduction.
**Fixed from v1.** `rgi load --local` puts the database in `./localDB`, so the old script's `rgi main --local` couldn't find it. The database is now loaded once into `CARD_DIR/localDB` and linked into each run folder.

## 10_taxonomy — GTDB-Tk (cohort)

**What.** Places all genomes in the GTDB tree and assigns species by ANI (≥ 95 % = same species).
**Why.** Tiny Earth usually identifies isolates by 16S rRNA, which can't separate many *Streptomyces* species. Genome taxonomy is precise, and an isolate with no species match is potentially new, which strengthens a novelty argument.
**Resources.** It needs about 64–100 GB RAM and the roughly 110 GB database. That's why it runs once for all genomes in the cohort job. Set `RUN_GTDBTK=0` to skip it.
**Check.** `gtdbtk.bac120.summary.tsv`: `classification` and `closest_genome_ani`.

## 11_bigscape — BiG-SCAPE 2 (cohort)

**What.** Networks all BGCs from all isolates **together with MIBiG**, then groups them into Gene Cluster Families at distance cutoff 0.30.
**Why.**

- It shows which isolates share a pathway, which tells you whether you are re-finding the same thing.
- It shows whether a family includes a characterised MIBiG cluster.

KnownClusterBlast compares gene by gene. BiG-SCAPE compares whole architectures, so the two complement each other.
**Note.** `--mibig-version 4.0` makes BiG-SCAPE download MIBiG the first time. If compute nodes have no internet, run this step once on the login node:

```bash
bin/run_pipeline.sh -c config/p7.sh --cohort-only --steps 11_bigscape
```

**Check.** Open `output/index.html` and find the families that contain your top-ranked BGCs.

## 12_summary — the two tables

`genome_summary.tsv` and `bgc_summary.tsv` are explained in `01_concepts.md` (section 6) and the README. Both load straight into R:

```r
library(readr)
bgc <- read_tsv("results/tiny_earth_P7/cohort/12_summary/bgc_summary.tsv")
```

The summary is always rebuilt when the cohort steps run, and you can rebuild it on its own:

```bash
bin/run_pipeline.sh -c config/p7.sh --cohort-only --steps 12_summary
```
