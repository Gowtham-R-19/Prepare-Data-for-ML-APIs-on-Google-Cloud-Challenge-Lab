#!/bin/bash

#===============================================================#
#             Google Cloud Lab Automation Script                #
#          Author: Gowtham R                                    #
#             Purpose: Automate BigQuery, Dataflow,             #
#                      ML & Dataproc tasks                      #
#===============================================================#

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

#---------------------------- Function to Gather Inputs ----------------------------#

get_input() {
    local prompt="$1"
    local var_name="$2"
    echo -n -e "${BOLD}${CYAN}${prompt}${RESET} "
    read input
    export "$var_name"="$input"
}

#---------------------------- User Inputs ----------------------------#
echo "==================== User Inputs ===================="
get_input "Enter the DATASET Name:" "DATASET"
get_input "Enter the BUCKET Name:" "BUCKET"
get_input "Enter the TABLE Name:" "TABLE"
get_input "Enter the RESULT_BUCKET_URL_1 value:" "BUCKET_URL_1"
get_input "Enter the RESULT_BUCKET_URL_2 value:" "BUCKET_URL_2"
echo "====================================================="
echo

#---------------------------- Enable API Services ----------------------------#
echo "${BLUE}${BOLD}Enabling API keys service...${RESET}"
gcloud services enable apikeys.googleapis.com

#---------------------------- API Key Creation ----------------------------#
echo "${GREEN}${BOLD}Creating an API key with display name 'awesome'...${RESET}"
gcloud alpha services api-keys create --display-name="awesome"

echo "${YELLOW}${BOLD}Retrieving API key name...${RESET}"
KEY_NAME=$(gcloud alpha services api-keys list --format="value(name)" --filter "displayName=awesome")

echo "${MAGENTA}${BOLD}Getting API key string...${RESET}"
API_KEY=$(gcloud alpha services api-keys get-key-string $KEY_NAME --format="value(keyString)")

#---------------------------- Project Info ----------------------------#
echo "${CYAN}${BOLD}Getting default Google Cloud region...${RESET}"
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo "${RED}${BOLD}Retrieving project ID...${RESET}"
PROJECT_ID=$(gcloud config get-value project)

echo "${GREEN}${BOLD}Retrieving project number...${RESET}"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="json" | jq -r '.projectNumber')

#---------------------------- BigQuery & Cloud Storage ----------------------------#
echo "${BLUE}${BOLD}Creating BigQuery dataset...${RESET}"
bq mk $DATASET

echo "${MAGENTA}${BOLD}Creating Cloud Storage bucket...${RESET}"
gsutil mb gs://$BUCKET

echo "${YELLOW}${BOLD}Copying lab files from GCS...${RESET}"
gsutil cp gs://cloud-training/gsp323/lab.csv .
gsutil cp gs://cloud-training/gsp323/lab.schema .

echo "${CYAN}${BOLD}Displaying schema contents...${RESET}"
cat lab.schema

# Overwrite schema in case of edits
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

echo "${RED}${BOLD}Creating BigQuery table...${RESET}"
bq mk --table $DATASET.$TABLE lab.schema

#---------------------------- Dataflow Job ----------------------------#
echo "${GREEN}${BOLD}Running Dataflow job to load data into BigQuery...${RESET}"
gcloud dataflow jobs run awesome-jobs \
--gcs-location gs://dataflow-templates-$REGION/latest/GCS_Text_to_BigQuery \
--region $REGION --worker-machine-type e2-standard-2 \
--staging-location gs://$DEVSHELL_PROJECT_ID-marking/temp \
--parameters inputFilePattern=gs://cloud-training/gsp323/lab.csv,\
JSONPath=gs://cloud-training/gsp323/lab.schema,\
outputTable=$DEVSHELL_PROJECT_ID:$DATASET.$TABLE,\
bigQueryLoadingTemporaryDirectory=gs://$DEVSHELL_PROJECT_ID-marking/bigquery_temp,\
javascriptTextTransformGcsPath=gs://cloud-training/gsp323/lab.js,\
javascriptTextTransformFunctionName=transform

#---------------------------- IAM Roles ----------------------------#
echo "${BLUE}${BOLD}Granting IAM roles to service account...${RESET}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member "serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role "roles/storage.admin"

echo "${MAGENTA}${BOLD}Assigning roles to user...${RESET}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member=user:$USER_EMAIL \
  --role=roles/dataproc.editor

gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member=user:$USER_EMAIL \
  --role=roles/storage.objectViewer

#---------------------------- VPC & Service Account ----------------------------#
echo "${CYAN}${BOLD}Updating VPC subnet for private IP access...${RESET}"
gcloud compute networks subnets update default --region $REGION --enable-private-ip-google-access

echo "${RED}${BOLD}Creating a service account...${RESET}"
gcloud iam service-accounts create awesome --display-name "my natural language service account"
sleep 15

echo "${GREEN}${BOLD}Generating service account key...${RESET}"
gcloud iam service-accounts keys create ~/key.json --iam-account awesome@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com
sleep 15

echo "${YELLOW}${BOLD}Activating service account...${RESET}"
export GOOGLE_APPLICATION_CREDENTIALS="/home/$USER/key.json"
sleep 30
gcloud auth activate-service-account awesome@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com --key-file=$GOOGLE_APPLICATION_CREDENTIALS

#---------------------------- ML & Speech Recognition ----------------------------#
echo "${BLUE}${BOLD}Running ML entity analysis...${RESET}"
gcloud ml language analyze-entities --content="Old Norse texts portray Odin as one-eyed and long-bearded, frequently wielding a spear named Gungnir and wearing a cloak and a broad hat." > result.json

echo "${MAGENTA}${BOLD}Copying result to bucket...${RESET}"
gsutil cp result.json $BUCKET_URL_2

cat > request.json <<EOF
{
  "config": {
      "encoding":"FLAC",
      "languageCode": "en-US"
  },
  "audio": {
      "uri":"gs://cloud-training/gsp323/task3.flac"
  }
}
EOF

echo "${CYAN}${BOLD}Performing speech recognition...${RESET}"
curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" > result.json

echo "${GREEN}${BOLD}Copying speech recognition result to Cloud Storage...${RESET}"
gsutil cp result.json $BUCKET_URL_1

#---------------------------- Dataproc Section ============================#
echo "==================== Dataproc Cluster Section ===================="
echo "${CYAN}${BOLD}Creating Dataproc cluster...${RESET}"
gcloud dataproc clusters create awesome --enable-component-gateway --region $REGION \
--master-machine-type e2-standard-2 --master-boot-disk-type pd-balanced --master-boot-disk-size 100 \
--num-workers 2 --worker-machine-type e2-standard-2 --worker-boot-disk-type pd-balanced --worker-boot-disk-size 100 \
--image-version 2.2-debian12 --project $DEVSHELL_PROJECT_ID

echo "${GREEN}${BOLD}Fetching VM instance name...${RESET}"
VM_NAME=$(gcloud compute instances list --project="$DEVSHELL_PROJECT_ID" --format=json | jq -r '.[0].name')

echo "${MAGENTA}${BOLD}Fetching VM zone...${RESET}"
export ZONE=$(gcloud compute instances list $VM_NAME --format 'csv[no-heading](zone)')

echo "${BLUE}${BOLD}Copying data to HDFS on VM...${RESET}"
gcloud compute ssh --zone "$ZONE" "$VM_NAME" --project "$DEVSHELL_PROJECT_ID" --quiet --command="hdfs dfs -cp gs://cloud-training/gsp323/data.txt /data.txt"

echo "${CYAN}${BOLD}Copying data to local storage on VM...${RESET}"
gcloud compute ssh --zone "$ZONE" "$VM_NAME" --project "$DEVSHELL_PROJECT_ID" --quiet --command="gsutil cp gs://cloud-training/gsp323/data.txt /data.txt"

echo "${MAGENTA}${BOLD}Submitting Spark job to Dataproc...${RESET}"
gcloud dataproc jobs submit spark --cluster=awesome --region=$REGION \
--class=org.apache.spark.examples.SparkPageRank \
--jars=file:///usr/lib/spark/examples/jars/spark-examples.jar --project=$DEVSHELL_PROJECT_ID -- /data.txt

#---------------------------- Completion ----------------------------#
echo
echo "${GREEN}${BOLD}Lab completed successfully!${RESET}"
echo "${YELLOW}${BOLD}Subscribe to Dr. Abhishek: https://www.youtube.com/@drabhishek.5460/videos${RESET}"
echo

#---------------------------- Cleanup Function ----------------------------#
remove_files() {
    for file in *; do
        if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* ]]; then
            if [[ -f "$file" ]]; then
                rm "$file"
                echo "File removed: $file"
            fi
        fi
    done
}
remove_files
