#!/usr/bin/env bash

SCRIPT_PATH=$(
  cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
  pwd -P
)

readonly VALID_TASKS=("all db_setup db tools tools_setup ref")

function join_by { local IFS="$1"; shift; echo "$*"; }

function usage() {
  echo "usage: setup -t task"
  echo "  -t  task            specify task: $(join_by ' ' ${VALID_TASKS})"
  echo "  -h                  show this help screen"
  exit 1
}

while getopts d:t:ph option; do
  case "${option}" in
  d) readonly PARAM_DIR_PATIENT=$OPTARG ;;
  t) PARAM_TASK=$OPTARG ;;
  h) usage ;;
  \?)
    echo "Unknown option: -$OPTARG" >&2
    exit 1
    ;;
  :)
    echo "Missing option argument for -$OPTARG" >&2
    exit 1
    ;;
  *)
    echo "Unimplemented option: -$OPTARG" >&2
    exit 1
    ;;
  esac
done

# if no patient is defined
if [[ -z "${PARAM_TASK}" ]]; then
  PARAM_TASK='all'
fi



if [[ ! " ${VALID_TASKS[@]} " =~ " ${PARAM_TASK} " ]]; then
  echo "unknown task: ${PARAM_TASK}"
  echo "use one of the following values: $(join_by ' ' ${VALID_TASKS})"
  exit 1
fi

# TODO: flag install specific components: db, tools, example

DIR_TOOLS="${SCRIPT_PATH}/tools"
DIR_DATABASES="${SCRIPT_PATH}/databases"
DIR_REF="${SCRIPT_PATH}/references"


# REF
######################################################################################
function setup_references() {
  # Genome UCSC
  wget ftp://igenome:G3nom3s4u@ussd-ftp.illumina.com/Homo_sapiens/UCSC/hg19/Homo_sapiens_UCSC_hg19.tar.gz
  tar -xzf Homo_sapiens_UCSC_hg19.tar.gz -C references
  rm -f Homo_sapiens_UCSC_hg19.tar.gz

  # ControlFREEC MappabilityFile
  wget https://xfer.curie.fr/get/nil/7hZIk1C63h0/hg19_len100bp.tar.gz
  tar -xzf hg19_len100bp.tar.gz -C references

  # Chromosome length for hg19
  wget http://bioinfo-out.curie.fr/projects/freec/src/hg19.len -O reference/Homo_sapiens/UCSC/hg19/Sequence/Chromosomes/hg19.len
}



# TOOLS
######################################################################################
version_GATK="3.8-1-0-gf15c1c3ef"

########
# GATK #
########
function install_tool_gatk() {
  echo "installing tool gatk"
  cd "${DIR_TOOLS}" || exit 1

  echo "fetching gatk"
  # download new version
  wget "https://software.broadinstitute.org/gatk/download/auth?package=GATK-archive&version=${version_GATK}" \
      -O gatk.tar.bz2

  # unpack
  tar xjf gatk.tar.bz2
  rm -f gatk.tar.bz2

  # rename folder and file (neglect version information)
  mv GenomeAnalysisTK*/* gatk/
  rm -rf GenomeAnalysisTK*

  echo "done"
}



###########
# annovar #
###########
function install_tool_annovar() {
  echo "installing tool annovar"

  cd "${DIR_TOOLS}" || exit 1

  echo "please visit http://download.openbioinformatics.org/annovar_download_form.php to get the download link for annovar via an email"
  echo "enter annovar download link:"
  read -r url_annovar

  echo "fetching annovar"
  wget "${url_annovar}" \
      -O annovar.tar.gz

  # unpack
  tar -xzf annovar.tar.gz
  rm -f annovar.tar.gz

  cd annovar

  echo "done"
}

function setup_tool_annovar() {
  echo "setup tool annovar"
  echo "download databases"

  cd "${DIR_TOOLS}/annovar" || exit 1

  # Download proposed databases directly from ANNOVAR
  ./annotate_variation.pl -buildver hg19 -downdb -webfrom annovar refGene humandb/
  ./annotate_variation.pl -buildver hg19 -downdb -webfrom annovar dbnsfp35a humandb/
  ./annotate_variation.pl -buildver hg19 -downdb -webfrom annovar gnomad_exome humandb/
  ./annotate_variation.pl -buildver hg19 -downdb -webfrom annovar exac03 humandb/
  ./annotate_variation.pl -buildver hg19 -downdb -webfrom annovar esp6500siv2_ea humandb/
  ./annotate_variation.pl -buildver hg19 -downdb -webfrom annovar 1000g2015aug humandb/
  ./annotate_variation.pl -buildver hg19 -downdb -webfrom annovar avsnp150 humandb/
  ./annotate_variation.pl -buildver hg19 -downdb -webfrom annovar clinvar_20180603 humandb/
  ./annotate_variation.pl -buildver hg19 -downdb -webfrom annovar intervar_20180118 humandb/

  echo "done"
}

# databases
######################################################################################
function install_databases() {
  echo "installing databases"

  cd "${DIR_DATABASES}" || exit 1

  # dbSNP
  wget ftp://ftp.ncbi.nlm.nih.gov/snp/organisms/human_9606_b150_GRCh37p13/VCF/All_20170710.vcf.gz -O "${DIR_REF}/snp150hg19.vcf.gz"
  wget ftp://ftp.ncbi.nlm.nih.gov/snp/organisms/human_9606_b150_GRCh37p13/VCF/All_20170710.vcf.gz.tbi -O "${DIR_REF}/snp150hg19.vcf.gz.tbi"

  # CancerGenes
  wget https://github.com/oncokb/oncokb-public/blob/master/data/v1.15/CancerGenesList.txt

  # Cancer Hotspots
  wget http://www.cancerhotspots.org/files/hotspots_v2.xls

  # DGIdb
  wget http://www.dgidb.org/data/interactions.tsv -O DGIdb_interactions.tsv

  # Actionable alterations
  wget https://oncokb.org/api/v1/utils/allActionableVariants.txt

  echo "done"
}

function setup_databases() {
  echo "setup databases"

  BIN_RSCRIPT=$(which Rscript)
  if [[ -z "${BIN_RSCRIPT}" ]]; then
    echo "Rscript needs to be available and in PATH in order to install the databases"
    exit 1
  fi

  ## R Code for processing
  ${BIN_RSCRIPT} --vanilla -<<EOF
library(GSA)
gmt <- GSA.read.gmt('h.all.v7.0.entrez.gmt')
genesets <- gmt$genesets
names <- data.frame(Names = gmt$geneset.names, Descriptions = gmt$geneset.descriptions)
names(genesets) <- names$Names
hallmark <- genesets
save(hallmarksOfCancer, file = "hallmarksOfCancer_GeneSets.Rdata")
EOF

  rm -f h.all.v7.0.entrez.gmt

  echo "done"
}

case "${PARAM_TASK}" in
  "tools") 
    install_tool_gatk
    install_tool_annovar
  ;;

  "db") 
    install_databases
  ;;

  *) 
    install_tool_gatk
    install_tool_annovar

    install_databases
  ;;
esac