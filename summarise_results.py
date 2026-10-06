#!/usr/bin/env python3
"""
summarise_results.py — collect the pipeline's results into two tables.

  genome_summary.tsv   one row per isolate: reads, assembly, quality, taxonomy, #BGCs
  bgc_summary.tsv      one row per BGC, ranked by a simple, transparent priority score

Only the Python standard library is used, so it runs with any python3 >= 3.8.
Every input is optional: if a tool was skipped or failed, its columns stay
empty ("NA") instead of the script crashing.

The priority score is a TRIAGE aid to decide which BGCs to look at first, not
a measure of truth. See docs/02_pipeline_steps.md (step 12) for the reasoning.
"""
import argparse
import csv
import glob
import json
import os
import re
import sys
from collections import defaultdict

NA = "NA"
ANTIBIOTIC_CATEGORIES = {"NRPS", "PKS", "RiPP"}   # classes behind most clinical antibiotics


# ----------------------------------------------------------------------------- helpers
def read_tsv(path, comment=None):
    """Return list of dict rows from a tab-separated file with a header line."""
    if not path or not os.path.isfile(path) or os.path.getsize(path) == 0:
        return []
    with open(path, newline="") as fh:
        lines = [l for l in fh if l.strip() and not (comment and l.startswith(comment))]
    return list(csv.DictReader(lines, delimiter="\t"))


def pick(row, *names, default=NA):
    """Get the first column that exists (tools rename columns between versions)."""
    lower = {k.lower().strip(): v for k, v in row.items() if k}
    for n in names:
        v = lower.get(n.lower())
        if v not in (None, ""):
            return v
    return default


def first(pattern):
    hits = sorted(glob.glob(pattern, recursive=True))
    return hits[0] if hits else None


def overlaps(a_start, a_end, b_start, b_end):
    return a_start <= b_end and b_start <= a_end


# ----------------------------------------------------------------------------- per-sample readers
def read_stats(sdir):
    """SeqKit stats before/after Filtlong."""
    rows = read_tsv(os.path.join(sdir, "02_read_filter", "read_stats.tsv"))
    out = {}
    for r in rows:
        tag = "filt" if "filtered" in pick(r, "file") else "raw"
        out[f"reads_{tag}_n"] = pick(r, "num_seqs")
        out[f"bases_{tag}"] = pick(r, "sum_len")
        out[f"read_N50_{tag}"] = pick(r, "N50")
        out[f"mean_Q_{tag}"] = pick(r, "AvgQual")
    return out


def flye_info(sdir):
    """Flye's per-contig table: length, depth, circular?"""
    path = os.path.join(sdir, "03_assembly", "assembly_info.txt")
    contigs = []
    if os.path.isfile(path):
        with open(path) as fh:
            for line in fh:
                if line.startswith("#") or not line.strip():
                    continue
                f = line.rstrip("\n").split("\t")
                contigs.append({"name": f[0], "length": int(f[1]), "cov": float(f[2]),
                                "circular": f[3] == "Y"})
    return contigs


def quast_polished(sdir):
    rows = read_tsv(os.path.join(sdir, "05_assembly_qc", "quast", "report.tsv"))
    vals = {}
    for r in rows:
        metric = r.get("Assembly")
        vals[metric] = r.get("polished", NA)
    return {"total_length": vals.get("Total length", NA),
            "n_contigs": vals.get("# contigs", NA),
            "largest_contig": vals.get("Largest contig", NA),
            "N50": vals.get("N50", NA),
            "GC_percent": vals.get("GC (%)", NA)}


def checkm2(sdir):
    rows = read_tsv(os.path.join(sdir, "05_assembly_qc", "checkm2", "quality_report.tsv"))
    if not rows:
        return {"completeness": NA, "contamination": NA}
    return {"completeness": pick(rows[0], "Completeness"),
            "contamination": pick(rows[0], "Contamination")}


def bakta_cds(sdir, sample):
    path = os.path.join(sdir, "06_annotation", f"{sample}.txt")
    if os.path.isfile(path):
        for line in open(path):
            m = re.match(r"\s*CDSs?:\s*(\d+)", line)
            if m:
                return m.group(1)
    return NA


