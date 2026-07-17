# Exact Run Commands — ISAAC-NG HPC

This file records the exact commands used to run the `mouse_eeev` dataset on
ISAAC-NG after the EEEV reference swap (FL93 → KP282670.1) and the switch from
the `campus` partition (24 h) to the `long` partition (48 h, queueSize 48).

It is meant as a reproducibility aid: copy/paste these on the HPC login node
in order. Lines starting with `#` are comments; lines starting with `$` are
commands to run.

## 0. One-time setup (already done on ISAAC)

Bootstrap a user-managed Nextflow launcher (the cluster default module is too
old for `nf-core/rnaseq 3.23.0`):

```bash
mkdir -p "$HOME/bin"
cd "$HOME/bin"
curl -s https://get.nextflow.io | bash
chmod +x nextflow
```

Clone the wrapper repo on the HPC (only once):

```bash
cd $SCRATCHDIR
git clone https://github.com/aleponce4/rnaseq-nfcore-wrapper-alphavirus.git \
  veeev-nat-hist-nfcore-isaac
cd veeev-nat-hist-nfcore-isaac
```

## 1. Sync the repo with the latest changes

The `long` partition, `48:00:00` time limit, `queueSize = 48`, and the new
`bin/replace_virus_reference.sh` script are all on `origin/main` (commit
`c327e5e` or later). Pull them:

```bash
cd $SCRATCHDIR/<project>
git fetch origin
git reset --hard origin/main
```

> ⚠️ **Critical:** `git reset --hard` on Lustre strips the execute bit from
> scripts. Always run the `chmod +x` step below after any `git pull` or
> `git reset` on the HPC.

## 2. Restore execute permissions on scripts

```bash
chmod +x nextflow submit_rnaseq.sh submit_virus_polish.sh \
  bin/*.sh bin/*.py
```

Verify:

```bash
ls -l bin/build_combined_reference.sh bin/replace_virus_reference.sh
# Both must show -rwxr-xr-x (or similar with the x bit set)
```

## 3. Configure the account

Edit `settings.env` and set the real ISAAC account:

```bash
nano settings.env
# Set: ISAAC_ACCOUNT=ACF-UTKXXXX
```

Or export it for the current shell:

```bash
export ISAAC_ACCOUNT=ACF-UTKXXXX
export SBATCH_ACCOUNT=ACF-UTKXXXX
```

## 4. Replace the EEEV reference (already done — skip if `references/EEEV/virus.fa` already has KP282670.1)

This step downloads KP282670.1 from NCBI and regenerates `virus.fa` +
`virus.gtf`. Only run it if the reference needs to be (re)generated.

```bash
bash bin/replace_virus_reference.sh KP282670.1 references/EEEV
```

Verify the new reference:

```bash
head -1 references/EEEV/virus.fa
# Expected: >KP282670.1 Eastern equine encephalitis virus strain ...

cat references/EEEV/virus.gtf
# Expected: 5 lines, contig KP282670.1, transcripts EEEV_49S / EEEV_26S
```

## 5. Clear any stale combined reference for the dataset

The idempotency patch in `submit_rnaseq.sh` skips the reference build if
`references/build/<dataset>/combined.fa` already exists. After swapping the
virus reference, delete the old combined files so they get rebuilt:

```bash
rm -f references/build/mouse_eeev/combined.fa \
      references/build/mouse_eeev/combined.gtf \
      references/build/mouse_eeev/virus.normalized.gtf
```

## 6. Set up the runtime environment for an interactive preflight

```bash
module purge
module load openjdk/17.0.0_35
export PATH="$HOME/bin:$PATH"
export NXF_VER=25.04.3
export SKIP_MODULE_LOAD=1
```

Verify the runtime:

```bash
which nextflow        # $HOME/bin/nextflow
java -version         # openjdk 17.0.0_35
nextflow -version     # 25.04.3
```

## 7. Preflight check (no Slurm submission)

```bash
PREFLIGHT_ONLY=1 bash submit_rnaseq.sh mouse_eeev
```

This should print the detected runtime, confirm inputs/references, and exit
without launching Nextflow.

## 8. Submit the pipeline

```bash
sbatch --account=ACF-UTKXXXX --export=ALL \
  submit_rnaseq.sh mouse_eeev
```

Expected output:

```
Submitted batch job <JOBID>
```

## 9. Monitor the run

