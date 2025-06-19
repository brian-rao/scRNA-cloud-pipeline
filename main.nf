#!/usr/bin/env nextflow
// Log parameters
// These parameters are defined in your 'nextflow.config' file
log.info """\
    RNA-SEQ PIPELINE WITH REFERENCE BUILDING
    =======================================
    reads           : ${params.reads} (matches both .fastq & .fastq.gz)
    outdir          : ${params.outdir}
    qc_script       : ${params.qc_script}
    build_ref_script: ${params.build_ref_script}
    quant_script    : ${params.quant_script}
    s3_bucket       : ${params.s3_bucket}
    gencode_version : ${params.gencode_version}
    batch_queue     : ${params.batch_queue}
    aws_region      : ${params.aws_region}
    job_role        : ${params.job_role}
    ref_cpus        : ${params.ref_cpus}
    ref_memory      : ${params.ref_memory}
    qc_threads      : ${params.qc_threads}
    qc_memory       : ${params.qc_memory}
    quant_threads   : ${params.quant_threads}
    quant_memory    : ${params.quant_memory}
    container_qc    : ${params.container_qc}
    container_quant : ${params.container_quant}
    """.stripIndent()



log.info "Nextflow attempting to match reads with pattern: ${params.reads}" // <-- ADD THIS LINE

// Define the input channel from S3 reads - matches both .fastq and .fastq.gz
//Channel
//    .fromFilePairs(params.reads) //, checkIfExists: true)
//    .ifEmpty { error "Cannot find any reads matching: ${params.reads}" }
//    .view { sample_id, files -> "Found sample: $sample_id with files: $files" }
//    .set { read_pairs_ch }


// --- TEMPORARY DIAGNOSTIC TEST ---
// Change params.reads to a very broad pattern
params.reads = "s3://scrna-pipeline-data/reads/*.fastq"

// Define the input channel from S3 reads - matches both .fastq and .fastq.gz
// Using fromFilePairs to correctly group R1/R2 reads
Channel
    .fromFilePairs(params.reads, checkIfExists: true) // Rely on nextflow.config for params.reads value
    .ifEmpty { error "Cannot find any reads matching: ${params.reads}" }
    .view { sample_id, files -> "Found sample: $sample_id with files: $files" }
    .set { read_pairs_ch }

// Process to build references (e.g., Kallisto index)
process BUILD_REFERENCES {
    tag "build_references"
    // Publish results to a specific subdirectory in the output directory
    publishDir "${params.outdir}/references", mode: 'copy'

    // Resource requirements for this process, pulled from params in nextflow.config
    cpus params.ref_cpus
    memory params.ref_memory

    // Docker container image to use for this process, pulled from params
    container params.container_quant

    output:
    // A flag file to indicate successful reference build, used for dependency tracking
    path "reference_complete.flag", emit: ref_flag

    script:
    """
    # Execute the reference building script
    # -b: S3 bucket for reference data
    # -v: Gencode version
    # -f: Force flag (ensures re-build if necessary)
    bash ${params.build_ref_script} \\
        -b ${params.s3_bucket} \\
        -v ${params.gencode_version}
        #-f

    # Create the completion flag file
    echo "References built successfully at \$(date)" > reference_complete.flag
    """
}

// Process to download built references into the compute environment
process DOWNLOAD_REFERENCES {
    tag "download_references"

    // Lighter resource requirements for downloading, hardcoded as not parameterized in config
    cpus 2
    memory "8g"

    // Docker container image to use for this process
    container params.container_quant

    input:
    // Depends on the completion flag from BUILD_REFERENCES
    path ref_flag

    output:
    // Output all files within the 'references' directory
    path "references/*", emit: ref_files

    script:
    """
    # Create a directory to store the downloaded references
    mkdir -p references
    # Sync the built references from S3 to the local 'references' directory
    aws s3 sync ${params.s3_bucket}/kallisto_reference/ references/

    # Verify that crucial reference files exist after download
    if [[ ! -f references/kallisto_index.idx ]] || [[ ! -f references/transcript_to_gene.txt ]]; then
        echo "ERROR: Required reference files not found after download"
        exit 1
    fi

    echo "Successfully downloaded reference files:"
    ls -la references/
    """
}