def antismash_regions(asdir, sample):
    """Regions + best MIBiG hit from antiSMASH's JSON (+ contig-edge flag from region .gbk)."""
    path = os.path.join(asdir, f"{sample}.json")
    if not os.path.isfile(path):
        return None
    data = json.load(open(path))
    # contig_edge is written into each region GenBank file
    edge = {}
    for gbk in glob.glob(os.path.join(asdir, "*.region*.gbk")):
        stem = os.path.basename(gbk)[:-4]
        edge[stem] = '/contig_edge="True"' in open(gbk).read()

    regions = []
    for rec in data.get("records", []):
        rid = rec.get("id", "?")
        rec_len = len(rec.get("seq", {}).get("data", "")) if isinstance(rec.get("seq"), dict) else 0
        kcb = {}
        try:
            for res in rec["modules"]["antismash.modules.clusterblast"]["knowncluster"]["results"]:
                if res.get("ranking"):
                    ref, score = res["ranking"][0]
                    kcb[res["region_number"]] = (ref.get("accession", NA), ref.get("description", NA),
                                                 ref.get("cluster_type", NA), score.get("similarity", NA))
        except (KeyError, TypeError, ValueError):
            pass
        for i, area in enumerate(rec.get("areas", []), start=1):
            protos = area.get("protoclusters", {}).values()
            cats = sorted({p.get("category", "") for p in protos if p.get("category")})
            stem = f"{rid}.region{i:03d}"
            on_edge = edge.get(stem)
            if on_edge is None and rec_len:
                on_edge = area["start"] <= 0 or area["end"] >= rec_len
            hit = kcb.get(i, (NA, NA, NA, NA))
            regions.append({
                "sample": sample, "contig": rid, "region": stem,
                "start": int(area["start"]) + 1, "end": int(area["end"]),
                "length_kb": round((int(area["end"]) - int(area["start"])) / 1000, 1),
                "antismash_type": "+".join(area.get("products", [])),
                "category": "+".join(cats) if cats else NA,
                "contig_edge": "yes" if on_edge else "no",
                "mibig_best_hit": hit[0], "mibig_compound": hit[1],
                "mibig_hit_type": hit[2], "mibig_similarity": hit[3],
            })
    return regions


def gecco_clusters(sdir):
    path = first(os.path.join(sdir, "08_gecco", "*.clusters.tsv"))
    out = []
    for r in read_tsv(path):
        try:
            out.append({"contig": pick(r, "sequence_id"), "id": pick(r, "cluster_id", "bgc_id"),
                        "start": int(pick(r, "start")), "end": int(pick(r, "end")),
                        "type": pick(r, "type"), "p": pick(r, "average_p", "max_p")})
        except ValueError:
            continue
    return out


def rgi_hits(sdir, sample):
    out = []
    for r in read_tsv(os.path.join(sdir, "09_resistance", f"{sample}_rgi.txt")):
        try:
            contig = re.sub(r"_\d+$", "", pick(r, "Contig"))        # RGI appends _<ORF number>
            out.append({"contig": contig, "start": int(pick(r, "Start")), "end": int(pick(r, "Stop")),
                        "gene": pick(r, "Best_Hit_ARO"), "drug": pick(r, "Drug Class")})
        except ValueError:
            continue
    return out


# ----------------------------------------------------------------------------- cohort readers
def gtdbtk(outdir):
    taxa = {}
    for path in glob.glob(os.path.join(outdir, "cohort", "10_taxonomy", "gtdbtk", "*.summary.tsv")):
        for r in read_tsv(path):
            taxa[pick(r, "user_genome")] = {
                "gtdb_classification": pick(r, "classification"),
                "closest_reference": pick(r, "closest_genome_reference", "fastani_reference"),
                "closest_ani": pick(r, "closest_genome_ani", "fastani_ani")}
    return taxa


def bigscape_families(outdir, cutoff):
    """Map 'sample__contig_1.region001' -> family; flag families containing MIBiG BGCs."""
    # file names look like mix_clustering_c0.30.tsv (the number format can vary
    # between versions, so compare the cutoff as a number, not as text)
    files = []
    for path in glob.glob(os.path.join(outdir, "cohort", "11_bigscape", "output", "**",
                                       "*clustering_c*.tsv"), recursive=True):
        m = re.search(r"clustering_c([0-9.]+?)\.tsv$", os.path.basename(path))
        if m and abs(float(m.group(1)) - float(cutoff)) < 1e-6:
            files.append(path)
    fam_of, members = {}, defaultdict(set)
    for path in files:
        for r in read_tsv(path):
            gbk = pick(r, "GBK", "BGC", "Record")
            fam = pick(r, "Family", "GCF", "Clustering")
            if gbk == NA or fam == NA:
                continue
            gbk = os.path.basename(gbk)
            gbk = gbk[:-4] if gbk.endswith(".gbk") else gbk
            key = (os.path.basename(path), fam)
            fam_of.setdefault(gbk, key)
            members[key].add(gbk)
    return fam_of, members, bool(files)


