import os
import shutil
import subprocess
from pathlib import Path
import pytest

repo_root = Path(__file__).resolve().parent.parent


def test_make_samplesheet_success():
    fastq_dir = repo_root / "inputs" / "test_tmp_fastqs"
    out_csv = repo_root / "metadata" / "test_tmp_samplesheet.csv"

    fastq_dir.mkdir(parents=True, exist_ok=True)

    r1 = fastq_dir / "101_R1_001.fastq.gz"
    r2 = fastq_dir / "101_R2_001.fastq.gz"
    r1.write_bytes(b"dummy")
    r2.write_bytes(b"dummy")

    try:
        res = subprocess.run(
            ["bash", "bin/make_samplesheet.sh", "inputs/test_tmp_fastqs", "metadata/test_tmp_samplesheet.csv"],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
        )
        assert res.returncode == 0, f"make_samplesheet failed: {res.stderr}"
        assert out_csv.exists()

        content = out_csv.read_text(encoding="utf-8").strip().splitlines()
        assert content[0] == "sample,fastq_1,fastq_2,strandedness"
        assert content[1].startswith("s101,")
    finally:
        if fastq_dir.exists():
            shutil.rmtree(fastq_dir)
        if out_csv.exists():
            out_csv.unlink()


def test_make_samplesheet_missing_mate():
    fastq_dir = repo_root / "inputs" / "test_tmp_fastqs_missing"
    out_csv = repo_root / "metadata" / "test_tmp_samplesheet_missing.csv"

    fastq_dir.mkdir(parents=True, exist_ok=True)

    r1 = fastq_dir / "101_R1_001.fastq.gz"
    r1.write_bytes(b"dummy")

    try:
        res = subprocess.run(
            ["bash", "bin/make_samplesheet.sh", "inputs/test_tmp_fastqs_missing", "metadata/test_tmp_samplesheet_missing.csv"],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
        )
        assert res.returncode != 0
        assert "Missing mate" in res.stderr or "R2 file count" in res.stderr
    finally:
        if fastq_dir.exists():
            shutil.rmtree(fastq_dir)
        if out_csv.exists():
            out_csv.unlink()
        for leftover in repo_root.glob("metadata/test_tmp_samplesheet_missing.csv.*"):
            try:
                leftover.unlink()
            except OSError:
                pass


@pytest.fixture
def mock_pipeline_inputs():
    fastq_dir = repo_root / "inputs" / "mouse_veev"
    host_dir = repo_root / "references" / "mouse"
    
    fastq_dir.mkdir(parents=True, exist_ok=True)
    host_dir.mkdir(parents=True, exist_ok=True)

    dummy_r1 = fastq_dir / "dummy_sample_101_R1_001.fastq.gz"
    dummy_r2 = fastq_dir / "dummy_sample_101_R2_001.fastq.gz"
    dummy_host_fa = host_dir / "dummy_host.fa"
    dummy_host_gtf = host_dir / "dummy_host.gtf"

    dummy_r1.write_bytes(b"dummy")
    dummy_r2.write_bytes(b"dummy")
    dummy_host_fa.write_bytes(b">chr1\nACGT\n")
    dummy_host_gtf.write_bytes(b"chr1\ttest\texon\t1\t10\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n")

    yield

    for p in (dummy_r1, dummy_r2, dummy_host_fa, dummy_host_gtf):
        if p.exists():
            p.unlink()


def test_submit_rnaseq_preflight(mock_pipeline_inputs):
    res = subprocess.run(
        ["bash", "-c", "PREFLIGHT_ONLY=1 bash submit_rnaseq.sh mouse_veev"],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"Preflight check failed.\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
    assert "Preflight checks passed for mouse_veev" in res.stdout


def test_submit_rnaseq_dry_run(mock_pipeline_inputs):
    res = subprocess.run(
        ["bash", "-c", "DRY_RUN=1 SKIP_MODULE_LOAD=1 SKIP_RUNTIME_CHECK=1 ISAAC_ACCOUNT=ACF-UTK9999 SCRATCHDIR=/tmp/scratch_test bash submit_rnaseq.sh mouse_veev"],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"Dry run failed.\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
    assert "DRY_RUN nextflow command:" in res.stdout
    assert "nf-core/rnaseq" in res.stdout
