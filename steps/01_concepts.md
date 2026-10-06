steps# 1. Concepts: from soil isolate to candidate antibiotic

This page explains the ideas behind the pipeline. The step-by-step details are in `02_pipeline_steps.md`.

## The question

Tiny Earth isolates were picked because they showed **bioactivity** on a plate: a zone of inhibition against a tester strain. The plate tells you *that* something is made. It doesn't tell you *what* is made, or whether it's a compound we already know. Most "hits" from soil turn out to be well-known compounds such as streptomycin-like aminoglycosides or actinomycin, and rediscovering them costs time and money.

Genome mining asks a different question: **which biosynthetic gene clusters does this genome carry, and how different are they from every cluster we already know?** A cluster that doesn't resemble any characterised pathway is a candidate for a new molecule.

## 1. The data: Oxford Nanopore long reads

- ONT sequencing threads single DNA molecules through a protein pore and records the change in electric current. **Basecalling** (Dorado) turns that signal into bases. Reads are long, often 5–50 kb or more.
- **Why long reads matter for BGCs.** NRPS and PKS genes are huge (10–100 kb per cluster) and full of repeated modules. Short reads (Illumina, 150 bp) can't span those repeats, so assemblies break exactly inside the clusters you care about. Long reads span them, which gives complete, single-contig BGCs.
- **Accuracy.** With R10.4.1 flow cells and Dorado *sup*, single-read accuracy is about Q20 (99 %). After assembly and polishing, the consensus is usually above Q50 (fewer than 1 error per 100 kb). The remaining errors are mostly **homopolymer indels**: one base too many or too few in runs like `GGGGGG`.
- **Coverage (depth)** is the number of times each base was read: total bases divided by genome size. Aim for 40–100x after filtering. Below about 20x, assemblies fragment and errors stay in the consensus.

## 2. Assembly: rebuilding the genome

- **De novo assembly** finds overlaps between reads and merges them into **contigs**. Flye builds a *repeat graph* and resolves repeats that reads span.
- **A perfect bacterial assembly** has one contig per replicon: the chromosome plus any plasmids. Flye marks contigs it could close into a circle as `circ. = Y` in `assembly_info.txt`.
- **Streptomyces chromosomes are linear** (about 8–10 Mb, with terminal inverted repeats), and so are some of their plasmids. A linear Streptomyces chromosome is therefore *not* a failed assembly. It's also why this pipeline does **not** rotate contigs to start at *dnaA*. Tools that do this (dnaapler) assume a circular chromosome.
- **Polishing** maps the reads back to the draft and corrects small errors with a neural network. This matters for BGCs because **one indel inside a gene shifts the reading frame**. The protein then appears truncated, the annotation splits one NRPS gene into two, and domain predictions become wrong.

## 3. Quality control: can we trust this genome?

| Check | Tool | Good isolate genome | Warning sign |
|---|---|---|---|
| Contiguity | QUAST, Flye | 1–5 contigs, N50 ≈ chromosome size | Hundreds of contigs, which points to low coverage or degraded DNA |
| Completeness | CheckM2 | > 95 % | < 90 %, which means genes are missing and BGCs may be missing too |
| Contamination | CheckM2 | < 5 % | > 5–10 %, which suggests a mixed culture and BGCs that may belong to another organism |
| Identity | GTDB-Tk | Species assigned, ANI ≥ 95 % | No species (`s__` empty): possibly a **new species**, which is interesting |

## 4. Biosynthetic gene clusters (BGCs)

Bacteria make **specialised (secondary) metabolites** with enzymes whose genes sit next to each other in the genome as a **cluster**. A typical BGC contains:

- **Core biosynthetic genes**, which build the backbone:
  - **NRPS** (non-ribosomal peptide synthetases). These are assembly lines of modules, and each module adds one amino acid. Examples: vancomycin, daptomycin, penicillin precursors.
  - **PKS** (polyketide synthases; type I modular, II iterative, III). They build carbon chains from acyl-CoA units. Examples: erythromycin, tetracycline, rifamycin.
  - **RiPPs** (ribosomally synthesised and post-translationally modified peptides). A short precursor peptide is cut and modified. Examples: nisin (a lantibiotic), thiopeptides.
  - Others: terpenes, siderophores, aminoglycosides, β-lactams, and hybrids such as NRPS–PKS.
