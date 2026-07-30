#!/usr/bin/env bash
#SBATCH -J nfcore_rnaseq
#SBATCH -p campus
#SBATCH -q campus
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=24:00:00
#SBATCH -o %x.%j.out

set -euo pipefail

# Main places to edit settings:
# 1. The #SBATCH lines above control the manager job submitted by sbatch.
# 2. settings.env controls the reusable runtime settings used below.
# 3. CONTAINER_MODULE can be left empty if ISAAC already provides singularity on PATH.
#
# Common HPC terminal commands:
#   cd /path/to/veeev_nat_hist_nfcore
#   nano settings.env
#   module avail openjdk
#   python3 bin/stage_nat_hist_inputs.py "/path/to/V-EEEV Nat Hist"
#   bash bin/precache_nfcore_containers.sh
#   module purge
#   module load openjdk/17.0.0_35
#   export PATH="$HOME/bin:$PATH"
#   export NXF_VER=25.04.3
#   export SKIP_MODULE_LOAD=1
#   PREFLIGHT_ONLY=1 bash submit_rnaseq.sh mouse_veev
#   SMOKE_TEST=1 PREFLIGHT_ONLY=1 bash submit_rnaseq.sh mouse_veev
#   export ISAAC_ACCOUNT="ACF-UTKXXXX"
#   export SBATCH_ACCOUNT="$ISAAC_ACCOUNT"
#   DRY_RUN=1 SKIP_MODULE_LOAD=1 bash submit_rnaseq.sh mouse_veev
#   sbatch submit_rnaseq.sh mouse_veev
#   sbatch submit_rnaseq.sh mouse_eeev
#   sbatch submit_rnaseq.sh rat_veev
#   squeue -u <netid>

usage() {
    cat <<'EOF'
Usage:
  sbatch submit_rnaseq.sh <mouse_veev|mouse_eeev|rat_veev>

Primary settings:
  edit settings.env

Required final value:
  ISAAC_ACCOUNT must be changed from the template account

Quick HPC commands:
  cd /path/to/veeev_nat_hist_nfcore
  nano settings.env
  python3 bin/stage_nat_hist_inputs.py "/path/to/V-EEEV Nat Hist"
  module purge
  module load openjdk/17.0.0_35
  export PATH="$HOME/bin:$PATH"
  export NXF_VER=25.04.3
  export SKIP_MODULE_LOAD=1
  PREFLIGHT_ONLY=1 bash submit_rnaseq.sh mouse_veev
  SMOKE_TEST=1 PREFLIGHT_ONLY=1 bash submit_rnaseq.sh mouse_veev
  export ISAAC_ACCOUNT="ACF-UTKXXXX"
  export SBATCH_ACCOUNT="$ISAAC_ACCOUNT"
  sbatch submit_rnaseq.sh mouse_veev
EOF
}

if [[ $# -ne 1 ]]; then
    usage >&2
    exit 1
fi

# Step 1: identify which dataset to run.
dataset=$1
case "$dataset" in
    mouse_veev|mouse_eeev|rat_veev) ;;
    *)
        echo "Dataset must be one of: mouse_veev, mouse_eeev, rat_veev. Got: $dataset" >&2
        exit 1
        ;;
esac

if [[ -n "${SLURM_SUBMIT_DIR:-}" && -f "${SLURM_SUBMIT_DIR}/settings.env" ]]; then
    script_dir=$(cd "$SLURM_SUBMIT_DIR" && pwd)
else
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
settings_file="$script_dir/settings.env"
preflight_only=${PREFLIGHT_ONLY:-0}
smoke_test=${SMOKE_TEST:-0}

# Step 2: load the central runtime settings, if present.
if [[ -f "$settings_file" ]]; then
    # shellcheck disable=SC1091
    source "$settings_file"
fi

# Step 3: define the dataset-specific inputs, references, and output targets.
source_fastq_dir="$script_dir/inputs/$dataset"
fastq_dir="$source_fastq_dir"
samplesheet="$script_dir/metadata/${dataset}_samplesheet.csv"
reference_builder="$script_dir/bin/build_combined_reference.sh"
samplesheet_builder="$script_dir/bin/make_samplesheet.sh"
smoke_input_builder="$script_dir/bin/prepare_smoke_inputs.py"
smoke_manifest="$script_dir/metadata/smoke_samples.tsv"
case "$dataset" in
    mouse_veev)
        host_ref="mouse"
        virus_ref="${MOUSE_VEEV_VIRUS_REF:-VEEV}"
        ;;
    mouse_eeev)
        host_ref="mouse"
        virus_ref="${MOUSE_EEEV_VIRUS_REF:-EEEV}"
        ;;
    rat_veev)
        host_ref="rat"
        virus_ref="${RAT_VEEV_VIRUS_REF:-VEEV}"
        ;;
esac
combined_fasta="$script_dir/references/build/$dataset/combined.fa"
combined_gtf="$script_dir/references/build/$dataset/combined.gtf"
host_dir="$script_dir/references/$host_ref"
virus_dir="$script_dir/references/$virus_ref"

nextflow_module=${NEXTFLOW_MODULE:-}
java_module=${JAVA_MODULE:-}
nextflow_bin_dir=${NEXTFLOW_BIN_DIR:-}
container_module=${CONTAINER_MODULE:-}
nfcore_profile=${NFCORE_PROFILE:-}
results_base=${RESULTS_BASE:-}
work_root=${WORK_ROOT:-}
results_base_smoke=${RESULTS_BASE_SMOKE:-}
work_root_smoke=${WORK_ROOT_SMOKE:-}
container_cache=${CONTAINER_CACHE:-}

