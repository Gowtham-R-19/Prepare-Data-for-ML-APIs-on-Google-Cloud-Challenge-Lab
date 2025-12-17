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

# ===========================
# IAM, Service Accounts & ML Tasks
# ===========================
echo "${CLR_BLUE}${TXT_BOLD}Granting IAM roles to service account...${TXT_RESET}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member "serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role "roles/storage.admin"

echo "${CLR_MAGENTA}${TXT_BOLD}Assigning roles to user...${TXT_RESET}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member=user:$USER_EMAIL \
  --role=roles/dataproc.editor
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member=user:$USER_EMAIL \
  --role=roles/storage.objectViewer

echo "${CLR_CYAN}${TXT_BOLD}Updating VPC subnet for private IP access...${TXT_RESET}"
gcloud compute networks subnets update default \
    --region $REGION \
    --enable-private-ip-google-access

echo "${CLR_RED}${TXT_BOLD}Creating service account...${TXT_RESET}"
gcloud iam service-accounts create awesome \
  --display-name "my natural language service account"
sleep 15

echo "${CLR_GREEN}${TXT_BOLD}Generating service account key...${TXT_RESET}"
gcloud iam service-accounts keys create ~/key.json \
  --iam-account awesome@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com
sleep 15

echo "${CLR_YELLOW}${TXT_BOLD}Activating service account...${TXT_RESET}"
export GOOGLE_APPLICATION_CREDENTIALS="/home/$USER/key.json"
gcloud auth activate-service-account awesome@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com --key-file=$GOOGLE_APPLICATION_CREDENTIALS
sleep 30

echo "${CLR_BLUE}${TXT_BOLD}Running ML entity analysis...${TXT_RESET}"
gcloud ml language analyze-entities --content="Old Norse texts portray Odin as one-eyed and long-bearded, frequently wielding a spear named Gungnir and wearing a cloak and a broad hat." > result.json

echo "${CLR_GREEN}${TXT_BOLD}Authenticating to Google Cloud...${TXT_RESET}"
gcloud auth login --no-launch-browser --quiet

echo "${CLR_MAGENTA}${TXT_BOLD}Copying ML results to bucket...${TXT_RESET}"
gsutil cp result.json $BUCKET_URL_2

# Speech-to-text request JSON
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

echo "${CLR_CYAN}${TXT_BOLD}Performing speech recognition...${TXT_RESET}"
curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json \
"https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" > result.json

echo "${CLR_GREEN}${TXT_BOLD}Copying speech recognition result to Cloud Storage...${TXT_RESET}"
gsutil cp result.json $BUCKET_URL_1

# ===========================
# Progress Check Function
# ===========================
check_progress () {
    while true; do
        echo
        echo -n "${TXT_BOLD}${CLR_YELLOW}Have you checked your progress for Task 3 & Task 4? (Y/N): ${TXT_RESET}"
        read -r user_input
        if [[ "$user_input" == "Y" || "$user_input" == "y" ]]; then
            echo "${TXT_BOLD}${CLR_GREEN}Great! Proceeding to the next steps...${TXT_RESET}"
            break
        elif [[ "$user_input" == "N" || "$user_input" == "n" ]]; then
            echo "${TXT_BOLD}${CLR_RED}Please check your progress for Task 3 & Task 4 and then press Y to continue.${TXT_RESET}"
        else
            echo "${TXT_BOLD}${CLR_MAGENTA}Invalid input. Please enter Y or N.${TXT_RESET}"
        fi
    done
}

check_progress

# ===========================
# Dataproc Cluster & Spark Job
# ===========================
echo "${CLR_CYAN}${TXT_BOLD}Creating Dataproc cluster...${TXT_RESET}"
gcloud dataproc clusters create awesome --enable-component-gateway --region $REGION --master-machine-type e2-standard-2 --master-boot-disk-type pd-balanced --master-boot-disk-size 100 --num-workers 2 --worker-machine-type e2-standard-2 --worker-boot-disk-type pd-balanced --worker-boot-disk-size 100 --image-version 2.2-debian12 --project $DEVSHELL_PROJECT_ID

echo "${CLR_GREEN}${TXT_BOLD}Fetching VM instance name...${TXT_RESET}"
VM_NAME=$(gcloud compute instances list --project="$DEVSHELL_PROJECT_ID" --format=json | jq -r '.[0].name')

echo "${CLR_MAGENTA}${TXT_BOLD}Fetching VM zone...${TXT_RESET}"
export ZONE=$(gcloud compute instances list $VM_NAME --format 'csv[no-heading](zone)')

echo "${CLR_BLUE}${TXT_BOLD}Copying data to HDFS on VM...${TXT_RESET}"
gcloud compute ssh --zone "$ZONE" "$VM_NAME" --project "$DEVSHELL_PROJECT_ID" --quiet --command="hdfs dfs -cp gs://cloud-training/gsp323/data.txt /data.txt"

echo "${CLR_CYAN}${TXT_BOLD}Copying data to local storage on VM...${TXT_RESET}"
gcloud compute ssh --zone "$ZONE" "$VM_NAME" --project "$DEVSHELL_PROJECT_ID" --quiet --command="gsutil cp gs://cloud-training/gsp323/data.txt /data.txt"

echo "${CLR_MAGENTA}${TXT_BOLD}Submitting Spark job to Dataproc...${TXT_RESET}"
gcloud dataproc jobs submit spark \
  --cluster=awesome \
  --region=$REGION \
  --class=org.apache.spark.examples.SparkPageRank \
  --jars=file:///usr/lib/spark/examples/jars/spark-examples.jar \
  --project=$DEVSHELL_PROJECT_ID \
  -- /data.txt

# ===========================
# Cleanup Function
# ===========================
cleanup_files () {
    for file in *; do
        if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* || "$file" == request.json || "$file" == result.json ]]; then
            if [[ -f "$file" ]]; then
                rm "$file"
                echo "Removed temporary file: $file"
            fi
        fi
    done
}

cleanup_files

# ===========================
# Completion Message
# ===========================
echo
echo "${CLR_GREEN}${TXT_BOLD}Lab completed successfully!${TXT_RESET}"
echo "${CLR_YELLOW}${TXT_BOLD}Repository: https://github.com/Gowtham-R-19/Prepare-Data-for-ML-APIs-on-Google-Cloud-Challenge-Lab${TXT_RESET}"
echo
