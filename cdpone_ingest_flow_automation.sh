#!/bin/bash

# This script will clone the github repository(https://github.com/garidepallisandeep/airlines-self-service-framework.git)
# Export the Nifi CLI path
# Create the Session
# Get the default bucket id
# Create and import the flow in Nifi registry
# Create the flow in Nifi

# How to run this workflow

# This script requires demo.cfg file should be available 
# Copy demo.cfg file to /home/$USER/demo.cfg
# Execute this script sh cdpone_ingest_flow_automation.sh


#Source the Automation Script variables


FILE="/home/$USER/opendatalakehouse/demo.cfg"
if [ -f "$FILE" ]; then
    echo "$FILE exists."
    echo "list Automation script variables"
    source $FILE
    echo $CDP_ONE_NIFI_REGISTRY_URL    
else
    echo "$FILE does not exist."
    return 1
    exit
fi

# CDP One Truststore details
CDP_ONE_TRUSTSTORE="/etc/pki/java/cacerts"
CDP_ONE_TRUSTSTORE_PASSSWORD="changeit"
CDP_ONE_TRUSTSTORE_TYPE="JKS"

# New Hive DB Database to be created with in this ingest data pipeline
HIVE_DATABASE_NAME="airlines"

# External DB Details
EXT_DB_HOST="self-service-trial-source.cluster-cohsea0udkfq.us-east-1.rds.amazonaws.com"
EXT_DB_NAME="airlinedata"
EXT_DB_USERNAME="sstreadwrite"
EXT_DB_PASSWORD='vXNhq6th!jYXn9Wn'
EXT_DB_PORT="5432"

# Default Variables required to execute this script
DIRECTORY="/home/$USER/opendatalakehouse/cdpone_automation"
NIFI_REGISTRY_FLOW_VERSION="1"
NIFI_REGISTRY_BUCKET="Default"
GIT_REPO_DIRECTORY="opendatalakehouse/deployment/ingest"

# STAGE_1_PARAM_CONTEXT_ID="ec9a0d3b-a9de-3db8-b302-9af696e4906d"
# STAGE_2_PARAM_CONTEXT_ID="8034babb-2e0d-3559-9722-9161d81a2dbd"

start_inget_flows="false"

if [ ! -d "$DIRECTORY" ]; then
  mkdir ${DIRECTORY}
  echo "$DIRECTORY Created."
fi

cd ${DIRECTORY}

# Create the nifi.properties file
cat > ${DIRECTORY}/nifi.properties << EOF
baseUrl=${CDP_ONE_NIFI_REGISTRY_URL}
truststore=${CDP_ONE_TRUSTSTORE}
truststoreType=${CDP_ONE_TRUSTSTORE_TYPE}
truststorePasswd=${CDP_ONE_TRUSTSTORE_PASSSWORD}
EOF

cat ${DIRECTORY}/nifi.properties

echo "${DIRECTORY}/nifi.properties created"

ls -ltr ${DIRECTORY}/nifi.properties

# Git Clone the Nifi Ingest flows 

git clone https://github.com/garidepallisandeep/opendatalakehouse.git

if [ ! -d "$GIT_REPO_DIRECTORY" ]; then
    echo "$DIRECTORY git clone failed."
    exit 1
else
    echo "$DIRECTORY git clone successful."
fi

