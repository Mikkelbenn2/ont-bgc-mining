# `run_pipeline.sh` explained, line by line

This is a walkthrough of your pipeline script for someone new to both bash (the scripting language) and bioinformatics (what the tools actually do). Line numbers match the script currently in your Scripts folder.

## What the script does, in plain English

You have raw sequencing reads from an Oxford Nanopore sequencer (long, somewhat error-prone DNA reads). The script:

1. Checks the quality of those raw reads (**NanoPlot**).
2. Stitches the reads together into a genome (**Flye** — this is called "assembly").
3. Scans that assembled genome for gene clusters that produce interesting molecules like antibiotics (**antiSMASH**).
4. Scans the same genome for genes that make the organism resistant to antibiotics (**RGI**, using the **CARD** database).

It does this automatically for every sample (every read file) sitting in your `Data` folder, one after another, and writes everything into a `project` folder.

---

## Lines 1–37: the header comment

```bash
#!/usr/bin/env bash
```
This is called a "shebang." It's not a comment to the reader — it tells the operating system which program should execute this file. Here it says "run this file using bash," wherever bash happens to be installed on this computer. This line must be the very first line of the file.

Every other line starting with `#` (lines 2–37) is a plain comment. Bash ignores everything after a `#` on a line. This block is just documentation for a human: what the script does, what folder layout it expects, and what command-line options exist. Comments don't affect how the script runs at all — they're there so future-you (or anyone else) can understand it without reading the code.

---

## Line 38: safety settings

```bash
set -uo pipefail
```
`set` changes bash's own behavior for the rest of the script. Two options are turned on here:
- `-u`: if the script ever tries to use a variable that was never set (e.g. a typo like `$OUTPU_DIR`), bash will error out immediately instead of silently treating it as empty text. This catches typos early.
- `pipefail`: normally, when you chain commands with a pipe (`|`), bash only checks whether the *last* command in the chain succeeded. `pipefail` makes the whole pipeline count as failed if *any* command in it fails. This matters later when we pipe command output through other commands.