# ----------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outdir", required=True, help="pipeline OUTDIR")
    ap.add_argument("--samples", required=True, help="comma-separated sample ids")
    ap.add_argument("--out", required=True, help="folder for the summary tables")
    ap.add_argument("--bigscape-cutoff", default="0.30")
    ap.add_argument("--known", type=float, default=80)
    ap.add_argument("--related", type=float, default=30)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    samples = [s for s in a.samples.split(",") if s]
    taxa = gtdbtk(a.outdir)
    fam_of, fam_members, have_bigscape = bigscape_families(a.outdir, a.bigscape_cutoff)

    genome_rows, bgc_rows = [], []
    for s in samples:
        sdir = os.path.join(a.outdir, "samples", s)
        asdir = os.path.join(sdir, "07_antismash", "antismash")
        contigs = flye_info(sdir)
        regions = antismash_regions(asdir, s)
        gecco = gecco_clusters(sdir)
        rgi = rgi_hits(sdir, s)

        g = {"sample": s}
        g.update(read_stats(sdir))
        g.update(quast_polished(sdir))
        g["n_circular_contigs"] = sum(c["circular"] for c in contigs) if contigs else NA
        if contigs:
            tot = sum(c["length"] for c in contigs)
            g["mean_depth"] = round(sum(c["cov"] * c["length"] for c in contigs) / tot, 1)
        else:
            g["mean_depth"] = NA
        g.update(checkm2(sdir))
        g["n_CDS"] = bakta_cds(sdir, s)
        g.update(taxa.get(s, {"gtdb_classification": NA, "closest_reference": NA, "closest_ani": NA}))
        g["n_BGC_antismash"] = len(regions) if regions is not None else NA
        g["n_BGC_gecco"] = len(gecco)
        g["n_resistance_genes"] = len(rgi)
        genome_rows.append(g)

        used_gecco = set()
        for reg in regions or []:
            # GECCO support: any GECCO cluster overlapping this region
            g_hits = [c for c in gecco if c["contig"] == reg["contig"]
                      and overlaps(c["start"], c["end"], reg["start"], reg["end"])]
            used_gecco.update(id(c) for c in g_hits)
            r_hits = [h for h in rgi if h["contig"] == reg["contig"]
                      and overlaps(h["start"], h["end"], reg["start"], reg["end"])]

            # BiG-SCAPE family
            key = fam_of.get(f"{s}__{reg['region']}")
            if key:
                mem = fam_members[key]
                mibig = sorted(m for m in mem if m.startswith("BGC"))
                isolates = sorted({m.split("__")[0] for m in mem if "__" in m})
                fam_id, fam_mibig, fam_iso = key[1], ";".join(mibig) or "none", len(isolates)
            else:
                fam_id = fam_mibig = fam_iso = NA if have_bigscape else "not_run"
                mibig = []

            # novelty call from KnownClusterBlast similarity (+ BiG-SCAPE)
            try:
                sim = float(reg["mibig_similarity"])
            except (TypeError, ValueError):
                sim = 0.0                                    # no MIBiG hit at all
            if sim >= a.known:
                novelty = "known"
            elif sim >= a.related or mibig:
                novelty = "related"
            else:
                novelty = "novel_candidate"

            # transparent priority score (see docs)
            score = {"novel_candidate": 3, "related": 1, "known": 0}[novelty]
            if set(reg["category"].split("+")) & ANTIBIOTIC_CATEGORIES:
                score += 2
            if g_hits:
                score += 1
            if r_hits:
                score += 2
            if reg["contig_edge"] == "yes":
                score -= 1

            row = dict(reg)
            row.update({
                "gecco_support": "yes" if g_hits else "no",
                "gecco_type": ";".join(sorted({c["type"] for c in g_hits})) or NA,
                "resistance_genes_in_region": ";".join(h["gene"] for h in r_hits) or "none",
                "bigscape_family": fam_id, "family_mibig_members": fam_mibig,
                "family_n_isolates": fam_iso,
                "novelty": novelty, "priority_score": score,
            })
            bgc_rows.append(row)

        # clusters only GECCO found — possible unconventional BGCs
        for c in gecco:
            if id(c) in used_gecco:
                continue
            bgc_rows.append({
                "sample": s, "contig": c["contig"], "region": f"GECCO:{c['id']}",
                "start": c["start"], "end": c["end"],
                "length_kb": round((c["end"] - c["start"]) / 1000, 1),
                "antismash_type": "not_detected", "category": c["type"], "contig_edge": NA,
                "mibig_best_hit": NA, "mibig_compound": NA, "mibig_hit_type": NA, "mibig_similarity": NA,
                "gecco_support": "only_gecco", "gecco_type": c["type"],
                "resistance_genes_in_region": NA, "bigscape_family": NA, "family_mibig_members": NA,
                "family_n_isolates": NA, "novelty": "gecco_only_check_manually", "priority_score": 1,
            })

    bgc_rows.sort(key=lambda r: (-int(r["priority_score"]), -float(r["length_kb"])))
    for rank, r in enumerate(bgc_rows, start=1):
        r["rank"] = rank

    def write(path, rows):
        if not rows:
            open(path, "w").close()
            return
        cols = list(rows[0].keys())
        for r in rows[1:]:
            cols += [k for k in r if k not in cols]
        with open(path, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=cols, delimiter="\t", restval=NA, extrasaction="ignore")
            w.writeheader()
            w.writerows(rows)

    bgc_cols_first = ["rank", "priority_score", "novelty", "sample", "region"]
    bgc_rows = [{**{k: r[k] for k in bgc_cols_first}, **r} for r in bgc_rows]
    write(os.path.join(a.out, "genome_summary.tsv"), genome_rows)
    write(os.path.join(a.out, "bgc_summary.tsv"), bgc_rows)

    n_novel = sum(r["novelty"] == "novel_candidate" for r in bgc_rows)
    print(f"{len(genome_rows)} genomes, {len(bgc_rows)} BGC rows, {n_novel} novel candidates "
          f"-> {a.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
