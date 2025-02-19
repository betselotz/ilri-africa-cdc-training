#!/usr/bin/env bash

## sign in to compute06
interactive -w compute06 -c 8 -J metagen -p batch


## Step 1
## Preparing the project directory:
mkdir -p ilri-africa-cdc-training/viralMetagen/{data,scripts}
cd ilri-africa-cdc-training/viralMetagen/
mkdir -p ./data/{database,fastq,fastqc,fastp,centrifuge,kraken,spades,quast,bowtie,krona,ivar,samtools,snpeff}

## Downloading data from SRA matich the SRA039136 
## Data from this project: Open-Source Genomic Analysis of Shiga-Toxin–Producing E. coli O104:H4 (https://www.nejm.org/doi/full/10.1056/NEJMoa1107643)
wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR231/059/SRR23143759/SRR23143759_1.fastq.gz -P ./data/fastq
wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR231/059/SRR23143759/SRR23143759_2.fastq.gz -P ./data/fastq

### Setting variables for in put
##PROJDIR=$PWD
##FASTQDIR=$PWD/data/fastq/
#SAMPLEID=sample01
#

## Step 2
### Loading Modules:
module load fastqc/0.11.9
module load fastp/0.22.0
module load krona/2.8.1
module load centrifuge/1.0.4
module load kraken/2.1.2
module load spades/3.15
module load quast/5.0.2
module load samtools/1.15.1
module load bowtie2/2.5.0
module load bedtools/2.29.0
module load snpeff/4.1g
module load bcftools/1.13

## Step 3
### Copying the data fastq and databases
cp /var/scratch/global/gkibet/ilri-africa-cdc-training/viralMetagen/data/fastq/sample01_R* ./data/fastq/
cp /var/scratch/global/gkibet/ilri-africa-cdc-training/viralMetagen/data/database/ ./data/databse

## Step 4
### Assessing Read Quality using fastqc before quality trimming
fastqc -t 4 \
	-o ./data/fastqc/ \
	./data/fastq/sample01_R1.fastq.gz \
	./data/fastq/sample01_R2.fastq.gz

## Copying files to local laptop --- Run this command on your laptop not HPC
# scp username@hpc.ilri.cgiar.org:~/ilri-africa-cdc-training/viralMetagen/data/fastqc/*.html ./

## Step 5
### Quality Trimming fastq files with fastp and Trims adapter sequences
fastp --in1 ./data/fastq/sample01_R1.fastq.gz \
	--in2 ./data/fastq/sample01_R2.fastq.gz \
	--out1 ./data/fastp/sample01_R1.trim.fastq.gz \
	--out2 ./data/fastp/sample01_R2.trim.fastq.gz \
	--json ./data/fastp/sample01.fastp.json \
	--html ./data/fastp/sample01.fastp.html \
	--failed_out ./data/fastp/sample01_fail.fastq.gz \
	--thread 10 \
	--detect_adapter_for_pe \
	--qualified_quality_phred 20 \
	--cut_mean_quality 20 \
	--length_required 15 \
	2> ./data/fastp/sample01.fastp.log

## Step 6
#filtering Host genome seqiuences 
kraken2 -db ./data/database/host_db/kraken2_human_db \
	--threads 4 \
	--unclassified-out ./data/kraken/sample01.unclassified#.fastq \
	--classified-out ./data/kraken/sample01.classified#.fastq \
	--report ./data/kraken/sample01.kraken2.report.txt \
	--output ./data/kraken/sample01.kraken2.out \
	--gzip-compressed \
	--report-zero-counts \
	--paired ./data/fastp/sample01_R1.trim.fastq.gz \
	./data/fastp/sample01_R2.trim.fastq.gz

## Step 7
### Assessing Read Quality after quality trimming
#
fastqc -t 4 \
	-o ./data/fastqc/ \
	./data/fastp/sample01_R1.trim.fastq.gz \
	./data/fastp/sample01_R2.trim.fastq.gz

## Copying files to local laptop --- Run this command on your laptop not HPC
# scp username@hpc.ilri.cgiar.org:~/ilri-africa-cdc-training/viralMetagen/data/fastqc/*.html ./

## Step 8
## Taxonomic Classification of Reads

mkdir data/database/centrifuge/
cd data/database/centrifuge/
# Build Database:
# apptainer pull docker://quay.io/biocontainers/centrifuge:1.0.4_beta--he513fc3_5

