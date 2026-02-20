
![Version](https://img.shields.io/badge/version-0.13.0-brightgreen)

## Overview

This module is designed to function as both a standalone MAG short-read quality control pipeline as well as a component of the larger CAMP metagenome analysis pipeline. As such, it is both self-contained (ex. instructions included for the setup of a versioned environment, etc.), and seamlessly compatible with other CAMP modules (ex. ingests and spawns standardized input/output config files, etc.).

There are two filtration steps in the module: i) for general poor quality (Phred scores, length, Ns, adapters, polyG/X) and ii) for host reads — followed by a sequencing error correction step. The properties of the QC-ed FastQs are summarized in aggregate by a MultiQC report.

---

## Installation

### Option 1: Docker (Recommended)

No conda setup required. Pull and run the pre-built image.

```bash
docker pull raquellewei/camp_short-read-quality-control-docker:latest
```

Or build the image yourself from this repo:

```bash
git clone https://github.com/raquellewei/camp_short-read-quality-control-docker
cd camp_short-read-quality-control-docker
docker build -t camp-srqc .
```

### Option 2: Local conda install

See the [original upstream repo](https://github.com/Meta-CAMP/camp_short-read-quality-control) for conda-based local installation instructions using `setup.sh`.

---

## Using the Docker Image

### Input

Prepare a `samples.csv` with absolute paths to your FASTQ files:

```
sample_name,illumina_fwd,illumina_rev
sample1,/data/input/sample1_1.fastq.gz,/data/input/sample1_2.fastq.gz
```

> Paths in `samples.csv` must be paths **inside the container** (i.e. under `/data/input/`).

### Output

The pipeline produces:
- `/data/output/short_read_qc/final_reports/samples.csv` — output config for the next CAMP module
- `/data/output/short_read_qc/final_reports/read_stats.csv` — per-step read retention statistics
- `/data/output/short_read_qc/final_reports/*_multiqc_report.html` — pre/post QC reports

---

### Running the Pipeline

Mount your input FASTQs, output directory, and config files, then run:

```bash
docker run \
    -v /path/to/your/fastqs:/data/input \
    -v /path/to/your/output:/data/output \
    -v /path/to/your/config:/data/config \
    camp-srqc run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv
```

**Options:**

| Flag | Description |
|------|-------------|
| `-c` | Number of CPU cores (default: 1; use 10+ for real datasets) |
| `-d` | Working directory inside the container (e.g. `/data/output`) |
| `-s` | Path to `samples.csv` inside the container |
| `-p` | Path to a custom `parameters.yaml` (optional) |
| `-r` | Path to a custom `resources.yaml` (optional) |
| `--dry_run` | Print workflow commands without executing |
| `--unlock` | Remove a lock on the working directory after a failed run |

---

### Host Read Filtering (Optional)

By default, host filtering is **disabled**. To enable it:

1. Build or download a Bowtie2 index for your reference genome (e.g. human GRCh38 or mouse GRCm39)
2. Mount the index directory to `/data/ref`
3. Mount a custom `parameters.yaml` with host filtering enabled:

```yaml
use_host_filter: 'True'
host_ref_genome: '/data/ref/hg38'   # prefix of your .bt2 index files
```

```bash
docker run \
    -v /path/to/your/fastqs:/data/input \
    -v /path/to/your/output:/data/output \
    -v /path/to/your/bowtie2_index:/data/ref \
    -v /path/to/your/config:/data/config \
    camp-srqc run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv \
    -p /data/config/parameters.yaml
```

---

### Running the Built-in Test

Runs the pipeline on a small bundled dataset (4 bacterial gut genomes at 10X coverage). Should finish in ~3 minutes with 10 cores and 40 GB RAM.

```bash
docker run camp-srqc test
```

---

### Cleanup Intermediate Files

After confirming your outputs are complete, reclaim disk space:

```bash
docker run \
    -v /path/to/your/output:/data/output \
    -v /path/to/your/config:/data/config \
    camp-srqc cleanup \
    -d /data/output \
    -s /data/config/samples.csv
```

---

### Debugging

Drop into a shell inside the container:

```bash
docker run --entrypoint /bin/bash -it camp-srqc
```

Then manually invoke the pipeline:

```bash
conda run -n short-read-quality-control \
    python /opt/camp/workflow/short-read-quality-control.py --help
```

---

### Custom Parameters

The image ships with a default `parameters.yaml` baked in at `/opt/camp/configs/parameters.yaml`. To override it, mount your own:

```bash
docker run \
    -v /path/to/my/parameters.yaml:/opt/camp/configs/parameters.yaml \
    camp-srqc run ...
```

Key parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `minqual` | `30` | Phred quality threshold |
| `dedup` | `False` | Enable deduplication |
| `error_correction` | `'tadpole'` | Error correction method (`tadpole` or `bayeshammer`) |
| `use_host_filter` | `False` | Enable host read filtering |
| `host_ref_genome` | `'/data/ref'` | Bowtie2 index prefix |
| `qc_dataviz` | `False` | Enable dataviz (not available in this image) |

---

## Module Structure

```
└── workflow
    ├── Snakefile
    ├── short-read-quality-control.py
    ├── utils.py
    ├── __init__.py
    └── ext/
        └── common_adapters.txt
```

- `workflow/short-read-quality-control.py`: Click-based CLI wrapping Snakemake for clean management of parameters, resources, and environment variables.
- `workflow/Snakefile`: The Snakemake pipeline definition.
- `workflow/utils.py`: Sample ingestion, work directory setup, and other utility functions.
- `workflow/ext/`: Small auxiliary files used in the workflow (adapter sequences, etc.).

---

## Credits

- This package was created with [Cookiecutter](https://github.com/cookiecutter/cookiecutter) as a simplified version of the [project template](https://github.com/audreyr/cookiecutter-pypackage).
- Original upstream repo: [Meta-CAMP/camp_short-read-quality-control](https://github.com/Meta-CAMP/camp_short-read-quality-control)
- Free software: MIT
- Documentation: https://camp-documentation.readthedocs.io/en/latest/short-read-quality-control.html
