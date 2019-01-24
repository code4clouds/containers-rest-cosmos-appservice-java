#!/bin/bash

################################################################################
# Variables
################################################################################

resourceGroup=$RESOURCE_GROUP
cosmosName=$COSMOSDB_NAME
password=$COSMOSDB_PASSWORD
databaseName=IMDb
files=("title.basics.tsv" "name.basics.tsv" "title.principals.tsv")
collections=(titles names principals_mapping)
keys=("tconst" "nconst" "tconst")

len=${#collections[@]}

################################################################################
# Helpers
################################################################################
create_database() {
  # Verify db doesn't exist
  az cosmosdb database list -g $resourceGroup -n $cosmosName | grep id | grep $databaseName
  rc=$?  # get return code from the previous command.
  if [[ $rc != 0 ]]  # if db doesnt exist (because errored out)
  then az cosmosdb database create -g $resourceGroup -n $cosmosName --db-name $databaseName > /dev/null
  fi
}

create_collections() {  
  for ((i=0; i<len; i++)); do
    step=$((i + 1))
    echo "($step of $len) Creating collection '${collections[i]}'"
    # Verify collection doesn't exist
    az cosmosdb collection list -g $resourceGroup -n $cosmosName --db-name $databaseName | grep \"id\" | grep ${collections[$i]}
    rc=$?  # get return code from the previous command.
    if [[ $rc != 0 ]]  # if collection didnt exist (because errored out)
    then
    partition="/'\$v'/${keys[$i]}/'\$v'"
    az cosmosdb collection create -g $resourceGroup -n $cosmosName --db-name $databaseName --collection-name ${collections[$i]} \
      --partition-key-path $partition --throughput 100000 > /dev/null
    fi
  done
}

delete_tsv_files() {
  for ((i=0; i<len; i++)); do
    rm -v ${files[$i]}
  done
}

import_data() {
  for ((i=0; i<len; i++)); do
    step=$((i + 1))
    echo
    echo "($step of $len) Importing collection ${collections[$i]}..."

    hostName="${cosmosName}.documents.azure.com:10255"
    user=$cosmosName

    mongoimport --host $hostName -u $user -p $password --ssl --sslAllowInvalidCertificates --type tsv --headerline \
      --db $databaseName --collection ${collections[$i]} --numInsertionWorkers 40 --file ${files[$i]}

    echo
    echo "${collections[$i]} import is complete. Reducing RUs to 1,000 to reduce cost."
  done
}

set_throughput() {
  collection=$1
  RUs=$2

  echo
  echo "Setting ${collection} throughput to ${RUs}..."
  az cosmosdb collection update -g $resourceGroup -n $cosmosName --db-name $databaseName --collection-name $collection --throughput $RUs
}

################################################################################
# Main script
################################################################################
set -e

echo
echo "Creating Cosmos DB database..."
create_database

echo
echo "Creating Cosmos DB collections..."
create_collections

echo
echo "Importing IMDb data to Cosmos DB..."
import_data

echo
echo "Finished importing data. Cleaning up..."
delete_tsv_files
 
echo
echo "Reducing throughput on Azure..."
set_throughput

echo
echo "Complete!"
echo
