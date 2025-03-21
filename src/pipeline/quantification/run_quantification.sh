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
READS_DIR="reads"
KALLISTO_OUTPUT_DIR="kallisto_output"
BUSTOOLS_OUTPUT_DIR="bustools_output"
COUNTS_OUTPUT_DIR="counts"
LOCAL_REF_DIR="$REF_DIR"
S3_REF_PATH="$S3_BUCKET/$REF_DIR"
INDEX_FILE="$LOCAL_REF_DIR/kallisto_index.idx"
MAPPING_FILE="$LOCAL_REF_DIR/transcript_to_gene.txt"
S3_INDEX_FILE="$S3_REF_PATH/kallisto_index.idx"
S3_MAPPING_FILE="$S3_REF_PATH/transcript_to_gene.txt"

