#!/bin/bash
set -e  # Stop on error



SCRIPT_DIR="$(dirname "$0")"

################    HELP MESSAGE    ################
usage() {
    echo "Usage: $0 [-i input_dir] [-o output_dir] [-h]"
    echo
    echo "Options:"
    echo "  -i    Input directory containing .fastq files"
    echo "  -o    Output directory for analysis results"
    echo "  -h    Display this help message"
    echo
    echo "Environment variables can also be set in .env file:"
    echo "  INPUT_DIR   Same as -i"
    echo "  OUTPUT_DIR  Same as -o"
    exit 1
}

################    INPUT HANDLING    ################

#use .env for development
ENV_FILE="$SCRIPT_DIR/.env"

# Load .env file if it exists
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

#use FastQC dir for local testing, if in container it should be accessible from PATH
if [ -n "$FASTQC_DIR" ]; then
    FASTQC_CMD="$FASTQC_DIR"
else
    FASTQC_CMD="fastqc"  # Use system PATH in container
fi


# Allow command-line arguments to override .env values
while getopts "i:o:h" flag; do
    case "${flag}" in
        i) INPUT_DIR=${OPTARG};;
        o) OUTPUT_DIR=${OPTARG};;
        h) usage;;
        *) usage;;
    esac
done

# Validate that required variables are set
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Error: INPUT_FILE or OUTPUT_DIR is missing!"
    echo "Usage: $0 <input_file> <output_dir>"
    echo "Or set them in the .env file."
    exit 1
fi

# Ensure the input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' not found!"
    exit 1
fi

# Check if the directory contains at least one .fastq file
if ! ls "$INPUT_DIR"/*.fastq 1> /dev/null 2>&1; then
    echo "Error: No .fastq files found in '$INPUT_DIR'!"
    exit 1
fi

# Ensure the output directory exists, or create it
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Output directory does not exist. Creating: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

################    ANALYSIS    ################

echo "Running FastQC..."
"${FASTQC_CMD}" -t 4 -o "$OUTPUT_DIR" "$INPUT_DIR"/*.fastq

echo "Running additional Python calculations..."

#activating and deactivating the conda env will not be necessary inside the docker container - develop plots inside conda env locally then add reqs to image
#use conda dir for local testing, if in container python should be accessible from PATH
if [ -n "$CONDA_DIR" ]; then
    PYTHON_CMD="source $CONDA_DIR conda activate $CONDA_ENV"
else
    PYTHON_CMD="python"  # Use system PATH in container
fi

python "$SCRIPT_DIR/qc_reads.py" #placeholder print statement

echo "FastQC & analysis completed! Results in $OUTPUT_DIR"