(You might notice this isn't the common `set -euo pipefail` with `-e` too. `-e` would kill the whole script the instant any command fails. This script deliberately leaves `-e` off so that one failing sample doesn't stop the other samples — failures are instead caught explicitly, which you'll see further down.)

---

## Lines 40–46: figuring out where things live

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_INPUT_DIR="$BASE_DIR/Data"
DEFAULT_OUTPUT_DIR="$BASE_DIR/project"
```
In bash, `NAME="value"` creates a variable called `NAME` holding `value`. No spaces around the `=` sign — that's a strict bash rule. From then on, `$NAME` (or `${NAME}`) means "substitute the value of that variable here."

`$(...)` is called **command substitution**: bash runs whatever command is inside the parentheses, and replaces `$(...)` with the text that command printed out. So these lines are really three commands chained together, working from the inside out:

1. `dirname "${BASH_SOURCE[0]}"` — `BASH_SOURCE[0]` is a special built-in bash variable that holds the path to the currently-running script file itself (i.e. `run_pipeline.sh`'s own path). `dirname` strips the filename off a path, leaving just the containing folder. So if the script is at `.../Bioinformatics/Scripts/run_pipeline.sh`, this gives `.../Bioinformatics/Scripts`.
2. `cd "..." && pwd` — `cd` changes into that folder, and `pwd` ("print working directory") prints the *full, absolute* path to it. This extra step converts a possibly relative or messy path into a clean absolute one. `&&` means "only run the next command if the previous one succeeded."
3. The whole thing is stored in `SCRIPT_DIR`.

Then `BASE_DIR="$(dirname "$SCRIPT_DIR")"` goes up one more folder level — from `Scripts` to `Bioinformatics`.

Finally, two more variables are built by string concatenation: `$BASE_DIR/Data` and `$BASE_DIR/project`. Putting a variable next to plain text like this just glues the text together — no special operator needed.

**Why bother with all this instead of just typing the path?** Because it means the script figures out "Bioinformatics" is always "wherever Scripts' parent folder is" — so if you ever rename the top folder or copy the whole thing elsewhere, it still works without editing the script.

---

## Lines 48–60: default settings

```bash
THREADS=8
GENOME_SIZE=""
TAXON="bacteria"
SKIP_ENV_SETUP=0
SKIP_DB_SETUP=0
INPUT_DIR="$DEFAULT_INPUT_DIR"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"

NANOPLOT_ENV="np_nanoplot"
FLYE_ENV="np_flye"
ANTISMASH_ENV="np_antismash"
RGI_ENV="np_rgi"
```
Just more variable assignments — these are the script's default settings before it looks at anything you typed on the command line.

- `THREADS=8`: how many CPU cores each tool is allowed to use at once. More threads = faster, up to the number of cores your machine actually has.
- `GENOME_SIZE=""`: an empty string, meaning "not set." Flye can guess the genome size itself, so this is optional.
- `TAXON="bacteria"`: tells antiSMASH what kind of organism it's looking at (its gene-finding rules differ for bacteria vs. fungi).
- `SKIP_ENV_SETUP=0` / `SKIP_DB_SETUP=0`: these act like on/off switches (0 = off/false). They control whether the script tries to (re)install software and databases. They get flipped to `1` if you pass the matching command-line flag.
- `NANOPLOT_ENV`, `FLYE_ENV`, etc.: names for four separate, isolated software installations (see the "conda environments" explanation below). Prefixing them with `np_` just avoids clashing with any other environments you might already have.

---

## Line 62: the help text function

```bash
usage() { sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
```
This defines a **function** named `usage`. A function is a named, reusable block of commands — you define it once, then can "call" it just by writing its name later, like calling a command.

Everything between `{` and `}` is the function's body. Here it's all on one line, with commands separated by `;`.

- `sed -n '2,34p' "$0"` — `$0` is a special variable meaning "the path to this script itself." `sed` is a text-processing tool; `-n '2,34p'` tells it to print only lines 2 through 34 of the file (that's the comment header you read above). So this literally re-reads the script's own source code and prints out its own instructions block.
- `| sed 's/^# \{0,1\}//'` — the `|` (pipe) sends that output into a second `sed` command, which strips the leading `#` (and one optional space after it) from each line, so the help text doesn't show up littered with `#` characters.
- `exit 1` — stops the script immediately with exit code `1` (by convention, `0` means "success," any nonzero number means "something went wrong" — here, "the user asked for help / used it wrong"). This is why calling `usage` always ends the script.

This function only runs when something later in the script calls `usage` — defining it here doesn't print anything yet.

---

## Lines 64–77: reading your command-line options

```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) INPUT_DIR="$2"; shift 2 ;;
    -o) OUTPUT_DIR="$2"; shift 2 ;;
    -t) THREADS="$2"; shift 2 ;;
    -g) GENOME_SIZE="$2"; shift 2 ;;
    --taxon) TAXON="$2"; shift 2 ;;
    --skip-env-setup) SKIP_ENV_SETUP=1; shift ;;
    --skip-db-setup) SKIP_DB_SETUP=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done
```
When you run `./run_pipeline.sh -t 16 --taxon fungi`, bash makes the words after the script name available as **positional parameters**: `$1` is `-t`, `$2` is `16`, `$3` is `--taxon`, `$4` is `fungi`. `$#` is the *count* of how many of these there are.

`while [[ $# -gt 0 ]]; do ... done` is a **loop**: "while there are still leftover arguments, keep doing this." `[[ ... ]]` is bash's test syntax for conditions; `-gt` means "greater than" (for numbers). So in words: "while more than 0 arguments remain."

Inside the loop, `case "$1" in ... esac` is a **switch statement**: look at the current first argument (`$1`) and match it against a list of patterns, running the code for whichever one matches.

- `-i) INPUT_DIR="$2"; shift 2 ;;` — if `$1` is literally `-i`, then take `$2` (the *next* word after it, i.e. the folder path you typed) and store it in `INPUT_DIR`, overwriting the default. Then `shift 2` discards the first two positional parameters, so what used to be `$3` becomes the new `$1` — this is how the loop moves on to the next option instead of looping forever. The `;;` ends this case branch (like `break` in other languages).
- The `-o`, `-t`, `-g`, `--taxon` cases work identically, just filling in different variables.
- `--skip-env-setup) SKIP_ENV_SETUP=1; shift ;;` — this one takes no value after it (it's just a flag/switch), so it only shifts by 1, not 2.
- `-h|--help) usage ;;` — the `|` here means "either of these." If you type `-h` or `--help`, call the `usage` function (which prints help and exits).
- `*) echo "Unknown argument: $1"; usage ;;` — `*` matches *anything else* (a catch-all/default case). If you typed something the script doesn't recognize, print an error and show help.

Net effect: after this loop finishes, `INPUT_DIR`, `OUTPUT_DIR`, `THREADS`, etc. either hold their defaults from earlier, or whatever you overrode them with on the command line.

---

## Lines 79–89: sanity checks and logging setup

```bash
[[ -d "$INPUT_DIR" ]] || { echo "Error: input dir '$INPUT_DIR' not found. Put your fastq files in Bioinformatics/Data, or pass -i."; exit 1; }
```
`[[ -d "$INPUT_DIR" ]]` tests "does this path exist *and* is it a directory?" `||` means "or" in the sense of "if that failed, do this instead." So: "if the input directory does NOT exist, print an error and quit." This stops the script early with a clear message instead of failing confusingly later.

```bash
mkdir -p "$OUTPUT_DIR"/{logs,card_data}
```
`mkdir` makes a directory. `-p` means "also create any missing parent folders, and don't complain if it already exists." The `{logs,card_data}` is **brace expansion** — bash expands this into two separate paths, `$OUTPUT_DIR/logs` and `$OUTPUT_DIR/card_data`, and creates both in one command.

```bash
LOG_DIR="$OUTPUT_DIR/logs"
MAIN_LOG="$LOG_DIR/pipeline.log"
```
More variables, for convenience later.

```bash
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MAIN_LOG"; }
die()  { log "FATAL: $*"; exit 1; }
```
Two more functions.

- `log()`: this is how the whole script prints status messages. `date '+%Y-%m-%d %H:%M:%S'` prints the current date and time in a fixed format (e.g. `2026-09-11 16:01:03`); wrapped in `$(...)`, that gets embedded into the message as a timestamp. `$*` means "all the arguments this function was called with, joined together" — so `log "hello"` prints `hello`, `log "step" "1"` prints `step 1`. `tee -a "$MAIN_LOG"` is a command that copies its input both to the screen *and* appends (`-a`, so it doesn't erase previous content) it to a file — here, the log file. So every `log "..."` call in the script shows up on-screen live *and* gets permanently saved to `pipeline.log`.
- `die()`: calls `log` with a "FATAL:" prefix, then `exit 1` to stop the script. Used whenever something unrecoverable happens.

```bash
log "Input dir:  $INPUT_DIR"
log "Output dir: $OUTPUT_DIR"
```
The first two actual uses of the `log` function — printing which folders it resolved to, so you can immediately confirm it picked up the right paths.

---

## Lines 91–98: finding conda or mamba

```bash
if command -v mamba &>/dev/null; then
  CONDA_BIN=mamba
elif command -v conda &>/dev/null; then
  CONDA_BIN=conda
else
  die "Neither mamba nor conda found on PATH. Install one first."
fi
```
Background: **conda** (and its faster reimplementation, **mamba**) are package managers for scientific/bioinformatics software. They let you install a tool like NanoPlot into its own self-contained "environment" — a private folder with its own copy of Python and dependencies — so different tools' conflicting requirements never clash with each other.

`command -v mamba` checks whether a program called `mamba` exists and is runnable; it prints its path if so, and produces no useful output (and fails) if not. `&>/dev/null` throws away that output, since we only care whether the check succeeded or failed, not what it printed. `/dev/null` is a special "black hole" file — anything written there is simply discarded.

`if ... then ... elif ... then ... else ... fi` is an **if/else chain**: try mamba first (it's faster); if that's not installed, fall back to conda; if neither exists, call `die` with an explanatory error, which prints it and stops the script. `CONDA_BIN` then holds whichever program name was found, so the rest of the script can just say `"$CONDA_BIN"` instead of hardcoding one or the other.

---

## Lines 100–116: helper functions for conda environments

```bash
env_exists() { conda env list | awk '{print $1}' | grep -qx "$1"; }
```
A function that checks "does a conda environment with this name already exist?" `conda env list` prints a table of all environments. `awk '{print $1}'` extracts just the first column (the names) from each line. `grep -qx "$1"` searches for an exact match (`-x`) to the function's first argument, quietly (`-q`, meaning don't print anything, just report success/failure). The whole chain's success or failure (not any printed text) is what this function "returns" — used as a yes/no condition later.

```bash
create_env_if_missing() {
  local env_name=$1 pkg_spec=$2
  if env_exists "$env_name"; then
    log "Env '$env_name' already exists, skipping."
  else
    log "Creating env '$env_name' ($pkg_spec)..."
    "$CONDA_BIN" create -y -n "$env_name" -c bioconda -c conda-forge $pkg_spec \
      >>"$LOG_DIR/env_setup.log" 2>&1 || die "Failed to create env '$env_name' (see $LOG_DIR/env_setup.log)"
  fi
}
```
Another function, taking two arguments (the environment's name, and the package to install into it).

`local env_name=$1 pkg_spec=$2` — `local` means these variables only exist inside this function, and won't leak out or clash with any similarly-named variable elsewhere in the script. `$1`/`$2` here refer to *this function's* arguments (functions get their own private `$1`, `$2`, etc., separate from the script's own).

It calls `env_exists` (the function defined just above) to decide: if the environment already exists, just log that and do nothing more (no point reinstalling). Otherwise:

```bash
"$CONDA_BIN" create -y -n "$env_name" -c bioconda -c conda-forge $pkg_spec
```
This actually creates the environment. `-y` auto-confirms any "are you sure?" prompts. `-n "$env_name"` names it. `-c bioconda -c conda-forge` tells conda which software "channels" (repositories) to pull packages from — `bioconda` is the standard repository for bioinformatics tools, `conda-forge` for general scientific software they depend on.

The `\` at the end of a line is a **line continuation** — it tells bash "this command isn't finished, keep reading it on the next line." It's purely for readability; without it you'd have to cram everything onto one very long line.

`>>"$LOG_DIR/env_setup.log" 2>&1` is **output redirection**. Normally a command's output goes to your screen. `>>` sends it into a file instead — appending, not overwriting. There are two separate output streams a program can produce: "stdout" (normal output, file descriptor `1`) and "stderr" (error messages, file descriptor `2`). `2>&1` says "send stream 2 (errors) to wherever stream 1 (normal output) is currently going" — i.e., merge errors into the same log file too. Net effect: instead of flooding your screen with conda's noisy installation output, it all quietly goes into `env_setup.log`, and you only see the short `log "Creating env..."` message on screen.

`|| die "..."` — if the `create` command fails (nonzero exit code), call `die` with an error message pointing you at the log file to investigate.

```bash
run_in_env() {
  local env_name=$1; shift
  conda run --no-capture-output -n "$env_name" "$@"
}
```
A function used constantly for the rest of the script: it runs a single command *inside* a given conda environment, without you having to manually "activate" and "deactivate" that environment each time.

`local env_name=$1; shift` grabs the first argument as the environment name, then `shift` discards it, so `$@` (meaning "all remaining arguments, each kept separate") is just the actual command and its arguments, e.g. `NanoPlot --fastq reads.fastq ...`.

`conda run -n "$env_name" "$@"` executes that command as if you'd activated `$env_name` first. `--no-capture-output` makes sure the tool's normal live output (progress bars, etc.) still streams through properly instead of being buffered.

---

## Lines 118–127: step 0 — creating the four environments

```bash
if [[ "$SKIP_ENV_SETUP" -eq 0 ]]; then
  log "=== Setting up conda environments ==="
  create_env_if_missing "$NANOPLOT_ENV"   "nanoplot"
  create_env_if_missing "$FLYE_ENV"       "flye"
  create_env_if_missing "$ANTISMASH_ENV"  "antismash"
  create_env_if_missing "$RGI_ENV"        "rgi"
else
  log "Skipping env setup (--skip-env-setup)."
fi
```
`-eq` means "equals" (numeric comparison). This checks the on/off switch from earlier: unless you passed `--skip-env-setup`, call `create_env_if_missing` four times — once per tool — each in its own isolated environment. Since `create_env_if_missing` already skips anything that exists, running this every time is safe and cheap after the first run.

---

## Lines 129–159: step 0b — downloading reference databases (one-time)

Background: antiSMASH and RGI aren't just programs — they need large reference databases to compare your genome against (known biosynthetic gene clusters for antiSMASH, known resistance genes for RGI/**CARD**, the "Comprehensive Antibiotic Resistance Database"). These need to be downloaded once and reused.

```bash
CARD_DIR="$OUTPUT_DIR/card_data"
CARD_MARKER="$CARD_DIR/.card_loaded"
```
Where the CARD database will live, and a "marker" file used purely as a flag — its existence means "we already finished this step," so it's not repeated on every run. A dot-prefixed filename like `.card_loaded` is just a Unix convention for "hidden" files.

```bash
if [[ "$SKIP_DB_SETUP" -eq 0 ]]; then
```
Same pattern as before — only run this block if you didn't pass `--skip-db-setup`.

```bash
  run_in_env "$ANTISMASH_ENV" download-antismash-databases \
    >>"$LOG_DIR/antismash_db.log" 2>&1 || die "antiSMASH database download failed (see $LOG_DIR/antismash_db.log)"
```
Runs antiSMASH's own database-downloading command inside its environment, logging output and dying with a clear error if it fails. (antiSMASH's downloader is already smart enough to skip files it already has, so this is safe to run every time too.)

```bash
  if [[ -f "$CARD_MARKER" ]]; then
    log "CARD database already loaded, skipping."
  else
    log "Downloading and loading CARD database..."
    ( cd "$CARD_DIR" \
      && curl -sSL https://card.mcmaster.ca/latest/data -o card_data.tar.bz2 \
      && tar -xjf card_data.tar.bz2 \
    ) >>"$LOG_DIR/card_setup.log" 2>&1 || die "CARD download/extract failed (see $LOG_DIR/card_setup.log)"

    run_in_env "$RGI_ENV" rgi load --card_json "$CARD_DIR/card.json" \
      >>"$LOG_DIR/card_setup.log" 2>&1 || die "rgi load failed (see $LOG_DIR/card_setup.log)"

    touch "$CARD_MARKER"
    log "CARD database loaded."
  fi
```
`[[ -f "$CARD_MARKER" ]]` checks "does this exact file exist?" (`-f` = "is a regular file," as opposed to `-d` for a directory). If the marker exists, we've already done this — skip. Otherwise:

`( cd "$CARD_DIR" && curl ... && tar ... )` — the parentheses run everything inside in a **subshell**, a temporary "sandboxed" copy of the current shell. Changing directory (`cd`) inside it only affects that subshell, not the rest of the script — a safe way to "temporarily" move somewhere, do some work, and automatically be back in the original folder afterward without an explicit `cd` back.

Inside: `cd` into the CARD folder, then `curl -sSL <url> -o card_data.tar.bz2` downloads the CARD database from its official URL (`-sSL`: silent mode but still show errors, and follow any redirects) saving it as that filename (`-o`). Then `tar -xjf card_data.tar.bz2` extracts (`-x`) that compressed archive (`-j` = it's bzip2-compressed, `-f` = "here's the filename"). Each step is chained with `&&`, so if the download fails, it won't even attempt to extract a broken file.

`run_in_env "$RGI_ENV" rgi load --card_json "$CARD_DIR/card.json"` — tells the `rgi` tool to load and register that database file so it knows to use it for future scans.

`touch "$CARD_MARKER"` creates that empty marker file (or updates its timestamp if it already existed), recording "this step is done" for next time.

---

## Lines 161–167: finding your sample files

```bash
mapfile -t READ_FILES < <(find "$INPUT_DIR" -maxdepth 1 -type f \
  \( -name '*.fastq' -o -name '*.fq' -o -name '*.fastq.gz' -o -name '*.fq.gz' \) | sort)
```
This builds a bash **array** (a list of values) called `READ_FILES`, containing the path to every read file found.

`find "$INPUT_DIR" -maxdepth 1 -type f ...` searches your Data folder for files (`-type f`, as opposed to subfolders) directly inside it only (`-maxdepth 1`, i.e. don't dig into subfolders). The `\( -name '*.fastq' -o -name '*.fq' -o ... \)` part is a grouped "or" condition: match any file whose name ends in `.fastq`, `.fq`, `.fastq.gz`, or `.fq.gz` (`.gz` meaning gzip-compressed — a very common way to store sequencing reads to save disk space). The backslash-parentheses are needed because plain `(` `)` mean something else to bash itself, so they must be "escaped" to be passed through literally to `find`.

`| sort` alphabetically sorts the resulting list of file paths, so samples are always processed in a predictable order.

`mapfile -t READ_FILES < <(...)` reads that output, one line (one filename) per array entry, into `READ_FILES`. `<(...)` is **process substitution** — it lets you feed a command's output into another command as if it were a file. `-t` strips the trailing newline character from each line as it's stored.

```bash
[[ ${#READ_FILES[@]} -eq 0 ]] && die "No .fastq/.fq(.gz) files found in '$INPUT_DIR'."
```
`${#READ_FILES[@]}` is the *length* of the array (how many files were found). `&&` here means "if this condition is true, also run this" (opposite use from `||` earlier). So: if zero files were found, stop with a clear error rather than silently doing nothing.

```bash
log "Found ${#READ_FILES[@]} sample(s) in '$INPUT_DIR'."
```
Just reports how many samples it's about to process.

```bash
FAILED_SAMPLES=()
```
An empty array, which will collect the names of any samples that fail partway through, so a summary can be printed at the very end.

---

## Lines 171–178: turning a filename into a sample name

```bash
sample_name_from_file() {
  local f base
  base=$(basename "$1")
  base="${base%.gz}"
  base="${base%.fastq}"
  base="${base%.fq}"
  echo "$base"
}
```
A function that strips the folder path and file extension off a read file, so e.g. `/path/to/Sample_01.fastq.gz` becomes just `Sample_01`. This name is then used to name that sample's output subfolder and log file.

`basename "$1"` removes the directory part of a path, leaving just the filename, e.g. `Sample_01.fastq.gz`.

`${base%.gz}` is **suffix removal**: "take the value of `base`, and if it ends with `.gz`, strip that off." Doing this three times in a row (`.gz`, then `.fastq`, then `.fq`) handles all four possible extensions (`.fastq`, `.fq`, `.fastq.gz`, `.fq.gz`) — a file not ending in one of these tries just leaves it unchanged for that step.

`echo "$base"` prints the final result. Since functions in bash don't have a distinct dedicated "return a value" mechanism, the standard trick is: the function prints its result, and whoever calls it captures that printed text using `$(...)` (you'll see this used below, e.g. `sample=$(sample_name_from_file "$reads")`).

---

## Lines 180–230: `run_sample` — the actual work for one sample

This is the heart of the script — everything that happens to a single read file. It's defined as a function so it can be reused in a loop for every sample.

```bash
run_sample() {
  local reads=$1 sample outdir slog
  sample=$(sample_name_from_file "$reads")
  outdir="$OUTPUT_DIR/$sample"
  slog="$LOG_DIR/${sample}.log"
  mkdir -p "$outdir"

  log "----- [$sample] Starting -----"
```
Takes one argument — the path to a read file — and works out: the sample's short name (`sample`), its dedicated output folder (`outdir`, e.g. `project/Sample_01`), and its own per-sample log file (`slog`), then creates that output folder and prints a starting banner.

### Step 1: NanoPlot

```bash
  log "[$sample] Step 1/4: NanoPlot QC"
  run_in_env "$NANOPLOT_ENV" NanoPlot \
    --fastq "$reads" \
    --outdir "$outdir/01_nanoplot" \
    --threads "$THREADS" \
    >>"$slog" 2>&1 || { log "[$sample] NanoPlot FAILED"; return 1; }
```
**What NanoPlot does biologically:** it reads your raw sequencing file and produces quality-control plots and statistics — read length distribution, per-read accuracy, total data volume, etc. This is a sanity check *before* you trust the data enough to spend hours assembling a genome from it: if your reads are garbage, you want to know now rather than after Flye grinds away on them.

In bash terms: calls `NanoPlot` inside its conda environment, passing it the reads file (`--fastq`), where to save its charts and reports (`--outdir`), and how many CPU threads to use. Its console output goes to the per-sample log file (same redirection trick as before). `|| { ... }` — if NanoPlot exits with an error, run the block in braces: log a failure message, then `return 1`. `return` (not `exit`) ends just this *function* early, with status `1` (failure), without killing the whole script — this is what lets one bad sample not derail the rest of the batch.

### Step 2: Flye

```bash
  log "[$sample] Step 2/4: Flye assembly"
  local flye_args=(--nano-raw "$reads" --out-dir "$outdir/02_flye" --threads "$THREADS")
  [[ -n "$GENOME_SIZE" ]] && flye_args+=(--genome-size "$GENOME_SIZE")
  run_in_env "$FLYE_ENV" flye "${flye_args[@]}" \
    >>"$slog" 2>&1 || { log "[$sample] Flye FAILED"; return 1; }

  local assembly="$outdir/02_flye/assembly.fasta"
  [[ -s "$assembly" ]] || { log "[$sample] No assembly.fasta produced, aborting sample"; return 1; }
```
**What Flye does biologically:** this is genome **assembly** — taking thousands/millions of short-ish, overlapping, individually error-prone reads and computationally stitching them together into full contiguous DNA sequences ("contigs"), ideally reconstructing entire chromosomes. `--nano-raw` tells Flye these are uncorrected Nanopore reads (as opposed to a different, more accurate Nanopore basecalling mode).

In bash terms: `flye_args` is built as an **array** of arguments rather than one long string, because the optional genome size flag needs to be added conditionally. `[[ -n "$GENOME_SIZE" ]]` checks "is this variable non-empty?" — if you passed `-g` on the command line, `flye_args+=(--genome-size "$GENOME_SIZE")` appends two more elements onto the array (`+=` adds to an existing array/string rather than replacing it). `"${flye_args[@]}"` expands the whole array back out as separate, properly-quoted arguments when Flye is finally called.

After Flye runs, `assembly="$outdir/02_flye/assembly.fasta"` records where Flye's main result file should be (`.fasta` is the standard plain-text format for DNA/protein sequences). `[[ -s "$assembly" ]]` checks "does this file exist *and* is it non-empty?" (`-s`) — a final sanity check that assembly actually produced something usable before moving on, since the two downstream tools need a real genome file to work with.

### Step 3: antiSMASH

```bash
  log "[$sample] Step 3/4: antiSMASH"
  run_in_env "$ANTISMASH_ENV" antismash \
    --cpus "$THREADS" \
    --taxon "$TAXON" \
    --genefinding-tool prodigal \
    --output-dir "$outdir/03_antismash" \
    "$assembly" \
    >>"$slog" 2>&1 || { log "[$sample] antiSMASH FAILED"; return 1; }
```
**What antiSMASH does biologically:** it scans the assembled genome for "biosynthetic gene clusters" (BGCs) — groups of neighboring genes that together produce a specialized molecule, such as an antibiotic, pigment, or toxin. This is a common tool in "genome mining" for discovering natural products. `--genefinding-tool prodigal` tells it to use Prodigal (a standard bacterial gene-prediction tool) to first figure out where the genes even are in the raw DNA sequence, since your assembly is unannotated. `--taxon` (bacteria/fungi) changes which detection rules it applies, since these groups build these molecules differently.

In bash terms: same pattern as the previous steps — run inside its environment, pass the assembly file as the final (unnamed/positional) argument, log output, and bail out of this sample on failure.

### Step 4: RGI / CARD

```bash
  log "[$sample] Step 4/4: RGI (CARD)"
  mkdir -p "$outdir/04_rgi"
  ( cd "$outdir/04_rgi" && run_in_env "$RGI_ENV" rgi main \
      --input_sequence "$assembly" \
      --output_file rgi_output \
      --input_type contig \
      --num_threads "$THREADS" \
      --clean \
      --local ) \
    >>"$slog" 2>&1 || { log "[$sample] RGI FAILED"; return 1; }

  log "----- [$sample] Done -----"
}
```
**What RGI/CARD does biologically:** RGI ("Resistance Gene Identifier") scans the assembled genome against **CARD** (the Comprehensive Antibiotic Resistance Database) to find genes known to confer antibiotic resistance — e.g. genes that pump antibiotics back out of the cell, or that chemically deactivate them. This tells you what this organism is predicted to be resistant to, and why (which gene).

In bash terms: `mkdir -p` makes the output folder first, since `rgi` writes its result files into whatever the *current* directory happens to be, named after `--output_file` (it doesn't have a "save elsewhere" flag for all its outputs). That's why this step wraps the call in `( cd "$outdir/04_rgi" && ... )` — another subshell, so it temporarily "moves into" that specific results folder just for this one command, without affecting where the rest of the script thinks it is afterward. `--input_type contig` tells RGI the input is assembled sequence (as opposed to raw reads). `--local` tells it to use the CARD database copy that was loaded earlier for this project rather than a shared system-wide one. `--clean` removes some temporary intermediate files RGI creates along the way.

Finally, `log "----- [$sample] Done -----"` prints a completion banner — reached only if all four steps succeeded, since any earlier failure already `return`ed out of the function.

---

## Lines 232–245: the main loop and final summary

```bash
for reads in "${READ_FILES[@]}"; do
  if ! run_sample "$reads"; then
    FAILED_SAMPLES+=("$(sample_name_from_file "$reads")")
  fi
done
```
`for reads in "${READ_FILES[@]}"; do ... done` is a **for loop**: for each item in the `READ_FILES` array (one full pass per sample file), assign it to the variable `reads`, and run everything between `do` and `done`. This is where all the sample processing actually kicks off — for every read file found earlier, call the `run_sample` function on it.

`if ! run_sample "$reads"; then ... fi` — `!` negates a condition. `run_sample` returns `1` on failure and (implicitly) `0` on success at its end. So "if NOT successful" means "if it failed." In that case, `FAILED_SAMPLES+=(...)` appends that sample's name onto the tracking array from earlier, so it can be reported at the end. Note this is *outside* `run_sample` — the function itself already logged exactly which step failed and why; this just keeps a short list for the final summary.

```bash
log "=== Pipeline finished ==="
if [[ ${#FAILED_SAMPLES[@]} -gt 0 ]]; then
  log "Failed samples: ${FAILED_SAMPLES[*]} (see per-sample logs in $LOG_DIR)"
  exit 1
else
  log "All samples completed successfully. Results in: $OUTPUT_DIR"
fi
```
After every sample has been attempted, print a final banner. If the failure list has anything in it (length greater than 0), list the failed sample names (`${FAILED_SAMPLES[*]}` joins all array elements into one space-separated string) and exit with status `1` (signalling overall failure — useful if you ever chain this script into something else that checks whether it succeeded). Otherwise, report success and where to find the results.

---

## Bash concepts glossary (quick reference)

- **Variable**: a named piece of storage, e.g. `NAME=value`. Read it back with `$NAME`.
- **Command substitution** `$(command)`: runs a command and replaces itself with that command's printed output.
- **Process substitution** `<(command)`: makes a command's output readable as if it were a file.
- **Array**: a list of values, e.g. `arr=(a b c)`. `${arr[@]}` = all elements, `${#arr[@]}` = count.
- **Function**: a named, reusable block of code, defined with `name() { ... }`, called just by writing `name`.
- **`local`**: keeps a variable private to the function it's declared in.
- **`if`/`elif`/`else`/`fi`**, **`case`/`esac`**, **`while`/`for`... `do`/`done`**: bash's conditional and looping constructs — all end with the keyword spelled backwards-ish (`fi`, `esac`, `done`) instead of a closing brace.
- **`[[ ... ]]`**: bash's test/condition syntax. Common tests: `-d` (is directory), `-f` (is file), `-s` (is non-empty file), `-z`/`-n` (string is empty/non-empty), `-eq`/`-gt` (numeric equals/greater-than).
- **`&&` / `||`**: "and then" / "or else" — run the next command only if the previous one succeeded / failed, respectively.
- **`|` (pipe)**: sends one command's output directly into the next command's input.
- **`>>file 2>&1`**: append all normal output and error output into `file`, instead of printing to the screen.
- **Exit status**: every command finishes with a hidden number; `0` = success, anything else = failure. This is what `&&`, `||`, and `if` all actually check.

## Bioinformatics concepts glossary (quick reference)

- **FASTQ**: a text file format for storing sequencing reads along with a quality score for each base. Often gzip-compressed (`.fastq.gz`) to save space.
- **Nanopore sequencing**: a technology that reads very long strands of DNA directly, at the cost of a higher per-base error rate than some other methods.
- **Read**: one individual sequenced fragment of DNA.
- **Assembly**: computationally reconstructing a full genome by finding overlaps between many reads and merging them into longer continuous sequences.
- **Contig**: one continuous stretch of assembled DNA sequence (short for "contiguous sequence"). A perfect bacterial assembly might be just one contig per chromosome.
- **FASTA**: the standard plain-text format for storing DNA (or protein) sequences, used for assembly output.
- **Gene finding / annotation**: identifying which stretches of a raw DNA sequence are actual genes. Prodigal is a common tool for this in bacteria.
- **Biosynthetic gene cluster (BGC)**: a group of neighboring genes that work together to produce a specialized molecule (antibiotics, pigments, toxins, etc.) — what antiSMASH looks for.
- **CARD**: the Comprehensive Antibiotic Resistance Database, a curated reference of known resistance genes and mutations.
- **conda / mamba**: package managers that install software into isolated "environments," so different bioinformatics tools' conflicting dependencies never interfere with each other.
