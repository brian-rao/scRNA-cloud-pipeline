#!/bin/bash
set -e  # Stop on error



SCRIPT_DIR="$(dirname "$0")"


################    INPUT HANDLING    ################

#use .env for development
ENV_FILE="$SCRIPT_DIR/.env"

# Load .env file if it exists
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "Warning: .env file not found in $SCRIPT_DIR. Running without defaults."
fi

# Allow command-line arguments to override .env values
INPUT_DIR="${1:-$INPUT_DIR}"
OUTPUT_DIR="${2:-$OUTPUT_DIR}"

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
"${FASTQC_DIR}" -t 4 -o "$OUTPUT_DIR" "$INPUT_DIR"/*.fastq

echo "Running additional Python calculations..."

#activating and deactivating the conda env will not be necessary inside the docker container - develop plots inside conda env locally then add reqs to image
source ~/miniconda3/etc/profile.d/conda.sh #ensures conda commands are available
conda activate plot_qc_reads

python "$SCRIPT_DIR/qc_reads.py" #placeholder print statement

echo "FastQC & analysis completed! Results in $OUTPUT_DIR"