// Process to run Quality Control (QC) on raw sequencing reads
process runQC {
    tag "$sample_id"
    // Publish QC results to a sample-specific subdirectory
    publishDir "${params.outdir}/qc_results/${sample_id}", mode: 'copy'

    // Resource requirements for QC, pulled from params
    cpus params.qc_threads
    memory params.qc_memory

    // Docker container image for QC
    container params.container_qc

    input:
    // Tuple containing sample ID and the corresponding read pairs (R1, R2)
    // Nextflow's path type automatically handles staging of files.
    tuple val(sample_id), path(reads)

    output:
    // Output QC results in a sample-specific directory.
    // Nextflow expects the output files to be directly within this directory:
    // e.g., 'test1_output/test1_R1_fastqc.html', 'test1_output/test1_R2_fastqc.zip'
    tuple val(sample_id), path("${sample_id}_output/*"), emit: qc_results

    script:
    """
    # Create a 'reads' directory for symbolic linking.
    # This directory will hold the input FASTQ files for the bash script.
    mkdir -p reads/

    # Create symbolic links to the input read files.
    # Nextflow stages input files into the process's work directory.
    # We use \$(readlink -f ...) to get the absolute path of the staged files,
    # and then symlink them into 'reads/' with their original filenames.
    ln -s \$(readlink -f ${reads[0]}) reads/${reads[0].name}
    ln -s \$(readlink -f ${reads[1]}) reads/${reads[1].name}

    # Export sample ID as an environment variable for the bash script.
    # (Although run_qc_reads.sh also extracts sample_name, this ensures consistency)
    export sample_name="${sample_id}"

    # Run the QC bash script.
    # As per run_qc_reads.sh, it will output to: reads_qc/${sample_id}_output/fastqc/
    bash ${params.qc_script} -i reads/ -o reads_qc/

    # --- IMPORTANT FIX: Move outputs to the directory Nextflow expects ---
    # The run_qc_reads.sh script creates a nested directory structure:
    #   reads_qc/
    #   └── {sample_id}_output/
    #       └── fastqc/
    #           ├── {sample_id}_R1_fastqc.html
    #           └── {sample_id}_R1_fastqc.zip
    #           └── {sample_id}_R2_fastqc.html
    #           └── {sample_id}_R2_fastqc.zip
    #
    # Nextflow's 'output' declaration `path("${sample_id}_output/*")` expects:
    #   {sample_id}_output/
    #   ├── {sample_id}_R1_fastqc.html
    #   └── {sample_id}_R1_fastqc.zip
    #   └── {sample_id}_R2_fastqc.html
    #   └── {sample_id}_R2_fastqc.zip

    # Define the actual output directory created by the run_qc_reads.sh script.
    ACTUAL_SCRIPT_OUTPUT_DIR="reads_qc/${sample_id}_output/fastqc"

    # Define the directory Nextflow expects as its output for this process.
    EXPECTED_NEXTFLOW_OUTPUT_DIR="${sample_id}_output"

    # Check if the script successfully created its intended output directory.
    if [ -d "\$ACTUAL_SCRIPT_OUTPUT_DIR" ]; then
        echo "Found FastQC output from script in: \$ACTUAL_SCRIPT_OUTPUT_DIR"
        # Create the target directory that Nextflow expects.
        mkdir -p "\$EXPECTED_NEXTFLOW_OUTPUT_DIR"
        # Move all contents (files and subdirectories) from the script's output
        # directory to Nextflow's expected output directory.
        mv "\$ACTUAL_SCRIPT_OUTPUT_DIR"/* "\$EXPECTED_NEXTFLOW_OUTPUT_DIR"/
        echo "Successfully moved FastQC outputs to: \$EXPECTED_NEXTFLOW_OUTPUT_DIR"
    else
        # If the script's output directory is not found, it means the script
        # failed to produce the expected results. We should exit with an error.
        echo "ERROR: Expected FastQC output directory from run_qc_reads.sh not found."
        echo "       Checked for: \$ACTUAL_SCRIPT_OUTPUT_DIR"
        echo "       Please review run_qc_reads.sh for errors."
        exit 1 # Terminate the Nextflow process gracefully with an error
    fi
    # --- END IMPORTANT FIX ---

    # The previous complex if/else block to handle missing/alternate output
    # locations is now removed as it was masking the real issue.
    # The new 'mv' logic ensures that if the script's output is not as expected,
    # the process will fail clearly.
    """
}


