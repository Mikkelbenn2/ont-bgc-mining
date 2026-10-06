# References: cite the tool by its paper

The status column says how each reference was checked when this page was written (October 2026):

- **verified** means the paper page or record was opened.
- **check** means the details are from memory or a search result only. Open the DOI before it goes into the report.

## Tools in the pipeline

| Step | Tool | Reference | Status |
|---|---|---|---|
| Read QC | NanoPlot (NanoPack2) | De Coster W, Rademakers R (2023). NanoPack2: population-scale evaluation of long-read sequencing data. *Bioinformatics* 39(5):btad311. doi:10.1093/bioinformatics/btad311 | verified |
| Read filter | Filtlong | Wick RR. Filtlong. github.com/rrwick/Filtlong (no paper; cite the URL and version) | — |
| Read stats | SeqKit 2 | Shen W et al. (2024). SeqKit2: a Swiss army knife for sequence and alignment processing. *iMeta* 3:e191. doi:10.1002/imt2.191 | check |
| Assembly | Flye | Kolmogorov M, Yuan J, Lin Y, Pevzner PA (2019). Assembly of long, error-prone reads using repeat graphs. *Nat Biotechnol* 37:540–546. doi:10.1038/s41587-019-0072-8 | check |
| Polishing | Medaka / Dorado | Oxford Nanopore Technologies. github.com/nanoporetech/medaka and github.com/nanoporetech/dorado (no papers; cite URL and version) | verified |
| Assembly QC | QUAST | Gurevich A, Saveliev V, Vyahhi N, Tesler G (2013). QUAST: quality assessment tool for genome assemblies. *Bioinformatics* 29(8):1072–1075. doi:10.1093/bioinformatics/btt086 | check |
| Completeness | CheckM2 | Chklovski A, Parks DH, Woodcroft BJ, Tyson GW (2023). CheckM2: a rapid, scalable and accurate tool for assessing microbial genome quality using machine learning. *Nat Methods* 20:1203–1212. doi:10.1038/s41592-023-01940-w | check |
| Annotation | Bakta | Schwengers O et al. (2021). Bakta: rapid and standardized annotation of bacterial genomes via alignment-free sequence identification. *Microb Genom* 7(11):000685. doi:10.1099/mgen.0.000685 | check |
| BGC detection | antiSMASH 8 | Blin K, Shaw S, Vader L, et al. (2025). antiSMASH 8.0: extended gene cluster detection capabilities and analyses of chemistry, enzymology, and regulation. *Nucleic Acids Res* 53(W1):W32–W38. doi:10.1093/nar/gkaf334 | verified |
| Reference BGCs | MIBiG 4.0 | Zdouc MM et al. (2025). MIBiG 4.0: advancing biosynthetic gene cluster curation through global collaboration. *Nucleic Acids Res* 53(D1):D678–D690. doi:10.1093/nar/gkae1115 | title/journal/year verified; check pages + DOI |
| BGC detection (ML) | GECCO | Carroll LM, Larralde M, Fleck JS, et al. (2021). Accurate de novo identification of biosynthetic gene clusters with GECCO. *bioRxiv* doi:10.1101/2021.05.03.442509 (preprint; check whether a journal version exists) | verified |
| Resistance | RGI / CARD | Alcock BP et al. (2023). CARD 2023: expanded curation, support for machine learning, and resistome prediction at the Comprehensive Antibiotic Resistance Database. *Nucleic Acids Res* 51(D1):D690–D699. doi:10.1093/nar/gkac920 | check |
| Taxonomy | GTDB-Tk 2 | Chaumeil PA, Mussig AJ, Hugenholtz P, Parks DH (2022). GTDB-Tk v2: memory friendly classification with the genome taxonomy database. *Bioinformatics* 38(23):5315–5316. doi:10.1093/bioinformatics/btac672 | check |
| BGC families | BiG-SCAPE 2 | BiG-SCAPE 2.0 and BiG-SLiCE 2.0: scalable, accurate and interactive sequence clustering of metabolic gene clusters (2025). *bioRxiv* doi:10.1101/2025.08.20.671210 (preprint) | verified |
| BGC families (original method) | BiG-SCAPE 1 | Navarro-Muñoz JC et al. (2020). A computational framework to explore large-scale biosynthetic diversity. *Nat Chem Biol* 16:60–68. doi:10.1038/s41589-019-0400-9 | check |

## Background and method choices

| Topic | Reference | Status |
|---|---|---|
| Consensus assembly (an upgrade for top isolates) | Wick RR et al. (2025). Autocycler: long-read consensus assembly for bacterial genomes. *Bioinformatics* 41(9):btaf474 | verified |
| Perfect bacterial genomes, including polishing pitfalls | Wick RR, Judd LM, Holt KE (2023). Assembling the perfect bacterial genome using Oxford Nanopore and Illumina sequencing. *PLoS Comput Biol* 19(3):e1010905. doi:10.1371/journal.pcbi.1010905 | check |
| Medaka v2 `--bacteria` and the missing-plasmid pitfall | Wick RR (2024). Medaka v2: progress and potential pitfalls. rrwick.github.io/2024/10/17/medaka-v2.html (blog) | verified |
| Dorado polish `--bacteria` recommendation | Wick RR (2026). Dorado v2.0.0 part 2: assembly polishing. rrwick.github.io/2026/06/19/dorado-v2-polishing.html (blog) | verified |
| Self-resistance genes to prioritise BGCs | Mungan MD et al. (2020). ARTS 2.0: feature updates and expansion of the Antibiotic Resistant Target Seeker for comparative genome mining. *Nucleic Acids Res* 48(W1):W546–W552 | verified |

## For the "AI" part of the report (BGC to activity or product)

| Reference | Status |
|---|---|
| Walker AS, Clardy J (2021). A machine learning bioinformatics method to predict biological activity from biosynthetic gene clusters. *J Chem Inf Model* 61(6):2560–2571. doi:10.1021/acs.jcim.0c01304 | title/journal/DOI verified; check pages |
| Predicting biological activity from biosynthetic gene clusters using neural networks (2024). *bioRxiv* doi:10.1101/2024.06.20.599829 | found in search; read before citing |
| Machine learning inference of natural product chemistry across biosynthetic gene cluster types (2025). *bioRxiv* doi:10.1101/2025.03.13.642868 | found in search; read before citing |
| A foundation model enables prediction of natural product molecular properties, bioactivity, and structural similarity from biosynthetic gene cluster sequence (2026). *bioRxiv* (July 2026) | found in search; very recent, read before citing |

Blogs and preprints are fine for explaining a methods choice. For claims in the Introduction and Discussion, prefer peer-reviewed papers.
