# =============================================================================
# CAMP Short-Read Quality Control Pipeline
# =============================================================================
# Base image: continuumio/miniconda3 (Debian-based, conda pre-installed)

# -----------------------------------------------------------------------------
# Step 1: Base Image
# -----------------------------------------------------------------------------
FROM continuumio/miniconda3:latest

LABEL maintainer="raquellewei"
LABEL description="CAMP Short-Read Quality Control Pipeline"
LABEL version="0.13.0"

# -----------------------------------------------------------------------------
# Step 2: System Dependencies
# -----------------------------------------------------------------------------
# - wget/curl        : downloading reference genomes at runtime
# - gzip/bzip2       : compressing/decompressing FASTQ files
# - perl             : required by FastQC (Perl-based)
# - default-jre      : system-level Java fallback for BBMap (tadpole/repair);
#                      openjdk-11 is dropped in Debian Trixie; BBMap's conda
#                      env brings its own openjdk=11 anyway
# - procps           : allows Snakemake to monitor system resources
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        curl \
        gzip \
        bzip2 \
        perl \
        default-jre-headless \
        procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Step 3: Main CAMP Conda Environment
# -----------------------------------------------------------------------------
# Installs the core runtime environment from the pinned yaml file.
# This includes: snakemake, click, pandas, biopython, bowtie2, fastp,
# adapterremoval, spades, samtools, and all supporting Python packages.
#
# Notes:
# - The yaml has both conda + pip sections; pip entries override conda ones
#   (e.g. snakemake ends up at 7.18.2 via pip, not 7.12.1 from conda).
#   This is intentional — we leave it as-is for now and address version
#   conflicts in a later cleanup pass.
# - dataviz.yaml is intentionally skipped (Jupyter/Qt/UMAP stack, ~270
#   packages, not needed for the core pipeline run).
COPY configs/conda/short-read-quality-control.yaml /tmp/conda/short-read-quality-control.yaml

RUN conda env create -f /tmp/conda/short-read-quality-control.yaml \
    && conda clean -afy

# -----------------------------------------------------------------------------
# Step 4: Tool-Specific Conda Environments
# -----------------------------------------------------------------------------
# BBMap and MultiQC each live in their own isolated conda environments.
# This mirrors exactly how setup.sh installs them locally, and avoids
# dependency conflicts with the main environment (e.g. MultiQC needs
# Python 3.6 and FastQC, BBMap needs OpenJDK 11).
#
# Snakemake will activate these envs at runtime via --conda-prefix.
# We pre-build them here so the container needs no internet access at
# pipeline runtime.
COPY configs/conda/bbmap.yaml /tmp/conda/bbmap.yaml
COPY configs/conda/multiqc.yaml /tmp/conda/multiqc.yaml

RUN conda env create -f /tmp/conda/bbmap.yaml \
    && conda env create -f /tmp/conda/multiqc.yaml \
    && conda clean -afy

# -----------------------------------------------------------------------------
# Step 5: Copy Pipeline Code
# -----------------------------------------------------------------------------
# Copy the pipeline source into /opt/camp inside the container.
# Only what's needed at runtime is copied — see .dockerignore for exclusions.
#
# Layout inside the container:
#   /opt/camp/workflow/   — Snakefile, CLI entrypoint, utils
#   /opt/camp/configs/    — conda yamls, parameters templates, resources
#   /opt/camp/test_data/  — bundled test FASTQs for smoke-testing
WORKDIR /opt/camp

COPY workflow/       ./workflow/
COPY configs/        ./configs/
COPY test_data/      ./test_data/