- **Tailoring enzymes**: oxidases, methyltransferases and glycosyltransferases that decorate the backbone.
- **Transport and self-resistance genes**: the producer must survive its own antibiotic.
- **Regulators**: many BGCs are **silent** under lab conditions.

The genetic architecture partly predicts the chemistry. For example, the order of NRPS modules and their adenylation-domain specificity predicts the peptide sequence. This is the link between gene and product that the project is about.

## 5. Two ways to find BGCs

| | antiSMASH (rule-based) | GECCO (machine learning) |
|---|---|---|
| How | Profile HMMs of core enzymes plus hand-written rules ("KS + AT domain → T1PKS"), then the region is extended around each hit | Conditional Random Field over the protein domains of consecutive genes; learns what "BGC-like" neighbourhoods look like |
| Strength | Very reliable for known classes; detailed analysis (domains, substrate predictions, MIBiG comparison) | Can flag clusters of **unusual architecture** that no rule describes; gives a probability |
| Weakness | Finds nothing that no rule describes | More false positives; less detail |

Running both and comparing them is a simple form of **consensus**. A cluster found by both is well supported. A cluster found only by GECCO deserves a manual look.

## 6. How "novel" is judged

The pipeline uses three lines of evidence. All of them compare against **MIBiG**, the curated database of BGCs whose product has been experimentally characterised (version 4.0, about 3,000 entries).

1. **KnownClusterBlast similarity (antiSMASH).** This is the percentage of the closest MIBiG cluster's genes that have a BLAST hit in your region.
   - ≥ 80 % → `known`: very likely the same or a near-identical compound.
   - 30–79 % → `related`: perhaps an analogue or a cluster that shares sub-pathways.
   - < 30 % or no hit → `novel_candidate`.

   These thresholds are conventions, not laws, so they are configurable. Be careful with small clusters: a 3-gene terpene cluster reaches 100 % easily.
2. **Gene Cluster Families (BiG-SCAPE).** BGCs are networked by domain content, domain order and sequence identity, and grouped into families (GCFs). If a family contains a MIBiG BGC, your cluster resembles a known pathway. A family that contains only your isolates' clusters has no characterised relative.
3. **Self-resistance genes (RGI inside the region).** Producers often carry a resistant copy of the antibiotic's target, or a pump, inside the BGC. A resistance gene inside a cluster is (a) a hint that the product is an antibiotic and (b) a hint at its target. This is the idea behind the ARTS tool.

The **priority score** in `bgc_summary.tsv` adds these up:

| Evidence | Points |
|---|---|
| Novelty: novel / related / known | +3 / +1 / 0 |
| Antibiotic-type class (NRPS, PKS, RiPP) | +2 |
| GECCO agrees | +1 |
| Resistance gene inside the region | +2 |
| Region touches a contig edge (may be incomplete) | −1 |

The score is a **triage aid** that tells you which clusters to open first in antiSMASH. It isn't a prediction of activity. Always inspect the top hits by eye.

## 7. Limits to keep in mind (useful for your Discussion)

- **Silent clusters.** A BGC in the genome may not be what made the zone of inhibition on the plate, and the active compound may come from a cluster the tools didn't detect.
- **Reference bias.** MIBiG covers a small fraction of natural-product diversity. "No similarity" can mean "new". It can also mean "known compound, but its BGC was never deposited".
- **Assembly errors** can split or truncate BGCs, which is why polishing and QC matter.
- **Similarity is not chemistry.** Two clusters at 40 % similarity can make the same compound, and two at 90 % can make different ones because tailoring differs. The gold standard is chemical analysis (LC-MS/MS, molecular networking) linked back to the BGC.
- **Prediction from sequence to activity** is still an open research problem. The "AI component" in your problem statement sits here. Examples: GECCO's type predictions, Walker & Clardy's classifiers that predict antibacterial activity from BGC features, and newer BGC language models (see `references.md`).
