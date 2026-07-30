#!/usr/bin/env bash
# Shell library for submit_rnaseq.sh runtime validation and helper checks.

find_single_matching_file() {
    local search_dir="${1:-}"
    shift
    local patterns=("$@")
    local matches=()
    local pattern
    local found=()
    local f

    for pattern in "${patterns[@]}"; do
        mapfile -t found < <(find "$search_dir" -maxdepth 1 -type f -name "$pattern" | sort)
        for f in "${found[@]}"; do
            if [[ -n "$f" ]]; then
                matches+=("$f")
            fi
        done
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "No matching files found in $search_dir for patterns: ${patterns[*]}" >&2
        return 1
    fi
    if [[ ${#matches[@]} -ne 1 ]]; then
        echo "Expected exactly one matching file in $search_dir, found ${#matches[@]}:" >&2
        printf '  %s\n' "${matches[@]}" >&2
        return 1
    fi
    printf '%s\n' "${matches[0]}"
}

check_fastq_inputs() {
    local fastq_dir="${1:-}"
    local first_r1

    if [[ -z "$fastq_dir" || ! -d "$fastq_dir" ]]; then
        echo "FASTQ input directory not found: $fastq_dir" >&2
        return 1
    fi
    first_r1=$(find "$fastq_dir" -maxdepth 1 \( -type f -o -type l \) -name '*_R1_001.fastq.gz' -print -quit)
    if [[ -z "$first_r1" ]]; then
        echo "No R1 FASTQ files found in: $fastq_dir" >&2
        return 1
    fi
}

check_reference_inputs() {
    local host_dir="${1:-}"
    local virus_dir="${2:-}"
    local dataset="${3:-}"

    if [[ -z "$host_dir" || -z "$virus_dir" || ! -d "$host_dir" || ! -d "$virus_dir" ]]; then
        echo "Expected reference directories are missing for ${dataset:-unknown}" >&2
        echo "Expected: $host_dir and $virus_dir" >&2
        return 1
    fi

    find_single_matching_file "$host_dir" '*.fa' '*.fa.gz' '*.fasta' '*.fasta.gz' '*.fna' '*.fna.gz' >/dev/null || return 1
    find_single_matching_file "$host_dir" '*.gtf' '*.gtf.gz' >/dev/null || return 1
    find_single_matching_file "$virus_dir" '*.fa' '*.fa.gz' '*.fasta' '*.fasta.gz' '*.fna' '*.fna.gz' >/dev/null || return 1
    find_single_matching_file "$virus_dir" '*.gtf' '*.gtf.gz' '*.gff' '*.gff.gz' '*.gff3' '*.gff3.gz' >/dev/null || return 1
}

ensure_module_command() {
    if command -v module >/dev/null 2>&1; then
        return 0
    fi
    if [[ -f /etc/profile.d/modules.sh ]]; then
        # shellcheck disable=SC1091
        source /etc/profile.d/modules.sh
    elif [[ -f /etc/profile.d/lmod.sh ]]; then
        # shellcheck disable=SC1091
        source /etc/profile.d/lmod.sh
    fi
    command -v module >/dev/null 2>&1
}

prepend_nextflow_bin_dir() {
    local nextflow_bin_dir="${1:-}"
    if [[ -n "$nextflow_bin_dir" && -x "$nextflow_bin_dir/nextflow" ]]; then
        export PATH="$nextflow_bin_dir:$PATH"
    fi
}

nextflow_version_ge() {
    local current="${1:-0}"
    local minimum="${2:-0}"
    local current_major current_minor current_patch
    local minimum_major minimum_minor minimum_patch

    IFS=. read -r current_major current_minor current_patch <<<"$current"
    IFS=. read -r minimum_major minimum_minor minimum_patch <<<"$minimum"

    current_patch=${current_patch:-0}
    minimum_patch=${minimum_patch:-0}

    if (( current_major > minimum_major )); then
        return 0
    fi
    if (( current_major < minimum_major )); then
        return 1
    fi
    if (( current_minor > minimum_minor )); then
        return 0
    fi
    if (( current_minor < minimum_minor )); then
        return 1
    fi
    (( current_patch >= minimum_patch ))
}

java_version_ge() {
    local current="${1:-0}"
    local minimum="${2:-0}"
    local current_major minimum_major

    current_major=${current%%.*}
    minimum_major=${minimum%%.*}
    (( current_major >= minimum_major ))
}

check_java_version() {
    local required_minimum="17"
    local detected_version

    if ! command -v java >/dev/null 2>&1; then
        echo "java is not on PATH after runtime setup" >&2
        return 1
    fi

    detected_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2; exit}')
    if [[ -z "$detected_version" ]]; then
        echo "Could not determine Java version from 'java -version'" >&2
        return 1
    fi

    if [[ "$detected_version" == 1.* ]]; then
        detected_version=${detected_version#1.}
    fi

    if ! java_version_ge "$detected_version" "$required_minimum"; then
        echo "Java $detected_version is too old for Nextflow ${NXF_VER:-}; need >= $required_minimum" >&2
        return 1
    fi
}

check_nextflow_version() {
    local required_minimum="25.04.3"
    local detected_version

    if ! command -v nextflow >/dev/null 2>&1; then
        echo "nextflow is not on PATH after module loading" >&2
        return 1
    fi

    detected_version=$(nextflow -version 2>/dev/null | awk '/version/ {print $NF; exit}')
    detected_version=${detected_version#v}

    if [[ -z "$detected_version" ]]; then
        echo "Could not determine Nextflow version from 'nextflow -version'" >&2
        return 1
    fi

    if ! nextflow_version_ge "$detected_version" "$required_minimum"; then
        echo "Nextflow $detected_version is too old for nf-core/rnaseq 3.23.0; need >= $required_minimum" >&2
        return 1
    fi
}

print_runtime_summary() {
    printf 'Runtime nextflow: %s\n' "$(command -v nextflow 2>/dev/null || echo 'not found')"
    printf 'Runtime java: %s\n' "$(command -v java 2>/dev/null || echo 'not found')"
    if command -v nextflow >/dev/null 2>&1; then
        nextflow -version | awk 'NR<=4 {print}'
    fi
    if command -v java >/dev/null 2>&1; then
        java -version 2>&1 | awk 'NR==1 {print}'
    fi
}