if [[ "$smoke_test" == "1" ]]; then
    fastq_dir="$script_dir/inputs/smoke/$dataset"
    samplesheet="$script_dir/metadata/smoke/${dataset}_samplesheet.csv"
    results_base="$results_base_smoke"
    work_root="$work_root_smoke"
fi

work_dir="$work_root/$dataset"
outdir="$results_base/$dataset"

lib_file="$script_dir/bin/lib_rnaseq.sh"
if [[ -f "$lib_file" ]]; then
    # shellcheck disable=SC1091
    source "$lib_file"
else
    echo "Required runtime library missing: $lib_file" >&2
    exit 1
fi

# Step 4: run lightweight preflight checks that can be used before sbatch.
if [[ "$smoke_test" == "1" ]]; then
    smoke_builder_args=(
        python3 "$smoke_input_builder"
        "$dataset"
        "$source_fastq_dir"
        "$fastq_dir"
        --config "$smoke_manifest"
    )
    if [[ -n "${SMOKE_READ_PAIRS:-}" ]]; then
        smoke_builder_args+=(--read-pairs "$SMOKE_READ_PAIRS")
    fi
    if [[ "${SMOKE_REGENERATE:-0}" == "1" ]]; then
        smoke_builder_args+=(--force)
    fi
    "${smoke_builder_args[@]}"
fi

check_fastq_inputs "$fastq_dir" || exit 1
check_reference_inputs "$host_dir" "$virus_dir" "$dataset" || exit 1

if [[ "$preflight_only" == "1" ]]; then
    printf 'Preflight checks passed for %s\n' "$dataset"
    if [[ "$smoke_test" == "1" ]]; then
        printf 'Mode: smoke\n'
    fi
    printf 'FASTQs: %s\n' "$fastq_dir"
    printf 'Host reference dir:  %s (%s)\n' "$host_dir" "$host_ref"
    printf 'Virus reference dir: %s (%s)\n' "$virus_dir" "$virus_ref"
    exit 0
fi

# Step 5: validate the cluster environment needed for a real run.
if [[ -z "${ISAAC_ACCOUNT:-}" ]]; then
    echo "ISAAC_ACCOUNT is required" >&2
    exit 1
fi

if [[ "${ISAAC_ACCOUNT}" == "ACF-UTKXXXX" ]]; then
    echo "ISAAC_ACCOUNT is still set to the template value in settings.env" >&2
    exit 1
fi

if [[ -z "${SCRATCHDIR:-}" ]]; then
    echo "SCRATCHDIR is required on ISAAC-NG" >&2
    exit 1
fi

if [[ -z "$results_base" || -z "$work_root" || -z "$container_cache" ]]; then
    echo "Scratch-backed runtime paths are empty; confirm SCRATCHDIR is exported before launch" >&2
    exit 1
fi

export NXF_HOME=${NXF_HOME:-$SCRATCHDIR/veeev_nat_hist_nfcore/.nextflow}
export NXF_SINGULARITY_CACHEDIR=${NXF_SINGULARITY_CACHEDIR:-$container_cache}
export NXF_APPTAINER_CACHEDIR=${NXF_APPTAINER_CACHEDIR:-$container_cache}

# Step 6: create the directories Nextflow and the helper scripts will write to.
mkdir -p "$results_base" "$work_dir" "$container_cache" "$script_dir/metadata"

# Step 7: load Nextflow and the container runtime unless the environment already has them.
if [[ "${SKIP_MODULE_LOAD:-0}" != "1" ]]; then
    if ensure_module_command; then
        module purge
        if [[ -n "$java_module" ]]; then
            module load "$java_module"
        fi
        if [[ -n "$nextflow_module" ]]; then
            module load "$nextflow_module"
        fi
        if [[ -n "$container_module" ]]; then
            module load "$container_module"
        fi
    else
        echo "Environment module command not found; set SKIP_MODULE_LOAD=1 only if Nextflow is already on PATH" >&2
        exit 1
    fi
fi

# Step 7b: prefer a user-managed Nextflow launcher when configured.
prepend_nextflow_bin_dir "$nextflow_bin_dir"

# Step 7c: fail early if the loaded Java/Nextflow runtime is not usable.
if [[ "${SKIP_RUNTIME_CHECK:-0}" != "1" ]]; then
    check_java_version
    check_nextflow_version
    print_runtime_summary
fi

# Step 8: build the combined reference and generate the nf-core samplesheet.
"$reference_builder" "$dataset"
"$samplesheet_builder" "$fastq_dir" "$samplesheet"

# Step 9: assemble the nf-core/rnaseq command with dataset-specific paths.
cmd=(
    nextflow run nf-core/rnaseq
    -r 3.23.0
    -profile "$nfcore_profile"
    -c "$script_dir/nextflow.config"
    -work-dir "$work_dir"
    --input "$samplesheet"
    --fasta "$combined_fasta"
    --gtf "$combined_gtf"
    --aligner star_salmon
    --outdir "$outdir"
    -resume
)

# Optional debugging mode to print the exact Nextflow command and stop.
if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'DRY_RUN nextflow command:\n'
    printf '%q ' "${cmd[@]}"
    printf '\n'
    exit 0
fi

# Step 10: launch the actual pipeline on the allocated compute node.
printf 'Launching nf-core/rnaseq for %s\n' "$dataset"
if [[ "$smoke_test" == "1" ]]; then
    printf 'Mode: smoke\n'
fi
printf 'Results: %s\n' "$outdir"
printf 'Work dir: %s\n' "$work_dir"
printf 'Settings file: %s\n' "$settings_file"

"${cmd[@]}"
