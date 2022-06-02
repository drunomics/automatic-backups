#!/usr/bin/env bash

function upload_dump_to_s3() {
    aws s3 mv ${1} s3://${AWS_BACKUP_BUCKET}/${PLATFORM_APPLICATION_NAME}/sql/${PLATFORM_BRANCH}/ --storage-class STANDARD_IA
    if [ $(date +%d) -eq "01" ]; then SQLDUMP_VALUE=archive; else SQLDUMP_VALUE=rolling; fi
    KEY="${PLATFORM_APPLICATION_NAME}/sql/${PLATFORM_BRANCH}/$(basename ${1})"
    aws s3api put-object-tagging --bucket ${AWS_BACKUP_BUCKET} --key ${KEY} --tagging "TagSet=[{Key=sqldump,Value=${SQLDUMP_VALUE}}]"
}

# Be sure files directories are setup.
if [ -d "web" ]; then
  SITES_DIR=web/sites/*/
    echo "Using ${SITES_DIR}"
else
  SITES_DIR=docroot/sites/*/
  echo "Using ${SITES_DIR}"
fi

# check how many sites
SITES_NO=$(find $SITES_DIR -maxdepth 0 -type d | wc -l)
SITES_ALL=$(find $SITES_DIR -maxdepth 0 -name "*all" | wc -l)
SITES_DEFAULT=$(find $SITES_DIR -maxdepth 0 -name "*default" | wc -l)

SKIP_DEFAULT=true
# if these conditions are met then it's not multisite
# and default directory should be used.
if [[ $SITES_NO == 2 && $SITES_ALL == 1 && $SITES_DEFAULT == 1 ]]; then
  SKIP_DEFAULT=false
fi

if [[ -v AWS_BACKUP_BUCKET ]]; then
  for SITE in `ls -d $SITES_DIR`; do
    SITE=`basename $SITE`
    database=$SITE

    if [ $SITES_NO -gt 1 ]; then
      if [[ $SITE == 'all' ]]; then
        continue;
      fi
      if [[ $SITE == 'default' && $SKIP_DEFAULT == 'true' ]]; then
          continue;
      fi
    fi

    # if the site name is not used for database, then default to 'database'.
    if [[ "$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${database}[0].host")" == null ]]; then
      database='database'
    fi

    DB_HOST=$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${database}[0].host")
    DB_PORT=$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${database}[0].port")
    DB_NAME=$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${database}[0].path")
    DB_USER=$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${database}[0].username")
    DB_PASS=$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${database}[0].password")
    DUMP_FOLDER=$HOME/drush-backups/${SITE}/$(date +%Y%m%d%H%M%S)
    DUMP_FILE=${DUMP_FOLDER}/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql.gz
    mkdir -p "${DUMP_FOLDER}"
    echo "Creating database dump to ${DUMP_FILE}";
    time mysqldump --max-allowed-packet=16M --single-transaction --skip-opt -e --quick --skip-disable-keys --skip-add-locks -a --add-drop-table --triggers --routines -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" | gzip -9 > "${DUMP_FILE}"
    echo "DONE"

  done

  # loop through backups and upload to S3 until none left.
  find $HOME/drush-backups -type f -name *gz -print | while read dump;
  do
    upload_dump_to_s3 $dump;
  done

  # clean up remaining files
  find $HOME/drush-backups -mindepth 1 -type d -empty -delete
fi
