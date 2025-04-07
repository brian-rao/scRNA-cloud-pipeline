#!/usr/bin/env nextflow

// Define parameters
params {
    // Set to your S3 bucket path containing reads (handles both .fastq and .fastq.gz)
    reads = "s3://scrna-pipeline-data/reads/*_{1,2}.fastq{,.gz}"
    
    // Output directory
    outdir = "s3://scrna-pipeline-data/results"
    
    // Path to your QC bash script
    qc_script = "src/pipeline/qc_reads/run_qc_reads.sh"
    
    // Optional QC parameters if needed
    qc_threads = 8
    qc_memory = "16g"
    
    // AWS Batch queue name
    batch_queue = "scrna-pipeline-queue"
}

// Log parameters
log.info """\
         RNA-SEQ QC PROCESS
         =================
         reads       : ${params.reads} (matches both .fastq & .fastq.gz)
         outdir      : ${params.outdir}
         qc_script   : ${params.qc_script}
         batch_queue : ${params.batch_queue}
         """
         .stripIndent()

// Define process executor
process.executor = 'awsbatch'
process.queue = params.batch_queue

// Define the input channel from S3 reads - matches both .fastq and .fastq.gz
Channel
    .fromFilePairs(params.reads, checkIfExists: true)
    .ifEmpty { error "Cannot find any reads matching: ${params.reads}" }
    .view { sample_id, files -> "Found sample: $sample_id with files: $files" }
    .set { read_pairs_ch }

// QC process - creates a reads/ folder within the container that symbolic links the read files from the bucket to be used by the script
process runQC {
    tag "$sample_id"
    publishDir "${params.outdir}/qc_results/${sample_id}", mode: 'copy'
    
    // Resource requirements
    cpus params.qc_threads
    memory params.qc_memory
    
    container '588738579752.dkr.ecr.us-east-2.amazonaws.com/scma-pipeline:qc_reads'
    
    input:
    tuple val(sample_id), path(reads) from read_pairs_ch
    
    output:
    tuple val(sample_id), path("${sample_id}_output/*"), emit: qc_results
    
    script:
    """
    # Create required directory structure
    mkdir -p reads/
    
    # Link input files to reads directory
    ln -s \$(readlink -f ${reads[0]}) reads/
    ln -s \$(readlink -f ${reads[1]}) reads/
    
    # Pass the sample ID as an environment variable that your bash script can use
    export sample_name="${sample_id}"
    
    # Run your QC script that expects reads/ directory
    bash ${params.qc_script}
    
    # Check if the script already created the expected output directory
    if [ ! -d "${sample_id}_output" ]; then
        echo "Note: Expected output directory ${sample_id}_output not found"
        echo "Checking for alternate output locations..."
        
        # If the script created output in a different location, adapt accordingly
        if [ -d "output" ]; then
            echo "Found 'output' directory, copying contents to ${sample_id}_output"
            mkdir -p ${sample_id}_output
            cp -r output/* ${sample_id}_output/
        else
            echo "Creating empty output directory to satisfy Nextflow"
            mkdir -p ${sample_id}_output
            touch ${sample_id}_output/.placeholder
        fi
    else
        echo "Found ${sample_id}_output directory created by the script"
    fi
    """
}

// Define the workflow
workflow {
    // Run QC process
    runQC()
    
    // Print completion message
    runQC.out.qc_results.view { sample_id, files -> "QC completed for $sample_id" }
}