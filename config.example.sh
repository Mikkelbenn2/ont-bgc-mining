# =============================================================================
# config.example.sh — settings for one run of the ONT BGC-mining pipeline
#
# HOW TO USE
#   cp config/config.example.sh config/my_project.sh
#   nano config/my_project.sh            # edit paths below
#   bin/run_pipeline.sh -c config/my_project.sh --dry-run
#
# This file is plain bash: it is "sourced" by the pipeline, so every line is
# just VARIABLE="value" (no spaces around "="). Lines starting with # are notes.
# Keep one config file per project so you can always see how a run was made.
# =============================================================================

# ---------- Project ----------------------------------------------------------
PROJECT_NAME="tiny_earth_P7"

# Sample sheet: tab-separated, one isolate per line (see config/samples.example.tsv)
SAMPLES_TSV="config/samples.tsv"

# Where results go (created if missing). Put this on storage with lots of space.
OUTDIR="results/${PROJECT_NAME}"

# ---------- Compute ----------------------------------------------------------
# Threads per tool. Inside a Slurm job this is overridden by $SLURM_CPUS_PER_TASK.
THREADS=16

# ---------- Software environments -------------------------------------------
# One conda environment per tool is created here by bin/setup_envs.sh.
# On a shared server, home directories often have small quotas: point this at
# a project/scratch area instead.
ENV_DIR="${HOME}/conda_envs/ont-bgc-mining"

# ---------- Databases (downloaded once by bin/setup_databases.sh) ------------
DB_DIR="${HOME}/databases/ont-bgc-mining"
ANTISMASH_DB="${DB_DIR}/antismash"
BAKTA_DB="${DB_DIR}/bakta/db-light"     # db-light (~1.5 GB) or db (full, ~40 GB)
BAKTA_DB_TYPE="light"                   # light | full  (used by setup_databases.sh)
CHECKM2_DB_DIR="${DB_DIR}/checkm2"
CARD_DIR="${DB_DIR}/card"
GTDBTK_DB="${DB_DIR}/gtdbtk"            # ~110 GB unpacked; set RUN_GTDBTK=0 to skip
# BiG-SCAPE needs Pfam-A.hmm. Leave empty to reuse the copy antiSMASH downloads.
PFAM_HMM=""

# ---------- Reads & read filtering --------------------------------------------
# Basecalling quality decides how Flye treats the reads:
#   nano-hq  = R10.4.1 + Dorado hac/sup (or Guppy5+ sup), roughly Q15-Q20+  <- typical today
#   nano-raw = older R9.4.1 / fast basecalling
FLYE_READ_MODE="nano-hq"

# Filtlong: drop short reads and the worst-quality tail.
FILTLONG_MIN_LEN=1000          # bp; reads shorter than this rarely help assembly
FILTLONG_KEEP_PERCENT=95       # keep the best 95 % of bases
# Optional cap on total bases kept (e.g. 100x coverage of a 8 Mb genome = 800000000).
# Very deep coverage (>150x) slows Flye and gives no benefit. Empty = no cap.
FILTLONG_TARGET_BASES=""

# ---------- Assembly ---------------------------------------------------------
# Expected genome size (e.g. 8m for Streptomyces, 5m for Pseudomonas, 4m for Bacillus).
# Optional. Per-sample values in the sample sheet take priority over this.
GENOME_SIZE=""
FLYE_EXTRA_ARGS=""             # e.g. "--asm-coverage 100" with very deep data

# ---------- Polishing --------------------------------------------------------
#   medaka = medaka_consensus --bacteria (bioconda; works with any FASTQ)
#   dorado = dorado polish --bacteria (ONT's newer polisher; needs the dorado binary
#            and FASTQ that still carry Dorado's header tags)
#   none   = skip polishing (Flye already does one round internally)
POLISHER="medaka"
DORADO_BIN="dorado"            # path to the dorado executable, if POLISHER=dorado

# ---------- Optional / cohort steps ------------------------------------------
RUN_GTDBTK=1                   # genome taxonomy (needs ~64-100 GB RAM and the DB)
RUN_GECCO=1                    # machine-learning BGC detection (second opinion)
RUN_RGI=1                      # antibiotic resistance genes (CARD)
RUN_BIGSCAPE=1                 # gene-cluster families + MIBiG comparison

# ---------- antiSMASH --------------------------------------------------------
# Extra comparison/analysis modules. --cb-general (compare to the whole antiSMASH
# database) is informative but slow, so it is off by default.
ANTISMASH_EXTRA_ARGS="--cb-knownclusters --cb-subclusters --cc-mibig --asf --rre --tfbs --pfam2go --clusterhmmer --tigrfam --smcog-trees"

# ---------- BiG-SCAPE --------------------------------------------------------
BIGSCAPE_MIBIG_VERSION="4.0"   # include MIBiG reference BGCs in the network
BIGSCAPE_CUTOFF="0.30"         # distance cutoff that defines a gene-cluster family

# ---------- Novelty thresholds used in the summary table ---------------------
# KnownClusterBlast similarity (% of reference genes with a hit) to the closest MIBiG BGC
KNOWN_SIMILARITY=80            # >= this -> "known"
RELATED_SIMILARITY=30          # between the two -> "related"; below -> "novel_candidate"

# ---------- Slurm (used by slurm/submit.sh) -----------------------------------
SLURM_PARTITION=""             # leave empty to use the cluster default
SLURM_ACCOUNT=""
SLURM_SAMPLE_CPUS=16
SLURM_SAMPLE_MEM="64G"
SLURM_SAMPLE_TIME="1-00:00:00"
SLURM_COHORT_CPUS=32
SLURM_COHORT_MEM="128G"        # GTDB-Tk is the memory-hungry step
SLURM_COHORT_TIME="1-00:00:00"
