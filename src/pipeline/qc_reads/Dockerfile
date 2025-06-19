#debian-based, python comes pre-installed
FROM python:3.9-slim

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies and FastQC
RUN apt-get update && apt-get install -y \
    fastqc \
    default-jre \
    && rm -rf /var/lib/apt/lists/*

# Install aws reqs for NF
RUN apt-get update && apt-get install -y python3-pip
RUN pip3 install awscli

# Install Python packages
#RUN pip install --no-cache-dir \
#    numpy \
#    pandas \
#    matplotlib \
#    seaborn

# Create a directory structure
WORKDIR /app
#RUN mkdir -p /scripts

# where the output goes
RUN mkdir -p reads_qc/

# Get pipeline scripts, test files, etc
COPY . .
RUN chmod +x run_qc_reads.sh

#remove .env since thats just for local testing(non-container)
RUN rm .env

#Get test files


#Get .env for testing
#COPY src/pipeline/qc_reads/.env /app

# Verify installations
#RUN python --version && \
#python -c "import numpy; print(numpy.__version__)" && \
#python -c "import matplotlib; print(matplotlib.__version__)" && \
#python -c "import seaborn; print(seaborn.__version__)" && \
RUN fastqc --version

# Set default command to bash
CMD ["/bin/bash"]


