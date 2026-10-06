#!/usr/bin/env python3
"""Create a tiny fake results folder (2 isolates) to test summarise_results.py
without running any real tool. File formats imitate the real tools' outputs."""
import json
import os
import sys

out = sys.argv[1]


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


for s, n_regions in [("isoA", 2), ("isoB", 1)]:
    d = f"{out}/samples/{s}"
    w(f"{d}/02_read_filter/read_stats.tsv",
      "file\tformat\ttype\tnum_seqs\tsum_len\tN50\tAvgQual\n"
      f"{d}/00_reads/{s}.fastq.gz\tFASTQ\tDNA\t90000\t900000000\t12000\t17.1\n"
      f"{d}/02_read_filter/{s}.filtered.fastq.gz\tFASTQ\tDNA\t70000\t850000000\t14000\t18.0\n")
    w(f"{d}/03_assembly/assembly_info.txt",
      "#seq_name\tlength\tcov.\tcirc.\trepeat\tmult.\talt_group\tgraph_path\n"
      "contig_1\t8000000\t95\tN\tN\t1\t*\t1\n"
      "contig_2\t50000\t180\tY\tN\t2\t*\t2\n")
    w(f"{d}/05_assembly_qc/quast/report.tsv",
      "Assembly\tdraft\tpolished\n# contigs\t2\t2\nLargest contig\t8000000\t8000010\n"
      "Total length\t8050000\t8050012\nGC (%)\t72.1\t72.1\nN50\t8000000\t8000010\n")
    w(f"{d}/05_assembly_qc/checkm2/quality_report.tsv",
      "Name\tCompleteness\tContamination\n" f"{s}\t99.5\t0.8\n")
    w(f"{d}/06_annotation/{s}.txt", "Annotation:\ntRNAs: 70\nCDSs: 7100\n")

    asd = f"{d}/07_antismash/antismash"
    areas, kcb = [], []
    for i in range(1, n_regions + 1):
        start, end = 100000 * i, 100000 * i + 45000
        cat = "NRPS" if i == 1 else "terpene"
        areas.append({"start": start, "end": end, "products": [cat if cat != "NRPS" else "NRPS"],
                      "protoclusters": {"0": {"category": cat, "product": cat}}})
        if i == 2:   # second region resembles a known terpene
            kcb.append({"region_number": i, "total_hits": 1, "prefix": "",
                        "ranking": [[{"accession": "BGC0000661", "description": "geosmin",
                                      "cluster_type": "terpene"}, {"similarity": 100}]]})
        w(f"{asd}/contig_1.region{i:03d}.gbk",
          f'LOCUS contig_1\n     region  1..45000\n                     /contig_edge="False"\n')
    rec = {"id": "contig_1", "seq": {"data": "A" * 10}, "areas": areas,
           "modules": {"antismash.modules.clusterblast": {"knowncluster": {"results": kcb}}}}
    w(f"{asd}/{s}.json", json.dumps({"records": [rec]}))

    w(f"{d}/08_gecco/{s}.clusters.tsv",
      "sequence_id\tcluster_id\tstart\tend\taverage_p\tmax_p\ttype\n"
      f"contig_1\tcontig_1_cluster_1\t101000\t140000\t0.9\t0.99\tNRP\n"
      f"contig_1\tcontig_1_cluster_2\t700000\t720000\t0.7\t0.9\tUnknown\n")
    w(f"{d}/09_resistance/{s}_rgi.txt",
      "ORF_ID\tContig\tStart\tStop\tBest_Hit_ARO\tDrug Class\n"
      "contig_1_88 x\tcontig_1_88\t120000\t121500\tvanH\tglycopeptide antibiotic\n")

w(f"{out}/cohort/10_taxonomy/gtdbtk/gtdbtk.bac120.summary.tsv",
  "user_genome\tclassification\tclosest_genome_reference\tclosest_genome_ani\n"
  "isoA\td__Bacteria;p__Actinomycetota;g__Streptomyces;s__\tGCF_000001\t91.2\n"
  "isoB\td__Bacteria;p__Actinomycetota;g__Streptomyces;s__Streptomyces griseus\tGCF_000002\t98.9\n")
w(f"{out}/cohort/11_bigscape/output/output_files/run/mix/mix_clustering_c0.30.tsv",
  "GBK\tRecord_Type\tRecord_Number\tCC\tFamily\n"
  "isoA__contig_1.region001\tregion\t1\t1\tFAM_1\n"
  "isoB__contig_1.region001\tregion\t1\t1\tFAM_1\n"
  "isoA__contig_1.region002\tregion\t1\t2\tFAM_2\n"
  "BGC0000661.5\tregion\t1\t2\tFAM_2\n")
print(out)
