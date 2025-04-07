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

# Track processed samples to avoid duplicates
declare -A processed_fastqs

# Organize input files by sample
for fastq in "$INPUT_DIR"/*.fastq; do
    # Sed pattern to handle common formats:
    # Get filename without path
    file_name=$(basename "$fastq") 
    sample_name=$(echo "$file_name" | sed -E 's/_(R)?[12]\.fastq$|\.([12]|R[12])\.fastq$|_S[0-9]+_L[0-9]+_R[12]_[0-9]+\.fastq$//')
    echo "Extracted sample name: $sample_name"
    
    if [ "${processed_fastqs[$file_name]}" ]; then
        continue
    fi
    
    processed_fastqs[$file_name]=1
    
    # Create output structure
    sample_output_dir="$OUTPUT_DIR/${sample_name}_output/fastqc"
    mkdir -p "$sample_output_dir"
done

################    ANALYSIS    ################

for file_name in "${!processed_fastqs[@]}"; do
    echo "Running FastQC on $file_name..."
    sample_output_dir="$OUTPUT_DIR/${sample_name}_output/fastqc"

    fastqc -t 4 -o "$sample_output_dir" "$INPUT_DIR/$file_name"


    echo "FastQC on $file_name complete!"

done
#use conda dir for local testing, if in container python should be accessible from PATH
#    if [ -n "$CONDA_DIR" ]; then
#        source "$CONDA_DIR/etc/profile.d/conda.sh"
#        conda activate "$CONDA_ENV"
#    fi
#
#    python "$SCRIPT_DIR/qc_reads.py"
#
#    echo "FastQC & analysis on $sample_name completed! Results in $sample_output_dir"
#done