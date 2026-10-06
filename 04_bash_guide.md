# 4. Bash techniques used in this pipeline

The basics (variables, `if`, loops, `case`, functions, redirection, conda environments) are explained line by line in `legacy/run_pipeline_explained.md`, which you wrote for v1. This page covers what is **new in v2**, in the order you meet it in the code.

## Splitting code over several files: `source`

```bash
source "$REPO_DIR/lib/common.sh"
for f in "$REPO_DIR"/steps/*.sh; do source "$f"; done
```

`source FILE` runs a file *inside the current shell*, so the functions and variables it defines become available. Running it with `bash FILE` would execute it in a separate shell and forget everything afterwards. That's how `run_pipeline.sh` stays short: helpers live in `lib/`, and each step lives in `steps/`. The config file is also just bash that gets `source`d, which is why it must be plain `NAME="value"` lines.

## One function per step, and resumable steps

```bash
run_step 03_assembly "$SDIR/03_assembly" step_assembly "$SAMPLE" || return 1
```

`run_step` (in `lib/common.sh`) receives the **name of a function** (`step_assembly`) and calls it with `"$func"`. Before calling it, it checks for a marker file `.done`. If the file exists, the step already succeeded, so it's skipped. After success it writes `.done`. This *marker file* pattern is what makes the pipeline resumable, and it's the same idea that workflow managers like Snakemake and Nextflow are built on.

`|| return 1` means: if this step failed, stop processing *this isolate* (later steps need its output) and let the main loop continue with the next one.

## Variables shared between files

`set_sample_paths` (in `steps/00_paths.sh`) sets `READS_FILT`, `DRAFT`, `ASSEMBLY`, … once per isolate. Every step then uses those names. **Each file name is written in exactly one place**, so renaming a folder can't break one step and not another.

## Running a tool inside its environment

```bash
run_in_env flye flye --nano-hq reads.fastq.gz --out-dir out --threads 16
#          ^env ^the command, exactly as you would type it
```

Inside, this becomes `conda run -p <ENV_DIR>/flye flye ...`, with all output appended to the step's log. `printf '%q '` writes the command into the log with correct quoting, so you can copy it from the log and re-run it by hand.

## Pipes inside an environment: `bash -c '...' _ args`

`conda run` runs *one* program, but some steps need a pipe (`filtlong ... | gzip > file`). The solution is to run a small bash inside the environment:

```bash
run_in_env reads bash -c 'set -o pipefail; out=$1; shift; filtlong "$@" | gzip -c > "$out"' \
  _ "$READS_FILT" --min_length 1000 --keep_percent 95 "$READS_RAW"
```

- The text in **single quotes** is a mini-script. The single quotes stop the *outer* shell from expanding `$1` too early.
- The words after it become the mini-script's `$0` (the `_` placeholder), `$1`, `$2`, …
- `shift` drops `$1` (the output file) so that `"$@"` is exactly the Filtlong options and input.

Passing values as arguments, instead of pasting them into the quoted text, is safe even with spaces in paths.

## Reading a TSV into arrays

```bash
while IFS=$'\t' read -r id reads gsize _rest; do ... done < "$SAMPLES_TSV"
```

`IFS=$'\t'` tells `read` to split each line at **tabs**, and `-r` keeps backslashes literal. Each column lands in its own variable. `${id%$'\r'}` removes a Windows carriage return if the sheet was saved in Excel on Windows, which is a classic cause of mysterious "file not found" errors.

## Arrays for optional arguments

```bash
local args=("--${FLYE_READ_MODE}" "$READS_FILT" --out-dir "$d" --threads "$THREADS")
[[ -n "$GSIZE" ]] && args+=(--genome-size "$GSIZE")
run_in_env flye flye "${args[@]}"
```

You build the argument list step by step and expand it with `"${args[@]}"`, which keeps each element as one argument even when it contains spaces. This is the clean way to add flags only when a setting is filled in.

## Subshell to change folder temporarily

```bash
( cd "$d" && run_in_env rgi rgi main ... )
```

The parentheses run the commands in a copy of the shell, so the `cd` doesn't affect the rest of the script.

## Slurm job arrays

```bash
sbatch --array 1-12 slurm/sample_job.sh "$REPO_DIR" "$CONFIG"
```

Slurm starts 12 copies of the script, and each copy gets its own `$SLURM_ARRAY_TASK_ID` (1…12). `sample_job.sh` uses that number to pick its row from the sample sheet. `--dependency afterany:<id>` makes the cohort job wait until every array task has ended. `exec` at the end of `sample_job.sh` *replaces* the wrapper with `run_pipeline.sh` instead of starting a child process. It's a small tidy-up, so Slurm reports the pipeline's own exit status.

## Strict mode, and why `-e` is left out

`set -uo pipefail` is used, but not `-e`. With `-e`, the first failing command kills the whole script, including the other isolates. Instead, every step's success is checked explicitly (`|| return 1`, `|| warn ...`). `slurm/submit.sh` *does* use `-e`, because there any error should stop everything immediately.

## Self-test

`test/run_tests.sh` checks syntax (`bash -n`), runs a full `--dry-run` on fake samples, and runs the summary script on fake tool outputs. Run it after every edit. Two seconds of testing can save a day of failed cluster jobs.