// Process for gene quantification (e.g., using Kallisto)
process QUANTIFY_GENES {
    tag "$sample_id"
    // Publish quantification results to a sample-specific subdirectory
    publishDir "${params.outdir}/quantification/${sample_id}", mode: 'copy'

    // Resource requirements for quantification, pulled from params
    cpus params.quant_threads
    memory params.quant_memory

    // Docker container image for quantification
    container params.container_quant

    input:
    // Input read pairs for quantification (from `runQC` process)
    tuple val(sample_id), path(reads)
    // Dependency: Receive the flag that references are built and available on S3.
    // The quantification script itself will handle downloading them.
    path ref_completion_flag // Name changed for clarity (it's the ref_flag)
    // Explicitly stage the quantification script into the container's work directory
    path "${params.quant_script}" // Assuming `params.quant_script` is defined in your config

    output:
    // Output quantification counts in a sample-specific directory
    tuple val(sample_id), path("${sample_id}_counts/*"), emit: counts

    script:
    """
    # Create a 'reads' directory and link input files
    # Nextflow stages 'reads' into the work directory.
    # We create symlinks into a 'reads/' subdirectory, preserving original filenames.
    mkdir -p reads/
    ln -s \$(readlink -f ${reads[0]}) reads/${reads[0].name}
    ln -s \$(readlink -f ${reads[1]}) reads/${reads[1].name}

    # Set sample name as an environment variable for the quantification script
    export sample_name="${sample_id}"

    # Run the quantification script, passing the S3 bucket as an argument.
    # NOTE: Your run_quantification.sh script is responsible for downloading
    # the references from S3 into its own local work directory.
    bash ${params.quant_script} -b ${params.s3_bucket}

    # Handle output from the quantification script (expected in output/sample_id/counts)
    # Define the actual output directory created by the script within the container
    QUANT_SCRIPT_OUTPUT_DIR="output/${sample_id}/counts"
    # Define the final output directory name Nextflow expects for staging
    EXPECTED_NEXTFLOW_OUTPUT_DIR="${sample_id}_counts"

    # Check if the script's output directory exists and move its contents
    if [ -d "\$QUANT_SCRIPT_OUTPUT_DIR" ]; then
        echo "Found quantification output in: \$QUANT_SCRIPT_OUTPUT_DIR"
        mkdir -p "\$EXPECTED_NEXTFLOW_OUTPUT_DIR"
        # Move all contents (files and subdirectories) to Nextflow's expected output directory
        mv "\$QUANT_SCRIPT_OUTPUT_DIR"/* "\$EXPECTED_NEXTFLOW_OUTPUT_DIR"/
        echo "Successfully moved quantification outputs to: \$EXPECTED_NEXTFLOW_OUTPUT_DIR"
    else
        # If the script's output directory is not found, something went wrong with the script.
        echo "ERROR: Expected quantification output directory not found: \$QUANT_SCRIPT_OUTPUT_DIR"
        exit 1 # Fail the Nextflow process if expected outputs are not produced
    fi
    """
}


// Define the overall workflow of the pipeline
workflow {
    // Step 1: Build references. This process runs independently at the start.
    // It outputs a completion flag indicating references are on S3.
    BUILD_REFERENCES()

    // Step 2: Download references. This process is now only used for processes
    // that explicitly need to stage the references locally.
    // If QUANTIFY_GENES downloads its own, this might be redundant for that branch,
    // but the workflow structure requires it to be defined if it's a process.
    DOWNLOAD_REFERENCES(BUILD_REFERENCES.out.ref_flag)

    // Step 3: Run QC on all read pairs. This process runs in parallel for each sample.
    runQC(read_pairs_ch)

    // Step 4: Run gene quantification. This process runs in parallel for each sample.
    // It depends on:
    // a) The processed read pairs (from runQC)
    // b) The completion flag from BUILD_REFERENCES (signaling references are on S3)
    // c) The quantification script itself
    QUANTIFY_GENES(
        runQC.out.qc_results, // Passes tuple: (sample_id, reads)
        BUILD_REFERENCES.out.ref_flag.collect(), // Passes the collected reference completion flag
        file(params.quant_script) // Passes the quantification script file
    )

    // Print messages upon completion of each major workflow step
    BUILD_REFERENCES.out.ref_flag.view { "✅ References built successfully" }
    // The DOWNLOAD_REFERENCES process might not have a direct view if its output isn't explicitly used downstream,
    // but its completion is a prerequisite for QUANTIFY_GENES (if it consumes its output).
    // If DOWNLOAD_REFERENCES's output (downloaded_references) isn't used by other processes that don't download their own,
    // this view might be redundant for the current pipeline logic.
    DOWNLOAD_REFERENCES.out.downloaded_references.view { "✅ References downloaded and ready for downstream processes" }
    runQC.out.qc_results.view { sample_id, files -> "✅ QC completed for $sample_id" }
    QUANTIFY_GENES.out.counts.view { sample_id, files -> "✅ Gene quantification completed for $sample_id" }
}

// Workflow completion handler (uncomment to activate)
// This block executes once the entire pipeline finishes, providing a summary.
//workflow.onComplete {
//  log.info """
//    Pipeline execution summary
//    ---------------------------
//    Completed at: ${workflow.complete}
//    Duration    : ${workflow.duration}
//    Success     : ${workflow.success}
//    workDir     : ${workflow.workDir}
//    exit status : ${workflow.exitStatus}
//    """
//}
