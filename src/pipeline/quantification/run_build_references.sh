#!/bin/bash
# Stop on error and show executed commands for debugging
set -euxo pipefail

SCRIPT_DIR="$(dirname "$0")"

################    HELP MESSAGE    ################
usage() {
    echo "Usage: $0 [-b s3_bucket] [-v gencode_version] [-f] [-h]"
    echo
    echo "Options:"
    echo "    -b    S3 bucket URL (required, e.g. s3://mybucket)"
    echo "    -v    GENCODE version (default: 44)"
    echo "    -f    Force rebuild (skip S3 existence check)"
    echo "    -h    Display this help message"
    echo
    # Removed .env specific instructions from help message as credentials are handled by IAM
    exit 1
}

################    INPUT HANDLING    ################

# Removed .env file loading.
# Removed echo statements related to .env as they were misleading.

# Load .env file if it exists - aws container working dir app/, commpent out to let AWS handle via IAM
#ENV_FILE="/app/.env"
#echo "Looking for .env file"  # This line is now commented out
#if [ -f "$ENV_FILE" ]; then
#    echo "Found .env file, sourcing it"
#    source "$ENV_FILE"
#    echo "AWS_ACCESS_KEY_ID is set as $AWS_ACCESS_KEY_ID"
#else
#    echo "Could not find $ENV_FILE" # This line is now commented out
#fi




# Default values
GENCODE_VERSION=${GENCODE_VERSION:-44}
FORCE_REBUILD=${FORCE_REBUILD:-false}

# Allow command-line arguments to override .env values
while getopts "b:v:fh" flag; do
    case "${flag}" in
        b) S3_BUCKET=${OPTARG};;
        v) GENCODE_VERSION=${OPTARG};;
        f) FORCE_REBUILD=true;;
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

# --- Temporary Debugging: Check AWS Identity ---
echo "--- AWS CLI Identity Check ---"
aws sts get-caller-identity || {
    echo "ERROR: Failed to get AWS caller identity. This indicates an IAM role or AWS CLI configuration issue."
    exit 1
}
echo "--- End AWS CLI Identity Check ---"
# --- End Temporary Debugging ---

# Removed explicit 'aws configure set' as credentials should be handled by IAM role.

# Test the connection to the S3 bucket using the inherited IAM role
echo "Testing S3 connection to $S3_BUCKET..."
aws s3 ls "$S3_BUCKET" || {
    echo "ERROR: Failed to list S3 bucket contents. Check S3 bucket name and IAM permissions."
    exit 1
}
echo "S3 connection test successful."

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

################    CHECK EXISTING FILES (OPTIONAL)    ################

# Only check for existing files if not forcing rebuild
if [ "$FORCE_REBUILD" != "true" ]; then
    echo "Checking for existing reference files in S3..."

    # Check if both index and mapping files exist in S3
    INDEX_EXISTS=false
    MAPPING_EXISTS=false

    if aws s3 ls "$S3_INDEX_FILE" &>/dev/null; then
        INDEX_EXISTS=true
        echo "Index file exists in S3: $S3_INDEX_FILE"
    else
        echo "Index file not found in bucket"
    fi

    if aws s3 ls "$S3_MAPPING_FILE" &>/dev/null; then
        MAPPING_EXISTS=true
        echo "Mapping file exists in S3: $S3_MAPPING_FILE"
    else
        echo "Mapping file not found in bucket"
    fi

    # If both files exist, exit (for standalone use)
    if [ "$INDEX_EXISTS" = true ] && [ "$MAPPING_EXISTS" = true ]; then
        echo "Both index and mapping files already exist in S3. Use -f to force rebuild."
        exit 0
    fi
fi

echo "Building reference files..."

################    DOWNLOAD REFERENCE DATA    ################

# Download transcriptome from GENCODE
echo "Downloading transcriptome from GENCODE v${GENCODE_VERSION}..."
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
echo "Downloading GTF annotation from GENCODE v${GENCODE_VERSION}..."
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
        gsub(/^ +/,"",a[i]);   # Trim leading spaces
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
}' "$LOCAL_GTF" > "$MAPPING_FILE" || {
    echo "ERROR: Failed to process GTF file";
    exit 1;
}

# Validate mapping file was created successfully
if [[ ! -s "$MAPPING_FILE" ]]; then
    echo "ERROR: Transcript-to-gene mapping file is empty or was not created"
    exit 1
fi

echo "Generated $(wc -l < "$MAPPING_FILE") transcript-to-gene mappings"

# Generate kallisto index
echo "Generating kallisto index..."
kallisto index -i "$INDEX_FILE" "$LOCAL_TRANSCRIPTOME" || {
    echo "ERROR: Failed to generate kallisto index"
    exit 1
}

# Validate index file was created
if [[ ! -f "$INDEX_FILE" ]]; then
    echo "ERROR: Kallisto index file was not created"
    exit 1
fi

echo "Successfully generated kallisto index: $(ls -lh "$INDEX_FILE" | awk '{print $5}')"

################    UPLOAD TO S3    ################

# Upload references to S3
echo "Uploading reference files to S3..."

# Upload mapping file
aws s3 cp "$MAPPING_FILE" "$S3_MAPPING_FILE" || {
    echo "ERROR: Failed to upload mapping file to S3"
    exit 1
}
echo "Uploaded mapping file to: $S3_MAPPING_FILE"

# Upload index file
aws s3 cp "$INDEX_FILE" "$S3_INDEX_FILE" || {
    echo "ERROR: Failed to upload index to S3"
    exit 1
}
echo "Uploaded index file to: $S3_INDEX_FILE"

# Verify uploads
echo "Verifying S3 uploads..."
aws s3 ls "$S3_REF_PATH/" --human-readable || {
    echo "ERROR: Failed to verify S3 uploads. Check S3 bucket permissions."
    exit 1
}

echo "✅ Successfully generated and uploaded reference files to $S3_REF_PATH"
echo "Files created:"
echo "    - Kallisto index: $S3_INDEX_FILE"
echo "    - Transcript mapping: $S3_MAPPING_FILE"

exit 0