for filename in ${DIRECTORY}/${GIT_REPO_DIRECTORY}/*.json; do
    echo "$filename flow execution started"
    filename_modified=$(echo ${filename##*/})
    file=$(echo "$filename_modified" | cut -f 1 -d '.')

    # Get the bucket id
    export PATH=$PATH:/opt/cloudera/parcels/CFM-2.2.5.0/TOOLKIT/bin
    cli.sh session set nifi.reg.props ${DIRECTORY}/nifi.properties
    echo "nifi cli session created"
    bucket_id=$(cli.sh registry list-buckets -bau ${CDP_ONE_USERNAME} -bap ${CDP_ONE_PASSWORD} -ot json | jq '.[] | select(.name=="'${NIFI_REGISTRY_BUCKET}'") | .identifier')
    if [ -z "$bucket_id" ]; then
        echo "Buckets not found"
        exit 1
    else
        echo "$bucket_id"
    fi
    echo "nifi registry bucket_id $bucket_id"

    # Create the flow in Nifi Registry
    create_flow=$(cli.sh registry create-flow -b ${bucket_id} -fd ${file} -fn ${file} -bau ${CDP_ONE_USERNAME} -bap ${CDP_ONE_PASSWORD})
    
    echo "created flow in nifi registry $create_flow"
    # Get the flow Id
    flow_id=$(cli.sh registry list-flows -b ${bucket_id} -bau ${CDP_ONE_USERNAME} -bap ${CDP_ONE_PASSWORD} -ot json | jq '.[] | select(.name=="'${file}'") | .identifier')
    if [ -z "$flow_id" ]; then
        echo "flow not found"
        exit 1
    else
        echo $flow_id
    fi

    # Import the flow in Nifi Registry
    import_flow=$(cli.sh registry import-flow-version -f "${flow_id}" -i "${filename}" -bau ${CDP_ONE_USERNAME} -bap ${CDP_ONE_PASSWORD})
    # Import the flow in Nifi
    echo "Imported flow in nifi-registry $import_flow"

    create_flow_nifi=$(cli.sh nifi pg-import -b "${bucket_id}" -f "${flow_id}" -fv "${NIFI_REGISTRY_FLOW_VERSION}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
    if [ -z "$create_flow_nifi" ]; then
        echo "Create flow in nifi"
        exit 1
    else
        echo $create_flow_nifi
    fi
    echo "Created $filename flow in nifi"

    # Updated Nifi flow Stage 1 load-data-from-ext-db Parameter Context
    if [ "$file" == "step_1_load_from_source_db_to_cdp_one_landing_zone" ]; then
        
        echo "Get the load-data-from-ext-db parameter context ID"
        STAGE_1_PARAM_CONTEXT_ID=$(cli.sh nifi list-param-contexts -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}" -ot json | jq '.parameterContexts[].component| select( .name == "load-data-from-ext-db") |.id')
        echo "load-data-from-ext-db parameter context ID:${STAGE_1_PARAM_CONTEXT_ID}"

        echo "Get the Pg Group ID for Step 1) Load from source DB to CDP One Landing zone"
        STAGE_1_PG_ID=$(cli.sh nifi pg-list -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}" -ot json| jq '.[]| select( .name == "Step 1) Load from source DB to CDP One Landing zone") |.versionControlInformation.groupId')
        echo "Stage 1 PG Group ID:${STAGE_1_PG_ID}"

        echo "Disable Stage 1 the controller services"
        STAGE_1_DISABLE_CONTROLLER_SERVICE=$(cli.sh nifi pg-disable-services -pgid "${STAGE_1_PG_ID}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")

        echo "Delete the stage-1 cdp-password parameter"
        STAGE_1_DELETE_PARAM_CDP_PASSWORD=$(cli.sh nifi delete-param -pcid ${STAGE_1_PARAM_CONTEXT_ID} -pn cdp-password -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")

        echo "Delete the stage-1 db_password parameter"
        STAGE_1_DELETE_PARAM_DB_PASSWORD=$(cli.sh nifi delete-param -pcid ${STAGE_1_PARAM_CONTEXT_ID} -pn db_password -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")

        echo "Set the stage-1 db_password parameter"
        STAGE_1_SET_PARAM_DB_PASSWORD=$(cli.sh nifi set-param -pcid "${STAGE_1_PARAM_CONTEXT_ID}" -pn db_password -pv ${EXT_DB_PASSWORD} -ps "true" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")

        echo "Set the stage-1 cdp password parameter"
        STAGE_1_SET_PARAM_CDP_PASSWORD=$(cli.sh nifi set-param -pcid "${STAGE_1_PARAM_CONTEXT_ID}" -pn cdp-password -pv ${CDP_ONE_PASSWORD} -ps "true" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")

        echo "Enable Stage 1 the controller services"
        STAGE_1_ENABLE_CONTROLLER_SERVICE=$(cli.sh nifi pg-enable-services -pgid "${STAGE_1_PG_ID}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
        
        if [ "$CDP_ONE_USERNAME" != "gsandeepkumar" ]; then
            stage_1_update_param_cdp_username=$(cli.sh nifi set-param -pcid "${STAGE_1_PARAM_CONTEXT_ID}"  -pn cdp-username -pv "${CDP_ONE_USERNAME}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
            echo "Updated stage 1 parameter cdp-username"
        fi

        if [ "$EXT_DB_HOST" != "self-service-trial-source.cluster-cohsea0udkfq.us-east-1.rds.amazonaws.com" ]; then
            stage_1_update_param_db_host=$(cli.sh nifi set-param -pcid "${STAGE_1_PARAM_CONTEXT_ID}" -pn db_host -pv "${EXT_DB_HOST}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
            echo "Updated stage 1 parameter extdb-host"
        fi

        if [ "$EXT_DB_NAME" != "airline" ]; then
            stage_1_update_param_db_name=$(cli.sh nifi set-param -pcid "${STAGE_1_PARAM_CONTEXT_ID}" -pn db_name -pv ${EXT_DB_NAME} -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
            echo "Updated stage 1 parameter ext-db-name"
        fi
        if [ "$EXT_DB_PORT" != "5432" ]; then
            stage_1_update_param_db_port=$(cli.sh nifi set-param -pcid "${STAGE_1_PARAM_CONTEXT_ID}" -pn db_port -pv ${EXT_DB_PORT} -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
            echo "Updated stage 1 parameter ext-db-port"
        fi

        if [ "$EXT_DB_USERNAME" != "sstreadonly" ]; then
            stage_1_update_param_db_username=$(cli.sh nifi set-param -pcid "${STAGE_1_PARAM_CONTEXT_ID}" -pn db_username -pv "${EXT_DB_USERNAME}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
            echo "Updated stage 1 parameter ext-db-username"
        fi

        if [ "$CDP_ONE_S3_BUCKET" != "cdponedemo-cdp-private-default-3hxxiqv" ]; then
            stage_1_update_param_s3_bucket=$(cli.sh nifi set-param -pcid "${STAGE_1_PARAM_CONTEXT_ID}" -pn landing-directory-path -pv "s3a://${CDP_ONE_S3_BUCKET}/landing/airlines" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
            echo "Updated stage 1 parameter cdp-s3-bucket"
        fi
    fi

    # Updated Nifi flow Stage 2 ETL and Data Engineering Parameter Context
    if [ "$file" == "step_2_data_engineering_ETL" ]; then

        echo "Get the cdp-create-hive-table-from-s3 parameter context ID"
        STAGE_2_PARAM_CONTEXT_ID=$(cli.sh nifi list-param-contexts -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}" -ot json | jq '.parameterContexts[].component| select( .name == "cdp-create-hive-table-from-s3") |.id')
        echo "load-data-from-ext-db parameter context ID:${STAGE_2_PARAM_CONTEXT_ID}"

        echo "Get the Pg Group ID for Step 2) Data Engineering & ETL/ELT"
        STAGE_2_PG_ID=$(cli.sh nifi pg-list -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}" -ot json| jq '.[]| select( .name == "Step 2) Data Engineering & ETL/ELT") |.versionControlInformation.groupId')
        echo "Stage 1 PG Group ID:${STAGE_2_PG_ID}"

        echo "Disable Stage 1 the controller services"
        STAGE_2_DISABLE_CONTROLLER_SERVICE=$(cli.sh nifi pg-disable-services -pgid "${STAGE_2_PG_ID}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")

        echo "Delete the Parameter for stage 2 cdp-password"
        STAGE_2_DELETE_PARAM_CDP_PASSWORD=$(cli.sh nifi delete-param -pcid ${STAGE_2_PARAM_CONTEXT_ID} -pn cdp-password -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")

        echo "set the parameter stage-2 cdp-password"
        STAGE_2_SET_PARAM_CDP_PASSWORD=$(cli.sh nifi set-param -pcid "${STAGE_2_PARAM_CONTEXT_ID}" -pn cdp-password -pv ${CDP_ONE_PASSWORD} -ps "true" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")

        echo "Enable Stage 2 the controller services"
        STAGE_2_ENABLE_CONTROLLER_SERVICE=$(cli.sh nifi pg-enable-services -pgid "${STAGE_2_PG_ID}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")

        
        if [ "$CDP_ONE_USERNAME" != "gsandeepkumar" ]; then
            stage_2_update_param_cdp_username=$(cli.sh nifi set-param -pcid "${STAGE_2_PARAM_CONTEXT_ID}"  -pn cdp-username -pv "${CDP_ONE_USERNAME}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
            echo "Updated stage 1 parameter cdp-username"
        fi

        if [ "$HIVE_DATABASE_NAME" != "airlines" ]; then
            stage_2_update_param_hive_database_name=$(cli.sh nifi set-param -pcid "${STAGE_2_PARAM_CONTEXT_ID}" -pn hive_database -pv "${HIVE_DATABASE_NAME}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
            echo "Updated stage 1 parameter hive-database-name"
        fi
        
        stage_2_update_param_hive_connection_uri=$(cli.sh nifi set-param -pcid "${STAGE_2_PARAM_CONTEXT_ID}" -pn hive_connection_uri -pv "${HIVE_CONNECTION_URI}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
        echo "Updated stage 1 parameter hive-connection-uri"       

        if [ "$CDP_ONE_S3_BUCKET" != "cdponedemo-cdp-private-default-3hxxiqv" ]; then
            stage_2_update_param_s3_bucket=$(cli.sh nifi set-param -pcid "${STAGE_2_PARAM_CONTEXT_ID}" -pn s3-bucket-private -pv "s3a://${CDP_ONE_S3_BUCKET}" -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
            echo "Updated stage 1 parameter cdp-s3-bucket"
        fi
    fi        
done

if [ "${start_inget_flows}" == "true" ]; then
    echo "Get the Pre-requisites Process Group ID for: (1. Pre-requisite) Download connector for Database source"
    PRE_REQ_PG_ID=$(cli.sh nifi pg-list -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}" -ot json| jq '.[]| select( .name == "(1. Pre-requisite) Download connector for Database source") |.versionControlInformation.groupId')
    echo "PG ID for (1. Pre-requisite) Download connector for Database source is: ${PRE_REQ_PG_ID}"

    echo "Get the Process Group ID ID for: Step 1) Load from source DB to CDP One Landing zone"
    STAGE_1_PG_ID=$(cli.sh nifi pg-list -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}" -ot json| jq '.[]| select( .name == "Step 1) Load from source DB to CDP One Landing zone") |.versionControlInformation.groupId')
    echo "PG ID for Step 1) Load from source DB to CDP One Landing zone is: ${STAGE_1_PG_ID}"

    echo "Get the Process Group ID for: Step 2) Data Engineering & ETL/ELT"
    STAGE_2_PG_ID=$(cli.sh nifi pg-list -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}" -ot json| jq '.[]| select( .name == "Step 2) Data Engineering & ETL/ELT") |.versionControlInformation.groupId')
    echo "PG ID for Step  Step 2) Data Engineering & ETL/ELT is: ${STAGE_1_PG_ID}"

    START_PRE_REQ_FLOW=$(cli.sh nifi pg-start -pgid ${PRE_REQ_PG_ID} -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
    echo "(1. Pre-requisite) Download connector for Database source is started"
    sleep 10

    START_STAGE_1_FLOW=$(cli.sh nifi pg-start -pgid ${STAGE_1_PG_ID} -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
    sleep 10
    echo "Step 1) Load from source DB to CDP One Landing zone is started"

    START_STAGE_2_FLOW=$(cli.sh nifi pg-start -pgid ${STAGE_2_PG_ID} -u "${CDP_ONE_NIFI_URL}" -ts "${CDP_ONE_TRUSTSTORE}" -tst "${CDP_ONE_TRUSTSTORE_TYPE}" -tsp "${CDP_ONE_TRUSTSTORE_PASSSWORD}" -bau "${CDP_ONE_USERNAME}" -bap "${CDP_ONE_PASSWORD}")
    echo "Step 2) Data Engineering & ETL/ELT"
fi

#Cleaning the CDP One Automation Directory
rm -rf ${DIRECTORY}
rm -rf $FILE
echo "Deleted demo config file and the Automation Directory:${DIRECTORY}"
