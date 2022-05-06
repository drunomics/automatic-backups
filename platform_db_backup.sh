#!/usr/bin/env bash
# Be sure files directories are setup.
if [[ -v AWS_BACKUP_BUCKET ]]; then
  for SITE in `ls -d docroot/sites/*/`; do
    SITE=`basename $SITE`

    if [[ $SITE == 'all' ]] || [[ $SITE == 'default' ]]; then
      continue;
    fi

    DB_HOST=$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${SITE}[0].host")
    DB_PORT=$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${SITE}[0].port")
    DB_NAME=$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${SITE}[0].path")
    DB_USER=$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${SITE}[0].username")
    DB_PASS=$(echo $PLATFORM_RELATIONSHIPS | base64 --decode | jq -r ".${SITE}[0].password")
    DUMP_FOLDER=~/drush-backups/${SITE}/${DB_USER}/$(date +%Y%m%d%H%M%S)
    DUMP_FILE=${DUMP_FOLDER}/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql.gz
    mkdir -p "${DUMP_FOLDER}"
    echo "Creating database dump to ${DUMP_FILE}";
    time mysqldump --max-allowed-packet=16M --single-transaction --skip-opt -e --quick --skip-disable-keys --skip-add-locks -a --add-drop-table --triggers --routines -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" | gzip -9 > "${DUMP_FILE}"
    echo "DONE"

  done

  # Upload backup to s3.
  find ~/drush-backups -type f -name *gz -print -execdir sh -c '
          aws s3 mv {} s3://${AWS_BACKUP_BUCKET}/${PLATFORM_APPLICATION_NAME}/sql/${PLATFORM_BRANCH}/ --storage-class STANDARD_IA
          if [ $(date +%d) -eq "01" ]; then SQLDUMP_VALUE=archive; else SQLDUMP_VALUE=rolling; fi
          KEY="${PLATFORM_APPLICATION_NAME}/sql/${PLATFORM_BRANCH}/$(basename {})"
          aws s3api put-object-tagging --bucket ${AWS_BACKUP_BUCKET} --key ${KEY} --tagging "TagSet=[{Key=sqldump,Value=${SQLDUMP_VALUE}}]"
      ' \;
    # clean up remaining files
  find ~/drush-backups -mindepth 1 -type d -empty -delete

fi
