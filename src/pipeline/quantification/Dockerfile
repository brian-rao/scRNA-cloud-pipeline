FROM nfcore/base:2.1

# Install Kallisto and Bustools
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    zlib1g-dev \
    libhdf5-dev \
    libboost-all-dev \
    wget \
    git \
    autoconf \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Kallisto
RUN wget https://github.com/pachterlab/kallisto/archive/v0.48.0.tar.gz && \
    tar -xzf v0.48.0.tar.gz && \
    cd kallisto-0.48.0 && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make && \
    make install && \
    cd ../.. && \
    rm -rf kallisto-0.48.0 v0.48.0.tar.gz

# Install Bustools
RUN wget https://github.com/BUStools/bustools/archive/v0.43.1.tar.gz && \
    tar -xzf v0.43.1.tar.gz && \
    cd bustools-0.43.1 && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make && \
    make install && \
    cd ../.. && \
    rm -rf bustools-0.43.1 v0.43.1.tar.gz

# Install AWS CLI - the nfcore way
RUN conda install -c conda-forge awscli \
    && conda clean -a

# Final verification and information
RUN echo "=== Installation Verification ===" && \
    echo "Kallisto version: $(kallisto version)" && \
    echo "Bustools version: $(bustools --version)" && \
    echo "AWS CLI version: $(aws --version)" && \
    echo "=================================="

# Create a directory structure
WORKDIR /app
RUN mkdir -p scripts

# Copy your scripts, resources, etc
COPY . .
RUN chmod +x run_build_references.sh
RUN chmod +x run_quantification.sh

#non-parallelizeable test script
RUN chmod +x run_build_references_singles.sh

