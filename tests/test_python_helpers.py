import sys
from pathlib import Path
import pytest

# Ensure bin directory is on sys.path for imports
repo_root = Path(__file__).resolve().parent.parent
bin_dir = repo_root / "bin"
if str(bin_dir) not in sys.path:
    sys.path.insert(0, str(bin_dir))

from stage_nat_hist_inputs import classify_sample
from prepare_smoke_inputs import load_manifest
from normalize_virus_gtf import parse_gtf_attributes, parse_gff_attributes


def test_classify_sample_rat():
    host, virus, dataset, rule = classify_sample("B12")
    assert host == "rat"
    assert virus == "VEEV"
    assert dataset == "rat_veev"
    assert rule == "rat_letter_code"

    host, virus, dataset, rule = classify_sample("L05")
    assert host == "rat"
    assert dataset == "rat_veev"


def test_classify_sample_mouse_eeev():
    host, virus, dataset, rule = classify_sample("40012")
    assert host == "mouse"
    assert virus == "EEEV"
    assert dataset == "mouse_eeev"
    assert rule == "five_digit_4xxxx"


def test_classify_sample_three_digit_ranges():
    # 100-199 -> mouse_veev
    assert classify_sample("105")[2] == "mouse_veev"
    # 200-299 -> mouse_eeev
    assert classify_sample("250")[2] == "mouse_eeev"
    # 300-399 -> mouse_veev
    assert classify_sample("310")[2] == "mouse_veev"
    # 400-499 -> mouse_eeev
    assert classify_sample("450")[2] == "mouse_eeev"


def test_classify_sample_invalid():
    with pytest.raises(ValueError, match="Unrecognized sample naming pattern"):
        classify_sample("X999")
    with pytest.raises(ValueError):
        classify_sample("50000")


def test_load_smoke_manifest(tmp_path):
    manifest_file = tmp_path / "smoke_samples.tsv"
    manifest_file.write_text(
        "dataset\tsample_id\tread_pairs\n"
        "mouse_veev\t101\t1000\n"
        "mouse_eeev\t201\t1000\n",
        encoding="utf-8"
    )
    data = load_manifest(manifest_file)
    assert "mouse_veev" in data
    assert data["mouse_veev"] == ("101", 1000)
    assert data["mouse_eeev"] == ("201", 1000)


def test_parse_gtf_attributes():
    raw = 'gene_id "GENE1"; transcript_id "TRANS1"; gene_name "test";'
    attrs = parse_gtf_attributes(raw)
    assert attrs["gene_id"] == "GENE1"
    assert attrs["transcript_id"] == "TRANS1"
    assert attrs["gene_name"] == "test"


def test_parse_gff_attributes():
    raw = "ID=gene1;Name=TestGene;biotype=protein_coding"
    attrs = parse_gff_attributes(raw)
    assert attrs["ID"] == "gene1"
    assert attrs["Name"] == "TestGene"
    assert attrs["biotype"] == "protein_coding"
