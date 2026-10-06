# 3. Setup and running

## 3.1 One-time setup on the server

**Conda.** You need `conda`, `mamba` or `micromamba` on your PATH. On many clusters you get it with `module load miniforge` (or `module avail conda` to see what's offered). If no module exists, install Miniforge in your home folder: download the installer from github.com/conda-forge/miniforge and run `bash Miniforge3-Linux-x86_64.sh`.

**Disk space.** Plan for about 25 GB of environments, about 130 GB of databases (110 GB of it GTDB-Tk), and about 2–5 GB of results per isolate. Home folders on clusters often have small quotas, so point `ENV_DIR`, `DB_DIR` and `OUTDIR` in your config at a project or scratch area. Ask the server admins where that is.

**Order of commands** (run on the **login node**, because compute nodes often have no internet):

```bash
cp config/config.example.sh config/p7.sh && nano config/p7.sh
bin/setup_envs.sh -c config/p7.sh
bin/setup_databases.sh -c config/p7.sh                  # all databases
bin/setup_databases.sh -c config/p7.sh --only antismash # or one at a time
```

Long downloads survive a closed laptop if you run them inside `tmux` or `screen`: start `tmux`, run the command, press `Ctrl-b` then `d` to detach, and run `tmux attach` later.

## 3.2 Running with Slurm

```bash
bin/run_pipeline.sh -c config/p7.sh --dry-run   # always first: check paths and commands
slurm/submit.sh -c config/p7.sh
```

`submit.sh` submits:

1. a **job array** with one task per isolate (task *n* = row *n* of the sample sheet), so all isolates run in parallel, each with `SLURM_SAMPLE_CPUS` and `SLURM_SAMPLE_MEM`;
2. a **cohort job** that starts when the whole array has finished (`--dependency=afterany`). It runs GTDB-Tk, BiG-SCAPE and the summary on all isolates that completed.

Useful Slurm commands:

| Command | What it does |
|---|---|
| `squeue --me` | Your queued and running jobs |
| `sacct -j <jobid> --format=JobID,State,Elapsed,MaxRSS` | How a finished job went, including peak memory |
| `scancel <jobid>` | Cancel a job (or a whole array) |
| `tail -f results/<project>/logs/slurm/sample_<jobid>_1.out` | Watch isolate 1 live |

**Resource guide** for one isolate of about 8 Mb at about 100x, with 16 CPUs: Flye takes about 30–60 min and 16–32 GB, Medaka about 30 min, Bakta about 15 min, antiSMASH (full) about 30–90 min, and the rest is small. `SLURM_SAMPLE_TIME=1-00:00:00` (1 day) leaves a large margin. After a first run, use `sacct` to see real usage and lower the requests, so your jobs start sooner.

## 3.3 Re-running, resuming, changing

| You want to … | Command |
|---|---|
| Continue after a crash or timeout | Submit again. Finished steps are skipped (each leaves a `.done` file) |
| Redo one step for all isolates (for example with new antiSMASH settings) | `--force 07_antismash`. Downstream steps are **not** redone automatically, so also force the steps that use its output, e.g. `--force 07_antismash,11_bigscape` |
| Run only some steps | `--steps 07_antismash,08_gecco` |
| Run one isolate interactively | `bin/run_pipeline.sh -c config/p7.sh --sample TE_isolate01` |
| Add new isolates later | Add rows to the sample sheet and submit again. Old isolates are skipped and the cohort steps rerun with everyone |
| Test without running anything | `--dry-run` |

## 3.4 Troubleshooting

Always look at the **step log** first: `results/<project>/samples/<isolate>/<step>/<step>.log`. The last 30 lines usually say what went wrong (`tail -n 30 <log>`).

| Symptom | Likely cause and fix |
|---|---|
| `No conda, mamba or micromamba found` | Run `module load miniforge` (or similar) first. In Slurm jobs, add it to your `~/.bashrc` or ask how modules work on your cluster |
| Flye fails quickly with low coverage | Too few reads. Check 01_read_qc, lower `FILTLONG_KEEP_PERCENT`, or sequence more |
| Flye: out of memory | Raise `SLURM_SAMPLE_MEM`, or set `FILTLONG_TARGET_BASES` to about 100x genome size |
| Medaka: model not found | Medaka needs internet once to download the model. Run the polish step once on the login node, or use `POLISHER=none` and polish later |
| antiSMASH: `databases not found` | Run `bin/setup_databases.sh --only antismash` and check that `ANTISMASH_DB` in the config is that folder |
| antiSMASH fails on the GenBank file | The step retries automatically with FASTA plus Prodigal. A warning appears in the main log |
| RGI: `localDB` not found | Run `bin/setup_databases.sh --only card` |
| BiG-SCAPE: cannot download MIBiG | Run that step once on the login node (see 02_pipeline_steps, step 11) |
| GTDB-Tk killed | Out of memory: raise `SLURM_COHORT_MEM` (≥ 100G) |
| A sample fails but the others continue | This is intended. Fix the cause and submit again, and only the missing work runs |

## 3.5 Updating tools

Tools improve, and antiSMASH and MIBiG release new versions about once a year. To update one tool, delete its environment folder (`rm -rf <ENV_DIR>/antismash`), run `bin/setup_envs.sh -c config/p7.sh --only antismash`, update its database, and **write the new version in the git commit message**. The versions used in every run are saved in `logs/software_versions.tsv`.
