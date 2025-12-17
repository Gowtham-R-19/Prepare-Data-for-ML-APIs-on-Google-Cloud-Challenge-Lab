#!/bin/bash

# ===========================
# Terminal Styling Utilities
# ===========================
CLR_BLACK=$(tput setaf 0)
CLR_RED=$(tput setaf 1)
CLR_GREEN=$(tput setaf 2)
CLR_YELLOW=$(tput setaf 3)
CLR_BLUE=$(tput setaf 4)
CLR_MAGENTA=$(tput setaf 5)
CLR_CYAN=$(tput setaf 6)
CLR_WHITE=$(tput setaf 7)

TXT_BOLD=$(tput bold)
TXT_RESET=$(tput sgr0)

# ===========================
# Welcome Banner
# ===========================
echo "${CLR_CYAN}${TXT_BOLD}"
echo "  ██████╗  ██████╗ ██╗    ██╗████████╗██╗  ██╗ █████╗ ███╗   ███╗"
echo " ██╔════╝ ██╔═══██╗██║    ██║╚══██╔══╝██║  ██║██╔══██╗████╗ ████║"
echo " ██║  ███╗██║   ██║██║ █╗ ██║   ██║   ███████║███████║██╔████╔██║"
echo " ██║   ██║██║   ██║██║███╗██║   ██║   ██╔══██║██╔══██║██║╚██╔╝██║"
echo " ╚██████╔╝╚██████╔╝╚███╔███╔╝   ██║   ██║  ██║██║  ██║██║ ╚═╝ ██║"
echo "  ╚═════╝  ╚═════╝  ╚══╝╚══╝    ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝"
echo "                         Gowtham R"
echo "${TXT_RESET}"

echo "${CLR_YELLOW}${TXT_BOLD}Repository:${TXT_RESET} https://github.com/Gowtham-R-19/Prepare-Data-for-ML-APIs-on-Google-Cloud-Challenge-Lab"
echo
echo "${CLR_GREEN}${TXT_BOLD}Execution initialized...${TXT_RESET}"
echo

# ===========================
# Input Collection
# ===========================
prompt_value () {
    echo -ne "${TXT_BOLD}${CLR_CYAN}$1:${TXT_RESET} "
    read value
    export "$2"="$value"
}

prompt_value "Provide BigQuery dataset name" DATASET
prompt_value "Provide Cloud Storage bucket name" BUCKET
prompt_value "Provide BigQuery table name" TABLE
prompt_value "Provide output bucket path (result 1)" BUCKET_URL_1
prompt_value "Provide output bucket path (result 2)" BUCKET_URL_2

echo

# ===========================
# API & Project Configuration
# ===========================
echo "${CLR_BLUE}${TXT_BOLD}Activating required Google Cloud services...${TXT_RESET}"
gcloud services enable apikeys.googleapis.com

echo "${CLR_GREEN}${TXT_BOLD}Generating API key resource...${TXT_RESET}"
gcloud alpha services api-keys create --display-name="awesome"

KEY_NAME=$(gcloud alpha services api-keys list \
  --filter="displayName=awesome" \
  --format="value(name)")

API_KEY=$(gcloud alpha services api-keys get-key-string "$KEY_NAME" \
  --format="value(keyString)")

REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")

PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" \
  --format="value(projectNumber)")

# ===========================
# BigQuery & Cloud Storage
# ===========================
echo "${CLR_BLUE}${TXT_BOLD}Provisioning BigQuery dataset...${TXT_RESET}"
bq mk "$DATASET"

echo "${CLR_MAGENTA}${TXT_BOLD}Provisioning Cloud Storage bucket...${TXT_RESET}"
gsutil mb "gs://$BUCKET"

gsutil cp gs://cloud-training/gsp323/lab.csv .
gsutil cp gs://cloud-training/gsp323/lab.schema .

cat > lab.schema <<EOF
[
  {"type":"STRING","name":"guid"},
  {"type":"BOOLEAN","name":"isActive"},
  {"type":"STRING","name":"firstname"},
  {"type":"STRING","name":"surname"},
  {"type":"STRING","name":"company"},
  {"type":"STRING","name":"email"},
  {"type":"STRING","name":"phone"},
  {"type":"STRING","name":"address"},
  {"type":"STRING","name":"about"},
  {"type":"TIMESTAMP","name":"registered"},
  {"type":"FLOAT","name":"latitude"},
  {"type":"FLOAT","name":"longitude"}
]
EOF

bq mk --table "$DATASET.$TABLE" lab.schema

# ===========================
# Dataflow Execution
# ===========================
echo "${CLR_GREEN}${TXT_BOLD}Launching Dataflow ingestion pipeline...${TXT_RESET}"
gcloud dataflow jobs run awesome-jobs \
  --gcs-location "gs://dataflow-templates-$REGION/latest/GCS_Text_to_BigQuery" \
  --region "$REGION" \
  --worker-machine-type e2-standard-2 \
  --staging-location "gs://$DEVSHELL_PROJECT_ID-marking/temp" \
  --parameters inputFilePattern=gs://cloud-training/gsp323/lab.csv,JSONPath=gs://cloud-training/gsp323/lab.schema,outputTable=$DEVSHELL_PROJECT_ID:$DATASET.$TABLE,bigQueryLoadingTemporaryDirectory=gs://$DEVSHELL_PROJECT_ID-marking/bigquery_temp,javascriptTextTransformGcsPath=gs://cloud-training/gsp323/lab.js,javascriptTextTransformFunctionName=transform

echo
echo "${CLR_GREEN}${TXT_BOLD}Workflow execution completed.${TXT_RESET}"
echo
