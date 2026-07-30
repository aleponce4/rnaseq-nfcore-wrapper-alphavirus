#!/usr/bin/env bash
# replace_virus_reference.sh
# Downloads a virus reference (FASTA + GenBank) from NCBI and generates a
# matching GTF with CDS coordinates for nsP1234 and structural polyprotein.
#
# Usage:
#   bash bin/replace_virus_reference.sh <accession> <reference_dir>
#
# Example:
#   bash bin/replace_virus_reference.sh KP282670.1 references/EEEV
#
# After running:
#   1. Delete the old combined reference so build_combined_reference.sh
#      picks up the new virus.fa:
#        rm -f references/build/<dataset>/combined.fa references/build/<dataset>/combined.gtf
#   2. Discard old results (the contig name changed):
#        rm -rf $RESULTS_BASE/../work/<dataset>
#   3. Re-run: sbatch submit_rnaseq.sh <dataset>

set -euo pipefail

ACCESSION="${1:?Usage: $0 <accession> <reference_dir>}"
REF_DIR="${2:?Usage: $0 <accession> <reference_dir>}"

EUTILS="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"

echo "=== Downloading $ACCESSION from NCBI ==="

# Backup existing reference if present
if [[ -f "$REF_DIR/virus.fa" ]]; then
    BACKUP="${REF_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    echo "Backing up existing reference to $BACKUP"
    mv "$REF_DIR" "$BACKUP"
    mkdir -p "$REF_DIR"
fi

mkdir -p "$REF_DIR"

# Download FASTA
echo "Downloading FASTA..."
curl -s "${EUTILS}?db=nuccore&id=${ACCESSION}&rettype=fasta&retmode=text" > "$REF_DIR/virus.fa"

# Download GenBank
echo "Downloading GenBank..."
curl -s "${EUTILS}?db=nuccore&id=${ACCESSION}&rettype=gb&retmode=text" > "$REF_DIR/virus.gb"

# Verify FASTA header
HEADER=$(head -1 "$REF_DIR/virus.fa")
echo "FASTA header: $HEADER"

if [[ ! "$HEADER" == ">$ACCESSION"* ]]; then
    echo "WARNING: FASTA header does not start with >$ACCESSION"
    echo "The contig name in BAM headers will be: ${HEADER#>}"
fi

# Generate GTF from GenBank CDS coordinates
echo "Generating GTF from GenBank CDS features..."
python3 - "$REF_DIR/virus.gb" "$REF_DIR/virus.gtf" "$ACCESSION" << 'PYEOF'
import re
import sys

gb_path = sys.argv[1]
gtf_path = sys.argv[2]
accession = sys.argv[3]

with open(gb_path) as f:
    content = f.read()

# Genome length from LOCUS line
m = re.search(r'LOCUS\s+\S+\s+(\d+)\s+bp', content)
if not m:
    print("ERROR: Could not parse genome length from LOCUS line", file=sys.stderr)
    sys.exit(1)
genome_length = int(m.group(1))

# Extract CDS features (alphaviruses have 2: nsP1234 + structural)
cds_matches = re.findall(r'CDS\s+(?:complement\()?<?(\d+)\.\.>?(\d+)\)?', content)
cds_features = sorted([(int(s), int(e)) for s, e in cds_matches])

if len(cds_features) >= 2:
    nsp_start, nsp_end = cds_features[0]
    struct_start, struct_end = cds_features[1]
elif len(cds_features) == 1:
    nsp_start, nsp_end = cds_features[0]
    struct_start, struct_end = nsp_end + 1, genome_length
else:
    print("ERROR: No CDS features found in GenBank file", file=sys.stderr)
    sys.exit(1)

# 26S subgenomic RNA starts at structural CDS start
s26_start = struct_start

# Determine gene name based on accession (EEEV or VEEV)
gene_name = "EEEV" if "EEEV" in accession or "KP282670" in accession else "VEEV"

with open(gtf_path, 'w') as f:
    f.write(f'{accession}\tcurated\tgene\t1\t{genome_length}\t.\t+\t.\tgene_id "{gene_name}"; gene_name "{gene_name}";\n')
    f.write(f'{accession}\tcurated\ttranscript\t1\t{genome_length}\t.\t+\t.\tgene_id "{gene_name}"; gene_name "{gene_name}"; transcript_id "{gene_name}_49S"; transcript_name "{gene_name}_49S";\n')
    f.write(f'{accession}\tcurated\texon\t1\t{genome_length}\t.\t+\t.\tgene_id "{gene_name}"; gene_name "{gene_name}"; transcript_id "{gene_name}_49S"; transcript_name "{gene_name}_49S";\n')
    f.write(f'{accession}\tcurated\ttranscript\t{s26_start}\t{genome_length}\t.\t+\t.\tgene_id "{gene_name}"; gene_name "{gene_name}"; transcript_id "{gene_name}_26S"; transcript_name "{gene_name}_26S";\n')
    f.write(f'{accession}\tcurated\texon\t{s26_start}\t{genome_length}\t.\t+\t.\tgene_id "{gene_name}"; gene_name "{gene_name}"; transcript_id "{gene_name}_26S"; transcript_name "{gene_name}_26S";\n')

print(f"Genome:  {genome_length} bp")
print(f"nsP1234: {nsp_start}-{nsp_end}")
print(f"Struct:  {struct_start}-{struct_end}")
print(f"26S RNA: {s26_start}-{genome_length}")
print(f"GTF written to {gtf_path}")
PYEOF

echo ""
echo "=== Done ==="
echo "Reference files in $REF_DIR:"
ls -lh "$REF_DIR/"
echo ""
echo "Next steps:"
echo "  1. Delete old combined reference:"
echo "     rm -f references/build/<dataset>/combined.fa references/build/<dataset>/combined.gtf"
echo "  2. Discard old results:"
echo "     rm -rf \$RESULTS_BASE/../work/<dataset>"
echo "  3. Re-run: sbatch submit_rnaseq.sh <dataset>"
