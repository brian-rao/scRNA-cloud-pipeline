# Cloud-Based Single-Cell RNA-seq Analysis Pipeline  

## Overview  
This repository contains a **scalable and reproducible pipeline** for **single-cell RNA sequencing (scRNA-seq) analysis**, from **raw FASTQ files to downstream analysis**, built using **Nextflow, AWS, and Docker**. The pipeline automates data processing, allowing efficient, cloud-based execution for large-scale studies.  

## Features  
- **Fully Automated Workflow:** Uses Nextflow to orchestrate each step.  
- **Cloud Scalability:** Deploys on AWS with compute resource optimization.  
- **Reproducibility:** Containerized with Docker for consistent execution.  
- **Efficient Read Processing:**  
  - **FastQC**: Quality control of raw sequencing reads.  
  - **Kallisto + Bustools**: Pseudoalignment and quantification of scRNA-seq reads.  
  - **Scanpy**: Clustering, differential expression analysis, and visualization.  
- **Modular Design:** Easily extendable for additional preprocessing or analysis steps.  

## Installation  
### **Prerequisites**  
Ensure the following are installed:  
- **[Nextflow](https://www.nextflow.io/)**  
- **[Docker](https://www.docker.com/)**   
- **[AWS CLI](https://aws.amazon.com/cli/)** (if deploying in the cloud)  

### **Clone the Repository**  
```bash
git clone https://github.com/brian-rap/scRNAseq-pipeline.git
cd scRNAseq-pipeline