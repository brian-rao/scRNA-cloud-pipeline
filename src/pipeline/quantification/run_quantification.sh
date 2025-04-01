#!/bin/bash
set -e  # Stop on error

SCRIPT_DIR="$(dirname "$0")"

################    HELP MESSAGE    ################
usage() {
    echo "Usage: $0 [-b s3_bucket] [-h]"
    echo
    echo "Options:"
    echo "  -b    S3 bucket URL (required, e.g. s3://mybucket)"
    echo "  -h    Display this help message"
    echo
    echo "Environment variables can also be set in .env file:"
    echo "  S3_BUCKET           Same as -b"
    exit 1
}

################    INPUT HANDLING    ################

# Load .env file if it exists
ENV_FILE=".env"
echo "Looking for $ENV_FILE"
if [ -f "$ENV_FILE" ]; then
    echo "Found $ENV_FILE, sourcing it"
    source "$ENV_FILE"
    echo "AWS_ACCESS_KEY_ID is set as $AWS_ACCESS_KEY_ID"
else
    echo "Could not find $ENV_FILE"
fi

# Allow command-line arguments to override .env values - in this case, the .env will have our AWS credentials
while getopts "b:h" flag; do
    case "${flag}" in
        b) S3_BUCKET=${OPTARG};;
        h) usage;;
        *) usage;;
    esac
done

# Validate that required variables are set
if [ -z "$S3_BUCKET" ]; then
    echo "Error: S3 bucket URL (-b) is required!"
    usage
fi

