#debian-based, python comes pre-installed
FROM python:3.9-slim

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies and FastQC
RUN apt-get update && apt-get install -y \
    fastqc \
    default-jre \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir \
    numpy \
    pandas \
    matplotlib \
    seaborn

# Create a directory structure
WORKDIR /app
RUN mkdir -p /scripts

# Get pipeline scripts
COPY src/pipeline/qc_reads/run_qc_reads.sh scripts/
RUN chmod +x scripts/run_qc_reads.sh
COPY src/pipeline/qc_reads/qc_reads.py scripts/
COPY docker/qc_reads/check_versions.sh scripts/

#Get test files
COPY docker/qc_reads/test_data test_data

#Get .env for testing
#COPY src/pipeline/qc_reads/.env /app

# Verify installations
RUN python --version && \
python -c "import numpy; print(numpy.__version__)" && \
python -c "import matplotlib; print(matplotlib.__version__)" && \
python -c "import seaborn; print(seaborn.__version__)" && \
fastqc --version

# Set default command to bash
CMD ["/bin/bash"]


