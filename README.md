
![Version](https://img.shields.io/badge/version-0.13.0-brightgreen)

## Overview

This module is designed to function as both a standalone MAG short-read quality control pipeline as well as a component of the larger CAMP metagenome analysis pipeline. As such, it is both self-contained (ex. instructions included for the setup of a versioned environment, etc.), and seamlessly compatible with other CAMP modules (ex. ingests and spawns standardized input/output config files, etc.).

There are two filtration steps in the module: i) for general poor quality (Phred scores, length, Ns, adapters, polyG/X) and ii) for host reads — followed by a sequencing error correction step. The properties of the QC-ed FastQs are summarized in aggregate by a MultiQC report.

---

## Installation

### Option 1: Singularity/Apptainer (Recommended — HPC & Linux servers)

No conda setup required. Singularity pulls the image directly from Docker Hub and caches it as a `.sif` file:

```bash
singularity pull camp-srqc.sif docker://raquelle70679/camp-srqc:latest
```

Run the built-in test to verify:
```bash
singularity run camp-srqc.sif test
```

> **Note:** Apptainer is the new name for Singularity (v3.9+). All commands are identical — just replace `singularity` with `apptainer`.

### Option 2: Docker (Cloud VMs & local machines)

```bash
docker pull raquelle70679/camp-srqc:latest
```

Or build the image yourself from this repo:

```bash
git clone https://github.com/raquellewei/camp_short-read-quality-control-docker
cd camp_short-read-quality-control-docker
docker build -t camp-srqc .
```

### Option 3: Local conda install

See the [original upstream repo](https://github.com/Meta-CAMP/camp_short-read-quality-control) for conda-based local installation instructions using `setup.sh`.

---

## Using the Container

### Input

Prepare a `samples.csv` with absolute paths to your FASTQ files **as they will appear inside the container**:

```
sample_name,illumina_fwd,illumina_rev
sample1,/data/input/sample1_1.fastq.gz,/data/input/sample1_2.fastq.gz
```

### Output

The pipeline produces:
- `/data/output/short_read_qc/final_reports/samples.csv` — output config for the next CAMP module
- `/data/output/short_read_qc/final_reports/read_stats.csv` — per-step read retention statistics
- `/data/output/short_read_qc/final_reports/*_multiqc_report.html` — pre/post QC reports

---

## Singularity Usage

### Running the Pipeline

```bash
singularity run \
    --bind /path/to/your/fastqs:/data/input \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    camp-srqc.sif run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv
```

### Running on a Slurm Cluster

```bash
sbatch << 'EOF'
#!/bin/bash
#SBATCH --job-name=camp-srqc
#SBATCH --cpus-per-task=10
#SBATCH --mem=40G
#SBATCH --output=camp-srqc-%j.log

singularity run \
    --bind /path/to/your/fastqs:/data/input \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    camp-srqc.sif run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv
EOF
```

### Host Read Filtering (Optional)

By default, host filtering is **disabled**. To enable it:

1. Build or download a Bowtie2 index for your reference genome (e.g. human GRCh38 or mouse GRCm39)
2. Bind the index directory to `/data/ref`
3. Mount a custom `parameters.yaml` with host filtering enabled:

```yaml
use_host_filter: True
host_ref_genome: '/data/ref/hg38'   # prefix of your .bt2 index files
```

```bash
singularity run \
    --bind /path/to/your/fastqs:/data/input \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/bowtie2_index:/data/ref \
    --bind /path/to/your/config:/data/config \
    camp-srqc.sif run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv \
    -p /data/config/parameters.yaml
```

### Running the Built-in Test

```bash
mkdir -p ~/camp-test-out
singularity run \
    --bind ~/camp-test-out:/data/test_out \
    ~/CAMP/camp-srqc.sif test
```

Output will be written to `~/camp-test-out/` on your host so you can inspect it. Test output is kept separate from real experiment output (`/data/output`) to avoid mixing the two.

### Cleanup Intermediate Files

```bash
singularity run \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    camp-srqc.sif cleanup \
    -d /data/output \
    -s /data/config/samples.csv
```

### Debugging

Drop into a shell inside the container:

```bash
singularity shell camp-srqc.sif
```

Then manually invoke the pipeline:

```bash
conda run -n short-read-quality-control \
    python /opt/camp/workflow/short-read-quality-control.py --help
```

### Custom Parameters

The image ships with a default `parameters.yaml` at `/opt/camp/configs/parameters.yaml`. To override it, bind your own file:

```bash
singularity run \
    --bind /path/to/my/parameters.yaml:/opt/camp/configs/parameters.yaml \
    camp-srqc.sif run ...
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

## Docker Usage

### Running the Pipeline

```bash
docker run \
    -v /path/to/your/fastqs:/data/input \
    -v /path/to/your/output:/data/output \
    -v /path/to/your/config:/data/config \
    raquelle70679/camp-srqc:latest run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv
```

### Running the Built-in Test

```bash
mkdir -p ~/camp-test-out
docker run --rm \
    -v ~/camp-test-out:/data/test_out \
    raquelle70679/camp-srqc:latest test
```

### Debugging

```bash
docker run --entrypoint /bin/bash -it raquelle70679/camp-srqc:latest
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
