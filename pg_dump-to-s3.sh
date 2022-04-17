#!/bin/bash

#                     _                             _                  _____ 
#  _ __   __ _     __| |_   _ _ __ ___  _ __       | |_ ___        ___|___ / 
# | '_ \ / _` |   / _` | | | | '_ ` _ \| '_ \ _____| __/ _ \ _____/ __| |_ \ 
# | |_) | (_| |  | (_| | |_| | | | | | | |_) |_____| || (_) |_____\__ \___) |
# | .__/ \__, |___\__,_|\__,_|_| |_| |_| .__/       \__\___/      |___/____/ 
# |_|    |___/_____|                   |_|                                   
#
# Project at https://github.com/gabfl/pg_dump-to-s3
#

set -e

# Set current directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Import config file
source $DIR/pg_dump-to-s3.conf

# Vars
NOW=$(date +"%Y-%m-%d-at-%H-%M-%S")
DELETETION_TIMESTAMP=`[ "$(uname)" = Linux ] && date +%s --date="-$DELETE_AFTER"` # Maximum date (will delete all files older than this date)

# Split databases
IFS=',' read -ra DBS <<< "$PG_DATABASES"

# Delete old files
echo " * Backup in progress.,.";

# Loop thru databases
for db in "${DBS[@]}"; do
    FILENAME="$NOW"_"$db"


    echo "   -> backing up $db..."

    # Dump database
    if [ "$DOCKER_IMAGE" == "" ]; then
        pg_dump -Fc -h $PG_HOST -U $PG_USER -p $PG_PORT $db > $TEMP_PATH/"$FILENAME".dump
    else 
        docker run \
            -it \
            --rm \
            --env PGPASSWORD=$PG_PASSWORD \
            --volume $TEMP_PATH:/dumpvol \
            --entrypoint /usr/local/bin/pg_dump \
            -u $(id -u ${USER}):$(id -g ${USER}) \
            $DOCKER_IMAGE \
            --verbose \
            --format=custom \
            --file=/dumpvol/$FILENAME.dump \
            --dbname=$db \
            --username=$PG_USER \
            --host=$PG_HOST
    fi

    # Copy to S3
    aws s3 cp $TEMP_PATH/"$FILENAME".dump s3://$S3_PATH/"$FILENAME".dump --storage-class STANDARD_IA

    # Delete local file
    rm $TEMP_PATH/"$FILENAME".dump

    # Log
    echo "      ...database $db has been backed up"
done

# Delere old files
echo " * Deleting old backups...";

# Loop thru files
aws s3 ls s3://$S3_PATH/ | while read -r line;  do
    # Get file creation date
    createDate=`echo $line|awk {'print $1" "$2'}`
    createDate=`date -d"$createDate" +%s`

    if [[ $createDate -lt $DELETETION_TIMESTAMP ]]
    then
        # Get file name
        FILENAME=`echo $line|awk {'print $4'}`
        if [[ $FILENAME != "" ]]
          then
            echo "   -> Deleting $FILENAME"
            aws s3 rm s3://$S3_PATH/$FILENAME
        fi
    fi
done;

echo ""
echo "...done!";
echo ""