# -----------------------------------------------------------------------------
# Step 6: Generate Container-Appropriate parameters.yaml
# -----------------------------------------------------------------------------
# The pipeline reads parameters.yaml to find:
#   ext           — path to workflow/ext/ (adapter sequences, etc.)
#   conda_prefix  — where Snakemake looks for pre-built conda envs
#   adapters      — path to common_adapters.txt
#   host_ref_genome — Bowtie2 index prefix (user-mounted at runtime)
#   use_host_filter — defaults to False; user overrides if mounting a genome
#   qc_dataviz    — False since dataviz env is not installed
#
# Two copies are written:
#   configs/parameters.yaml   — default, used by normal pipeline runs
#   test_data/parameters.yaml — used by the built-in `test` command
#
# Users who need host filtering or custom settings can override by mounting
# their own parameters.yaml to /opt/camp/configs/parameters.yaml at runtime:
#   docker run -v /my/params.yaml:/opt/camp/configs/parameters.yaml ...
RUN printf '%s\n' \
    "#'''Parameters'''#" \
    "" \
    "ext: '/opt/camp/workflow/ext'" \
    "conda_prefix: '/opt/conda/envs'" \
    "" \
    "# --- general --- #" \
    "" \
    "minqual:    30" \
    "" \
    "" \
    "# --- filter_low_qual --- #" \
    "" \
    "dedup:      False" \
    "" \
    "" \
    "# --- filter_adapters --- #" \
    "" \
    "adapters: '/opt/camp/workflow/ext/common_adapters.txt'" \
    "" \
    "" \
    "# --- filter_host_reads --- #" \
    "# Set use_host_filter to True and mount your Bowtie2 index to" \
    "# /data/ref, then set host_ref_genome to the index prefix, e.g.:" \
    "#   host_ref_genome: '/data/ref/hg38'" \
    "" \
    "use_host_filter:         False" \
    "host_ref_genome:         '/data/ref'" \
    "" \
    "" \
    "# --- filter_seq_errors --- #" \
    "" \
    "# Options (must choose one): 'bayeshammer', 'tadpole'" \
    "error_correction: 'tadpole'" \
    "" \
    "" \
    "# --- qc-option --- #" \
    "# dataviz env not installed in this image; set to False" \
    "qc_dataviz: False" \
    > /opt/camp/configs/parameters.yaml \
    && cp /opt/camp/configs/parameters.yaml /opt/camp/test_data/parameters.yaml

# -----------------------------------------------------------------------------
# Step 7: Volume Mount Points
# -----------------------------------------------------------------------------
# Create the directories that users will mount at runtime.
# Docker doesn't require pre-creating these, but doing so:
#   - makes the expected interface explicit and self-documenting
#   - ensures the directories exist even if the user forgets to mount them
#     (the pipeline will fail gracefully rather than with a cryptic path error)
#
# Expected mounts:
#   /data/input   — user's raw FASTQ files
#   /data/output  — working directory for pipeline outputs
#   /data/ref     — Bowtie2 index directory (optional, for host filtering)
#   /data/config  — optional: override samples.csv or parameters.yaml
#
# Example docker run with all mounts:
#   docker run \
#     -v /my/fastqs:/data/input \
#     -v /my/output:/data/output \
#     -v /my/bowtie2_index:/data/ref \
#     -v /my/config:/data/config \
#     camp-srqc run -d /data/output -s /data/config/samples.csv
RUN mkdir -p /data/input /data/output /data/ref /data/config

VOLUME ["/data/input", "/data/output", "/data/ref", "/data/config"]

# Generate test_data/samples.csv with container-correct paths.
# This file is gitignored (setup.sh writes it locally with host paths),
# so we create it here pointing to the bundled test FASTQs inside the image.
RUN printf '%s\n' \
    "sample_name,illumina_fwd,illumina_rev" \
    "uhgg,/opt/camp/test_data/uhgg_1.fastq.gz,/opt/camp/test_data/uhgg_2.fastq.gz" \
    > /opt/camp/test_data/samples.csv

# -----------------------------------------------------------------------------
# Step 8: Entrypoint
# -----------------------------------------------------------------------------
# The CLI script must run inside the 'short-read-quality-control' conda env,
# since click, snakemake, pandas, etc. all live there — not in the base env.
#
# We use conda run to activate the env per-command rather than trying to
# activate it in the shell profile (which doesn't work reliably in Docker).
#
# ENTRYPOINT is fixed — always invokes the pipeline CLI.
# CMD provides the default subcommand ('run'), which users can override:
#
#   # Run the pipeline
#   docker run camp-srqc run -d /data/output -s /data/config/samples.csv
#
#   # Run the built-in test
#   docker run camp-srqc test
#
#   # Cleanup intermediate files
#   docker run camp-srqc cleanup -d /data/output -s /data/config/samples.csv
#
#   # Drop into a shell for debugging
#   docker run --entrypoint /bin/bash -it camp-srqc
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "short-read-quality-control", \
            "python", "/opt/camp/workflow/short-read-quality-control.py"]
CMD ["--help"]