# Ensure S3 bucket URL has proper format
if [[ ! "$S3_BUCKET" == s3://* ]]; then
    echo "Error: S3 bucket URL must start with s3://"
    exit 1
fi

# Remove trailing slash if present
S3_BUCKET=${S3_BUCKET%/}


# Set AWS credentials
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" 
aws configure set default.region "$AWS_DEFAULT_REGION"


# Test the connection
aws s3 ls $S3_BUCKET

# Define standard paths
REF_DIR="kallisto_reference"
LOCAL_REF_DIR="$REF_DIR"
READS_DIR="reads"
OUTPUT_DIR="output"
KALLISTO_OUTPUT_DIR="kallisto_output"
BUSTOOLS_OUTPUT_DIR="bustools_output"
COUNTS_OUTPUT_DIR="counts"
S3_REF_PATH="$S3_BUCKET/$REF_DIR"
INDEX_FILE="$LOCAL_REF_DIR/kallisto_index.idx"
MAPPING_FILE="$LOCAL_REF_DIR/transcript_to_gene.txt"
S3_INDEX_FILE="$S3_REF_PATH/kallisto_index.idx"
S3_MAPPING_FILE="$S3_REF_PATH/transcript_to_gene.txt"
S3_READS_DIR=$S3_BUCKET/$READS_DIR
THREADS="4"
WHITELIST_PATH="10xv3_whitelist.txt" # Path to your 10x whitelist file

# Set defaults for optional features
CLEAN_TMP=false
UPLOAD_RESULTS=true
S3_OUTPUT_DIR="$S3_BUCKET/quantification_results"

# Create local reference directory to download references to
# the whitelist copying makes the kallisto_reference dir now
mkdir -p "$LOCAL_REF_DIR"

################    CHECK AND DOWNLOAD REFERENCES AND READ FILES    ################

# Check if both index and mapping files exist in S3
INDEX_EXISTS=false
MAPPING_EXISTS=false
READS_EXIST=false

if aws s3 ls "$S3_INDEX_FILE" &>/dev/null; then
    INDEX_EXISTS=true
    echo "Index file exists in S3: $S3_INDEX_FILE"
else 
    echo "Index file not found in bucket!"
fi

if aws s3 ls "$S3_MAPPING_FILE" &>/dev/null; then
    MAPPING_EXISTS=true
    echo "Mapping file exists in S3: $S3_MAPPING_FILE"
else 
    echo "Mapping file not found in bucket!"
fi

# Download files that exist in S3 into kallisto_reference/
if [ "$INDEX_EXISTS" = true ]; then
    echo "Downloading index file from S3..."
    aws s3 cp "$S3_INDEX_FILE" "$REF_DIR/"
fi

if [ "$MAPPING_EXISTS" = true ]; then
    echo "Downloading mapping file from S3..."
    aws s3 cp "$S3_MAPPING_FILE" "$REF_DIR/"
fi

# If both files exist and were downloaded
if [ "$INDEX_EXISTS" = true ] && [ "$MAPPING_EXISTS" = true ]; then
    echo "Both index and mapping files downloaded from S3"  
fi

# Check if reads directory exists in S3
if aws s3 ls "$S3_READS_DIR/" &>/dev/null; then
    # Check if there are actually fastq files in the directory - needs this instead of wildcards
    if aws s3 ls "$S3_READS_DIR/" | grep -E "\.fastq(\.gz)?$" &>/dev/null; then
        READS_EXIST=true
        echo "Read files exist in S3: $S3_READS_DIR/"
    else
        echo "Reads directory exists but no FASTQ files found!"
    fi
else 
    echo "Reads directory not found in bucket!"
fi

# Download reads if they exist in S3
if [ "$READS_EXIST" = true ]; then
    echo "Downloading read files from S3..."
    mkdir -p "$READS_DIR"
    aws s3 cp "$S3_READS_DIR/" "$READS_DIR/" --recursive --exclude "*" --include "*.fastq*"
    echo "Read files downloaded to $READS_DIR/"
fi


################    QUANTIFICATION    ################

# Check if all required files are present
if [ ! -f "$INDEX_FILE" ]; then
    echo "Error: Index file not found at $INDEX_FILE"
    exit 1
fi

if [ ! -f "$MAPPING_FILE" ]; then
    echo "Error: Mapping file not found at $MAPPING_FILE"
    exit 1
fi

if [ ! -d "$READS_DIR" ] || [ -z "$(ls -A $READS_DIR/*.fastq* 2>/dev/null)" ]; then
    echo "Error: No read files found in $READS_DIR"
    exit 1
fi

if [ ! -f "$WHITELIST_PATH" ]; then
    echo "Error: Whitelist file not found at $WHITELIST_PATH"
    exit 1
fi

echo "All required files present. Starting quantification..."

# Create an associative array to track processed samples
declare -A processed_samples

# Organize input files by sample
for fastq in "$READS_DIR"/*.fastq*; do
    # Get filename without path
    file_name=$(basename "$fastq")
    
    # Extract sample name using sed pattern to handle common formats
    sample_name=$(echo "$file_name" | sed -E 's/_(R)?[12]\.fastq.*$|\.([12]|R[12])\.fastq.*$|_S[0-9]+_L[0-9]+_R[12]_[0-9]+\.fastq.*$//')
    
    # Skip if we've already processed this sample
    if [ "${processed_samples[$sample_name]}" ]; then
        continue
    fi
    
    echo "Processing sample: $sample_name"
    processed_samples[$sample_name]=1
    
    # Create sample-specific output directories
    SAMPLE_TMP_DIR="$OUTPUT_DIR/$sample_name/tmp"
    SAMPLE_COUNTS_DIR="$OUTPUT_DIR/$sample_name/counts"
    mkdir -p "$SAMPLE_TMP_DIR"
    mkdir -p "$SAMPLE_COUNTS_DIR"
    
    # Find all related FASTQ files for this sample
    sample_fastqs=($READS_DIR/${sample_name}*.fastq*)
    echo "Found ${#sample_fastqs[@]} FASTQ files for sample $sample_name"
    
    # Run kallisto bus for this sample
    echo "Running kallisto bus for $sample_name..."
    kallisto bus \
        -i "$INDEX_FILE" \
        -o "$SAMPLE_TMP_DIR" \
        -x 10xv3 \
        -t $THREADS \
        "${sample_fastqs[@]}"
    
    # Run bustools correct
    echo "Running bustools correct for $sample_name..."
    bustools correct \
        -w "$WHITELIST_PATH" \
        -o "$SAMPLE_TMP_DIR/output.correct.bus" \
        "$SAMPLE_TMP_DIR/output.bus"
    
    # Run bustools sort
    echo "Running bustools sort for $sample_name..."
    bustools sort \
        -t $THREADS \
        -o "$SAMPLE_TMP_DIR/output.correct.sort.bus" \
        "$SAMPLE_TMP_DIR/output.correct.bus"
    
    # Run bustools count
    echo "Running bustools count for $sample_name..."
    bustools count \
        -o "$SAMPLE_COUNTS_DIR/${sample_name}" \
        -g "$MAPPING_FILE" \
        -e "$SAMPLE_TMP_DIR/matrix.ec" \
        -t "$SAMPLE_TMP_DIR/transcripts.txt" \
        --genecounts \
        "$SAMPLE_TMP_DIR/output.correct.sort.bus"
    
    echo "Quantification complete for sample $sample_name"
    
    # Optional: Clean up
    if [ "$CLEAN_TMP" = true ]; then
        echo "Cleaning up temporary files for $sample_name..."
        rm -rf "$SAMPLE_TMP_DIR"
    fi
    
    # Optional: Upload results
    if [ "$UPLOAD_RESULTS" = true ]; then
        echo "Uploading results for $sample_name to S3..."
        aws s3 cp --recursive "$SAMPLE_COUNTS_DIR/" "$S3_OUTPUT_DIR/$sample_name/"
    fi
done

echo "All samples processed successfully."