```bash
# Job status
squeue -u $USER

# Detailed job info (shows priority, reason for pending, etc.)
scontrol show job <JOBID>

# Check partition availability (maintenance windows show here)
sinfo -p long

# Tail the manager-job log
tail -f nfcore_rnaseq.<JOBID>.out

# Nextflow work directory and results
# NOTE: The actual RESULTS_BASE/WORK_ROOT paths come from settings.env or
# the environment. Check the launch output for the exact paths, e.g.:
#   Results: $SCRATCHDIR/veeev_nat_hist_nfcore/results/mouse_eeev
#   Work dir: $SCRATCHDIR/veeev_nat_hist_nfcore/work/mouse_eeev
ls -la $SCRATCHDIR/veeev_nat_hist_nfcore/work/mouse_eeev
ls -la $SCRATCHDIR/veeev_nat_hist_nfcore/results/mouse_eeev
```

Cancel if needed:

```bash
scancel <JOBID>
```

### If the job is PENDING with `ReqNodeNotAvail, Reserved for maintenance`

This is a cluster-side maintenance window on the `long` partition. The job
will start automatically once maintenance ends. Check with:

```bash
sinfo -p long
# Look for 'maintenance' or 'down' states in the NODELIST column
```

No need to resubmit — just wait.

## 10. After the run completes

Check the MultiQC report:

```bash
ls $SCRATCHDIR/veeev_nat_hist_nfcore/results/mouse_eeev/multiqc/star_salmon/
```

The Salmon quantification files and STAR BAMs will be under
`star_salmon/` and are the inputs for the downstream variant analysis in
`../variant_analysis/`.

## Key paths on ISAAC-NG

| Item | Path |
| --- | --- |
| Wrapper repo | `$SCRATCHDIR/<project>` |
| Container cache | `$SCRATCHDIR/veeev_nat_hist_nfcore/containers` |
| Nextflow home | `$SCRATCHDIR/veeev_nat_hist_nfcore/.nextflow` |
| Work dir (mouse_eeev) | `$SCRATCHDIR/veeev_nat_hist_nfcore/work/mouse_eeev` |
| Results (mouse_eeev) | `$SCRATCHDIR/veeev_nat_hist_nfcore/results/mouse_eeev` |
| FASTQ inputs | `$SCRATCHDIR/<project>/inputs/<dataset>` |

## Current run configuration (commit c327e5e)

| Setting | Value | File |
| --- | --- | --- |
| Slurm partition | `long` | `submit_rnaseq.sh` (`#SBATCH -p long`) |
| Slurm QoS | `long` | `submit_rnaseq.sh` (`#SBATCH -q long`) |
| Wall time | `48:00:00` | `submit_rnaseq.sh` (`#SBATCH --time=48:00:00`) |
| Manager job CPUs | 4 | `submit_rnaseq.sh` (`--cpus-per-task=4`) |
| Manager job memory | 16G | `submit_rnaseq.sh` (`--mem=16G`) |
| Nextflow queueSize | 48 | `nextflow.config` (line 41) |
| Aligner | `star_salmon` | `submit_rnaseq.sh` |
| nf-core/rnaseq version | `3.23.0` | `submit_rnaseq.sh` |
| Nextflow version | `25.04.3` | `settings.env` |
| Java module | `openjdk/17.0.0_35` | `settings.env` |
| EEEV reference contig | `KP282670.1` (11628 bp) | `references/EEEV/virus.fa` |
| VEEV reference contig | `KP282671.1` | `references/VEEV_INH/virus.fa` |

## Datasets

| Dataset | Samples | Host | Virus | Status |
| --- | --- | --- | --- | --- |
| `mouse_veev` | 46 | mouse | VEEV (KP282671.1) | ✅ completed |
| `mouse_eeev` | 84 | mouse | EEEV (KP282670.1) | 🔄 job <JOBID> PENDING (maintenance) |
| `rat_veev` | 31 | rat | VEEV (KP282671.1) | ⏳ not started |

## Troubleshooting notes

- **`Permission denied` on `bin/build_combined_reference.sh`**: run the
  `chmod +x` step in section 2. This happens after every `git reset --hard`
  or `git pull` on Lustre.
- **Job pending for a long time**: check `sinfo -p long` for maintenance
  windows; the `long` partition allows up to 6 days of wall time but can be
  busy.
- **Old combined reference being reused**: delete
  `references/build/<dataset>/combined.fa` and `combined.gtf` (section 5).
  The idempotency patch intentionally skips the rebuild when those files
  exist.
- **`git pull` conflicts after local edits on HPC**: the cleanest fix is
  `git stash clear; git reset --hard origin/main` followed by `chmod +x`
  (section 2). Any local-only changes will be lost, so re-apply
  `settings.env` account edits afterwards.
