#!/usr/bin/env bash

source .env     # fetch your PROJECT_ID and AUTH_NETWORK (your IP)

# enable apis
gcloud services enable container.googleapis.com # Kubernetes Engine API
gcloud services enable vpcaccess.googleapis.com # Serverless VPC
gcloud services enable cloudfunctions.googleapis.com # Cloud Functions API

export GCP_REGION=us-central1
export GCP_ZONE=us-central1-a
export GCP_NETWORK=default
export CLUSTER_NAME=central
export VPC_CONNECTOR=db-vpc-conn
export VPC_RANGE="10.8.0.0/28"
export FUNCTION_NAME=db_test

##################################################################
# HELPER FUNCTIONS
##################################################################

install_db () {
    echo "Installing DB ..."
    
    kubectl create clusterrolebinding cluster-admin-binding \
        --clusterrole cluster-admin \
        --user $(gcloud config get-value core/account)
    
    kubectl create namespace percona

    kubectl apply -f https://raw.githubusercontent.com/percona/percona-xtradb-cluster-operator/release-1.4.0/deploy/bundle.yaml \
        -n percona

    kubectl apply -f https://raw.githubusercontent.com/percona/percona-xtradb-cluster-operator/release-1.4.0/deploy/cr.yaml \
        -n percona

    # wait until stateful set is ready
    echo "Waiting for DB install ..."
    sleep 20    # if issues just re-run the script (cluster install time varies)
    kubectl wait --for=condition=ready pod \
        --timeout=600s \
        -l "app.kubernetes.io/instance=cluster1" \
        --namespace percona
}

load_test_data () {
    # just for demo (this is not secure to transmit pass!!!)
    echo "Fetching DB password"
    export DB_PASS=$(kubectl get secret my-cluster-secrets -n percona -o go-template='{{ .data.root }}' | base64 -D)
    echo "DB password: $DB_PASS"

    echo "Loading test data into database ..."
    kubectl -n percona exec -i cluster1-pxc-0 -c pxc -- mysql -uroot -p${DB_PASS} < database-test1.sql
}

create_vpc_connector () {
    echo "Creating VPC connector ..."

    gcloud compute networks vpc-access connectors create $VPC_CONNECTOR \
        --network $GCP_NETWORK \
        --region $GCP_REGION \
        --range $VPC_RANGE

    # verify connector
    gcloud compute networks vpc-access connectors describe $VPC_CONNECTOR --region $GCP_REGION
}

create_internal_lb () {
    echo "Creating internal lb ..."
    kubectl apply -f internal-lb.yaml

    echo "Waiting for LB host IP ..."

    while true; do                                                                     
        successCond="$(kubectl -n percona get svc/mysql-db -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"        
        if [[ -z "$successCond" ]]; then                                               
            echo "Waiting for endpoint readiness..."                                   
            sleep 10                                                                   
        else                                                                           
            sleep 2                                                                    
            export DB_HOST="$successCond"                                             
            echo "Load balancer with IP ${DB_HOST} is up!"                                                                    
            break                                                                      
        fi                                                                             
    done
}

deploy_cloud_function () {
    echo "Depoying cloud function ..."

    cd $FUNCTION_NAME

    gcloud beta functions deploy $FUNCTION_NAME \
        --runtime python37 \
        --trigger-http \
        --region $GCP_REGION \
        --vpc-connector projects/$PROJECT_ID/locations/$GCP_REGION/connectors/$VPC_CONNECTOR \
        --set-env-vars DB_HOST=$DB_HOST,DB_PASS=$DB_PASS
    
    echo "Cloud function created connecting to ${DB_HOST}"
}

##################################################################
# Let's begin ...
##################################################################

echo "Creating cluster $CLUSTER_NAME in zone $GCP_ZONE ..."

gcloud beta container --project $PROJECT_ID clusters create "$CLUSTER_NAME" \
    --zone "$GCP_ZONE" \
    --no-enable-basic-auth \
    --cluster-version "1.16.9-gke.6" \
    --machine-type "e2-standard-2" \
    --image-type "COS" \
    --disk-type "pd-standard" --disk-size "100" \
    --node-labels location=west \
    --metadata disable-legacy-endpoints=true \
    --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_write","https://www.googleapis.com/auth/sqlservice.admin","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/pubsub","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
    --preemptible \
    --num-nodes "4" \
    --enable-stackdriver-kubernetes \
    --enable-ip-alias \
    --network "projects/${PROJECT_ID}/global/networks/default" \
    --subnetwork "projects/${PROJECT_ID}/regions/${GCP_REGION}/subnetworks/default" \
    --default-max-pods-per-node "110" \
    --enable-autoscaling --min-nodes "0" --max-nodes "6" \
    --enable-network-policy \
    --enable-master-authorized-networks --master-authorized-networks $AUTH_NETWORK \
    --addons HorizontalPodAutoscaling,HttpLoadBalancing \
    --enable-autoupgrade \
    --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 1 \
    --labels env=sandbox \
    --enable-vertical-pod-autoscaling \
    --identity-namespace "${PROJECT_ID}.svc.id.goog" \
    --enable-shielded-nodes \
    --shielded-secure-boot \
    --tags "k8s","$1"

echo "Cluster $CLUSTER_NAME created in zone $GCP_ZONE"

# authenticate
echo "Authenticating kubectl (should after create but just in case)..."
gcloud container clusters get-credentials $CLUSTER_NAME --zone $GCP_ZONE

# install database
echo "Installing DB ..."
install_db

# create internal load balancer service
echo "Creating internal load balancer service ..."
create_internal_lb

# create serverless vpc
echo "Creating VPC connector ..."
create_vpc_connector

# deploy cloud function
echo "Loading test data into database ..."
load_test_data

# deploy cloud function
echo "Deploying cloud function ..."
deploy_cloud_function

echo "Congratulations! Visit your cloud function and try it out"

##################################################################
# Fin
##################################################################