## Alterantive 01
# Download NCBI Taxonomy to ./taxonomy/
centrifuge-download -o taxonomy taxonomy
# Download All complete archaea,bacteria,viral to ./library/
# Downloads from ftp://ftp.ncbi.nlm.nih.gov/genomes/refseq availabble domains are: archaea,bacteria,viral,plasmid,fungi,vertebrate_mammalian,vertebrate_other,protozoa,plasmid,plant,metagenomes,mitochondrion,invertebrate,...
centrifuge-download -o library \
	-m \
	-d "archaea,bacteria,viral,plasmid,fungi" refseq > seqid2taxid.map

## Alternative 02
# Prepare a database - Preffered alternative
wget https://zenodo.org/record/3732127/files/h+p+v+c.tar.gz?download=1
tar -xvzf hpvc.tar.gz 
cd ../../../

## Step 9
# Classification
centrifuge -x ./data/database/centrifuge/hpvc \
	-1 ./data/fastp/sample01_R1.trim.fastq.gz \
	-2 ./data/fastp/sample01_R2.trim.fastq.gz \
	--report-file ./data/centrifuge/sample01-report.txt \
	-S ./data/centrifuge/sample01-results.txt \
	-p 8 \
	--mm 100GB

## Step 10
#Convert centrifuge report to kraken-like report
centrifuge-kreport -x ./data/database/hpvc \
	./data/centrifuge/sample01-results.txt > ./data/centrifuge/sample01-kreport.txt

#Visualization of the taxonomic report using krona
# Load module

## Step 11
## Visualizing the classification report
#Preparing the classification data
cat ./data/centrifuge/sample01-results.txt | cut -f 1,3 > ./data/centrifuge/sample01-results.krona
#Build krona db
mkdir ./data/database/krona
apptainer run scripts/singularity/krona_2.7.1--pl526_5.sif \
	ktUpdateTaxonomy.sh ./data/database/krona/taxonomy

#Visiualize the report - create a HTML file
apptainer run scripts/singularity/krona_2.7.1--pl526_5.sif \
	ktImportTaxonomy -tax ./data/database/krona/taxonomy \
	-o ./data/centrifuge/sample01-results.html \
	./data/centrifuge/sample01-results.krona > ./data/centrifuge/sample01-results.html

## Step 12
### Filter Host Genome in preparation for genome assembly

mkdir ./data/database/host_db
cd ./data/database/host_db
## Alteranive 01
## Build host genome database
# Download genome (human)
kraken2-build --download-library human \
	--db ./ \
	--threads 4
# Downloading NCBI tax
kraken2-build --download-taxonomy \
	--db ./
# Build database
kraken2-build --build \
	--db ./ \
       	--threads 4
# Removing intermediate files to save space
kraken2-build --clean \
	--db ./

## Alternative 02 - Download prebuilt database
curl -L -o ./kraken2_human_db.tar.gz https://ndownloader.figshare.com/files/23567780
tar -xzvf kraken2_human_db.tar.gz
cd ../../../

## ## Notes
## ### Denovo Genome Assembly using Spades
## spades.py -k 27 \
## 	-1 ./data/kraken/sample01.unclassified_1.fastq \
## 	-2 ./data/kraken/sample01.unclassified_2.fastq \
## 	-o ./data/spades/sample01/ \
## 	-t 8 \
## 	-m 384
## #
## ###Assess the structure of the genome - examine contiguity
## ## Run quast
## quast.py ./data/spades/sample01/contigs.fasta \
## 	-t 8 \
## 	-o ./data/quast/
## 

