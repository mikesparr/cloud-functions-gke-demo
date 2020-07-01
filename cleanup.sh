#!/usr/bin/env bash

source .env

export GCP_REGION=us-central1
export GCP_ZONE=us-central1-a
export GCP_NETWORK=default
export CLUSTER_NAME=central
export VPC_CONNECTOR=db-vpc-conn
export VPC_RANGE="10.8.0.0/28"
export FUNCTION_NAME=db_test

# delete cloud function
gcloud beta functions delete $FUNCTION_NAME \
    --region $GCP_REGION

# delete VPC connector (use the network name [not full path] and region from above)
gcloud compute networks vpc-access connectors delete $VPC_CONNECTOR \
    --region $GCP_REGION

# delete gke cluster
gcloud container clusters delete $CLUSTER_NAME --zone $GCP_ZONE

