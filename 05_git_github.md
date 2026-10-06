# 5. Saving the pipeline with git and GitHub

**git** records every version of your code on your own computer. **GitHub** is a website that stores a copy online, so you can clone it on the server, share it with your group, and reuse it in later projects.

## First time: put this repository on GitHub

The folder is already a git repository with a first commit.

1. Log in at github.com, click **New repository**, name it `ont-bgc-mining`, and choose **Private** (you can make it public later). **Don't** tick "Add a README", because the repository already has one.
2. In a terminal, from inside the `ont-bgc-mining` folder:

   ```bash
   git remote add origin https://github.com/<your-username>/ont-bgc-mining.git
   git branch -M main
   git push -u origin main
   ```

   GitHub asks for a password. Use a **personal access token**, not your account password: GitHub → Settings → Developer settings → Personal access tokens → *Fine-grained*, with "Contents: read and write" for this repository. Alternatively, install the GitHub CLI (`brew install gh`, then `gh auth login`), which handles login for you.
3. On the server:

   ```bash
   git clone https://github.com/<your-username>/ont-bgc-mining.git
   ```

## Everyday workflow

```bash
git status                    # what changed?
git diff                      # the changes, line by line
git add steps/02_assembly.sh  # choose what goes in the next snapshot
git commit -m "Flye: add --asm-coverage option for very deep data"
git push                      # send to GitHub
git pull                      # get changes made elsewhere (e.g. edits on the server)
```

Good commit messages say *what changed and why*, for example "Switch polisher default to dorado (Wick 2026 benchmark)". If you edit on both your laptop and the server, always `git pull` before you start.

## Tag the version you used for the report

```bash
git tag -a v2.0 -m "Version used for P7 report results"
git push --tags
```

In the Methods section you can then write "analysed with ont-bgc-mining v2.0 (github.com/…)". Anyone can reproduce your results with `git checkout v2.0`.

## What never goes into git

Reads, assemblies, results and databases. They're large and often not yours to publish. `.gitignore` already excludes them, and it also excludes your own `config/*.sh` and `config/*.tsv`, because they hold server paths. To version a project's config on purpose, use `git add -f config/p7.sh`.

## Reusing the pipeline in a new project

Clone the repository (or `git pull` the latest version), make a new config and sample sheet, and run. If a new project needs a change (another organism, an extra tool), make a **branch**: `git switch -c fungi-support`. Later you can merge it into `main` if it's generally useful.