## Step 13
### Focus on One viral species: H1N1 - Influenza A Virus
# Download Genome from NCBI - Genome database - Reference Genome (Influenza A virus (A/New York/392/2004(H3N2)))
mkdir -p ./data/database/refseq/
wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/865/085/GCF_000865085.1_ViralMultiSegProj15622/GCF_000865085.1_ViralMultiSegProj15622_genomic.fna.gz -P ./data/database/refseq/
wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/865/085/GCF_000865085.1_ViralMultiSegProj15622/GCF_000865085.1_ViralMultiSegProj15622_genomic.gff.gz -P ./data/database/refseq/
gunzip data/database/refseq/*.gz

#Renaming files
mv ./data/database/refseq/GCF_000865085.1_ViralMultiSegProj15622_genomic.fna ./data/database/refseq/influenzaA.fna
mv ././data/database/refseq/GCF_000865085.1_ViralMultiSegProj15622_genomic.gff ./data/database/refseq/influenzaA.gff

## Step 14
## Index reference genome - samtools
samtools faidx \
	./data/database/refseq/influenzaA.fna \
	--fai-idx ./data/database/refseq/influenzaA.fna.fai

## Step 15
## Index reference genome - bowtie
mkdir ./data/database/bowtie/
bowtie2-build \
	--threads 4 \
	./data/database/refseq/influenzaA.fna \
	./data/database/bowtie/influenzaA

## Step 16
## Align reads to reference genome
bowtie2 -x ./data/database/bowtie/influenzaA \
	-1 ./data/kraken/sample01.unclassified_1.fastq \
	-2 ./data/kraken/sample01.unclassified_2.fastq \
	--threads 1 \
	--un-conc-gz ./data/bowtie/sample01.unmapped.fastq.gz \
	--local \
	--very-sensitive-local \
	2> ./data/bowtie/sample01.bowtie2.log \
	| samtools view -@ 1 -F4 -bhS -o ./data/bowtie/sample01.trim.dec.bam -

## Step 17
## Sort and Index aligment map
samtools sort -@ 4 \
	-o ./data/bowtie/sample01.sorted.bam \
	-T ./data/bowtie/sample01 \
	./data/bowtie/sample01.trim.dec.bam

samtools index -@ 4 ./data/bowtie/sample01.sorted.bam

## Step 18
## Coverage computation
bedtools genomecov \
	-d \
	-ibam ./data/bowtie/sample01.sorted.bam \
	> ./data/bowtie/sample01.coverage

## Step 19
## Plot Genome coverage in R
Rscript ./scripts/plotGenomecov.R ./data/bowtie/sample01.coverage

## Step 20
## Consensus Genome construsction
# For segmented viruses e.g Influenza A ivar consensus is unable to analyse more than one reference (segment/cromosome) name at once. We need to split by reference:
bamtools split -in data/bowtie/sample01.sorted.bam \
	-refPrefix "REF_" \
	-reference
#Renameing output files
rename 'sorted.REF' 'REF' ./data/bowtie/*

## Step 21
## Loop through segmented BAM files and generate consensus:
mkdir -p ./data/ivar/consensus/
for bamFile in $(find ./data/bowtie -name "*.REF_*.bam")
do
	fileName=`basename -- "$bamFile"`
	outName=${fileName%.*}
	samtools mpileup -aa \
		--count-orphans \
		--no-BAQ \
		--max-depth 0 \
		--min-BQ 0 \
		--reference ./data/database/refseq/influenzaA.fna \
		$bamFile \
		--output ./data/samtools/${outName}.mpileup
	
	cat ./data/samtools/${outName}.mpileup | ivar consensus \
		-t 0.75 \
		-q 20 \
		-m 10 \
		-n N \
		-p ./data/ivar/consensus/${outName}.consensus
done

## Step 22
## Loop through seqmented BAM files and conduct Variant Calling from the alignemnts
mkdir -p ./data/ivar/variants/
for bamFile in $(find ./data/bowtie -name "*.REF_*.bam")
do
	fileName=`basename -- "$bamFile"`
	outName=${fileName%.*}
	samtools mpileup --ignore-overlaps \
		--count-orphans \
		--no-BAQ \
		--max-depth 0 \
		--min-BQ 0 \
		--reference ./data/database/refseq/influenzaA.fna \
		$bamFile \
		--output ./data/samtools/${outName}.var.mpileup
	
	cat ./data/samtools/${outName}.var.mpileup | ivar variants \
		-t 0.25 \
		-q 20 \
		-m 10 \
		-g ./data/database/refseq/influenzaA.gff \
		-r ./data/database/refseq/influenzaA.fna \
		-p ./data/ivar/variants/${outName}.variants
done

## Step 23
## Coverting variant files from .tsv to vcf (Variant Call Format) - needed in downstream steps
for varFile in $(find ./data/ivar/variants -name "*.variants.tsv")
do
	fileName=`basename -- "$varFile"`
	outName=${fileName%.*}
	python3 ./scripts/ivar_variants_to_vcf.py \
		$varFile \
		./data/ivar/variants/${outName}.vcf \
		--pass_only \
		--allele_freq_thresh 0.75 > ./data/ivar/variants/${outName}.counts.log

	#Compress
	bgzip -c ./data/ivar/variants/${outName}.vcf > ./data/ivar/variants/${outName}.vcf.gz
	#Create tabix index - Samtools
	tabix -p vcf -f ./data/ivar/variants/${outName}.vcf.gz
	#Generate VCF files
	bcftools stats ./data/ivar/variants/${outName}.vcf.gz > ./data/ivar/variants/${outName}.stats.txt
done

## Step 24
## Annotation of Variants - SnpEff and SnpSift

## How to build a SnpEff Database:
# Building a snpEff Database:

mkdir -p ./data/database/snpEff/H1N1/
cp ./data/database/refseq/influenzaA.gff ./data/database/snpEff/H1N1/genes.gff
cp ./data/database/refseq/influenzaA.fna ./data/database/snpEff/H1N1/sequences.fa
echo -e "# Influenza A virus genome, version influezaA\nH1N1.genome: H1N1" > ./data/database/snpEff/H1N1/snpEff.config
#Alternative 01 - Build
java -Xmx4g -jar /export/apps/snpeff/4.1g/snpEff.jar build \\
	-config ./data/database/snpEff/H1N1/snpEff.config \\
	-dataDir ./../ \\
	-gff3 \\
	-v H1N1

# Alternative 02 - Download Pre-built database:
# Check databases for right target
java -Xmx4g -jar /export/apps/snpeff/4.1g/snpEff.jar databases > viralMetagen/data/database/snpEff/snpeff.databases.txt
# Download target
java -Xmx4g -jar /export/apps/snpeff/4.1g/snpEff.jar download -v <genome_version>

## Annotate the variants VCF file with snpEff
for varFile in $(find ./data/ivar/variants -name "*.vcf.gz")
do
	fileName01=`basename -- "$varFile"`
	fileName=${fileName01%.*}
	outName=${fileName%.*}
	java -Xmx4g -jar /export/apps/snpeff/4.1g/snpEff.jar \
		-config ./data/database/snpEff/H1N1/snpEff.config \
		-dataDir ./../ \
		-v H1N1 ${varFile} > ./data/ivar/variants/${outName}.ann.vcf

	# Rename summary.html and genes.txt
	mv ./snpEff_summary.html ./data/ivar/variants/${outName}.ann.summary.html
	mv ./snpEff_genes.txt ./data/ivar/variants//${outName}.ann.genes.txt
	
	#Compress vcf
	bgzip -c ./data/ivar/variants/${outName}.ann.vcf > ./data/ivar/variants/${outName}.ann.vcf.gz
	#Create tabix index - Samtools
	tabix -p vcf -f ./data/ivar/variants/${outName}.ann.vcf.gz
	#Generate VCF files
	bcftools stats ./data/ivar/variants/${outName}.ann.vcf.gz > ./data/ivar/variants/${outName}.ann.stats.txt
done

## Filter the most significant variants using snpSift
for varFile in $(find ./data/ivar/variants -name "*.ann.vcf.gz")
do
	fileName01=`basename -- "$varFile"`
	fileName=${fileName01%.*}
	outName=${fileName%.*}
	java -Xmx4g -jar /export/apps/snpeff/4.1g/SnpSift.jar \
		extractFields \
		-s "," \
		-e "." \
		${varFile} \
		"ANN[*].GENE" "ANN[*].GENEID" \
		"ANN[*].IMPACT" "ANN[*].EFFECT" \
		"ANN[*].FEATURE" "ANN[*].FEATUREID" \
		"ANN[*].BIOTYPE" "ANN[*].RANK" "ANN[*].HGVS_C" \
		"ANN[*].HGVS_P" "ANN[*].CDNA_POS" "ANN[*].CDNA_LEN" \
		"ANN[*].CDS_POS" "ANN[*].CDS_LEN" "ANN[*].AA_POS" \
		"ANN[*].AA_LEN" "ANN[*].DISTANCE" "EFF[*].EFFECT" \
		"EFF[*].FUNCLASS" "EFF[*].CODON" "EFF[*].AA" "EFF[*].AA_LEN" \
		> ./data/ivar/variants/${outName}.snpsift.txt
done
