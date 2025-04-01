#!/bin/bash
set -e  # Stop on error

SCRIPT_DIR="$(dirname "$0")"

################    HELP MESSAGE    ################
usage() {
    echo "Usage: $0 [-b s3_bucket] [-v gencode_version] [-h]"
    echo
    echo "Options:"
    echo "  -b    S3 bucket URL (required, e.g. s3://mybucket)"
    echo "  -v    GENCODE version (default: 44)"
    echo "  -h    Display this help message"
    echo
    echo "Environment variables can also be set in .env file:"
    echo "  S3_BUCKET           Same as -b"
    echo "  GENCODE_VERSION     Same as -v"
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

# Default values
GENCODE_VERSION=${GENCODE_VERSION:-44}

# Allow command-line arguments to override .env values - in this case, the .env will have our AWS credentials
while getopts "b:v:h" flag; do
    case "${flag}" in
        b) S3_BUCKET=${OPTARG};;
        v) GENCODE_VERSION=${OPTARG};;
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
S3_REF_PATH="$S3_BUCKET/$REF_DIR"
INDEX_FILE="$LOCAL_REF_DIR/kallisto_index.idx"
MAPPING_FILE="$LOCAL_REF_DIR/transcript_to_gene.txt"
S3_INDEX_FILE="$S3_REF_PATH/kallisto_index.idx"
S3_MAPPING_FILE="$S3_REF_PATH/transcript_to_gene.txt"

# Create local reference directory
mkdir -p "$LOCAL_REF_DIR"

################    CHECK EXISTING FILES    ################

# Check if both index and mapping files exist in S3
INDEX_EXISTS=false
MAPPING_EXISTS=false

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

# If both files exist, exit
if [ "$INDEX_EXISTS" = true ] && [ "$MAPPING_EXISTS" = true ]; then
    echo "Both index and mapping files already exist in S3. Nothing to do."
    exit 0
fi

# If either file is missing, generate both
echo "One or more reference files are missing. Generating references..."

################    DOWNLOAD REFERENCE DATA    ################

# Download transcriptome from GENCODE
echo "Downloading transcriptome from GENCODE..."
TRANSCRIPTOME_URL="https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_${GENCODE_VERSION}/gencode.v${GENCODE_VERSION}.transcripts.fa.gz"
LOCAL_TRANSCRIPTOME="$LOCAL_REF_DIR/transcriptome.fa"

wget "$TRANSCRIPTOME_URL" -O "$LOCAL_REF_DIR/transcriptome.fa.gz" || {
    echo "ERROR: Failed to download transcriptome from GENCODE"
    exit 1
}

gunzip -f "$LOCAL_REF_DIR/transcriptome.fa.gz" || {
    echo "ERROR: Failed to decompress transcriptome file"
    exit 1
}

# Download GTF from GENCODE
echo "Downloading GTF annotation from GENCODE..."
GTF_URL="https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_${GENCODE_VERSION}/gencode.v${GENCODE_VERSION}.annotation.gtf.gz"
LOCAL_GTF="$LOCAL_REF_DIR/annotation.gtf"

wget "$GTF_URL" -O "$LOCAL_REF_DIR/annotation.gtf.gz" || {
    echo "ERROR: Failed to download GTF from GENCODE"
    exit 1
}

gunzip -f "$LOCAL_REF_DIR/annotation.gtf.gz" || {
    echo "ERROR: Failed to decompress GTF file"
    exit 1
}

################    GENERATE REFERENCE FILES    ################

# Generate transcript-to-gene mapping from GTF
echo "Generating transcript-to-gene mapping..."

awk -F"\t" '$3 == "transcript" {
    split($9,a,";");
    tid=""; gid="";
    for(i in a) {
        gsub(/^ +/,"",a[i]);  # Trim leading spaces
        if(a[i]~/transcript_id/) {
            match(a[i], /transcript_id "([^"]+)"/);
            tid = substr(a[i], RSTART+14, RLENGTH-15);
        }
        if(a[i]~/gene_id/) {
            match(a[i], /gene_id "([^"]+)"/);
            gid = substr(a[i], RSTART+9, RLENGTH-10);
        }
    }
    if(tid != "" && gid != "") print tid, gid;
}' "$LOCAL_GTF" > "$MAPPING_FILE" || { echo "Error processing GTF file"; exit 1; }

# Generate kallisto index
echo "Generating kallisto index..."
kallisto index -i "$INDEX_FILE" "$LOCAL_TRANSCRIPTOME" || {
    echo "ERROR: Failed to generate kallisto index"
    exit 1
}

################    UPLOAD TO S3    ################

# Upload references to S3
echo "Uploading reference files to S3..."
aws s3 cp "$MAPPING_FILE" "$S3_MAPPING_FILE" || {
    echo "ERROR: Failed to upload mapping file to S3"
    exit 1
}

aws s3 cp "$INDEX_FILE" "$S3_INDEX_FILE" || {
    echo "ERROR: Failed to upload index to S3"
    exit 1
}

echo "Successfully generated and uploaded reference files to $S3_REF_PATH"
exit 0