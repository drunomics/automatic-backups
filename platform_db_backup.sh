#!/usr/bin/env bash

# check if PROJECT_NAME variable is set, if not, default to $PLATFORM_APPLICATION_NAME.
if [[ ! -v PROJECT_NAME ]]; then
  PROJECT_NAME=$PLATFORM_APPLICATION_NAME
fi


function upload_dump_to_s3() {
    aws s3 mv ${1} s3://${AWS_BACKUP_BUCKET}/${PROJECT_NAME}/sql/${PLATFORM_BRANCH}/ --storage-class STANDARD_IA
    if [ $(date +%d) -eq "01" ]; then SQLDUMP_VALUE=archive; else SQLDUMP_VALUE=rolling; fi
    KEY="${PROJECT_NAME}/sql/${PLATFORM_BRANCH}/$(basename ${1})"
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
NUMBER_OF_SITES=$(find $SITES_DIR -maxdepth 0 -type d | wc -l)
SITES_ALL=$(find $SITES_DIR -maxdepth 0 -name "all" | wc -l)
SITES_DEFAULT=$(find $SITES_DIR -maxdepth 0 -name "*default" | wc -l)

SKIP_DEFAULT=true
# if these conditions are met then it's not multisite
# and default directory should be used.
if [[ $NUMBER_OF_SITES == 2 && $SITES_ALL == 1 && $SITES_DEFAULT == 1 ]]; then
  SKIP_DEFAULT=false
fi

# if sftp, prepare ssh keys.
if [[ -v SFTP_USERNAME ]]; then
    mkdir -p $HOME/.ssh
    echo "${SSH_SECRET_KEY}" > $HOME/.ssh/id_rsa
    echo "${SSH_PUBLIC_KEY}" > $HOME/.ssh/id_rsa.pub
    chmod 600 $HOME/.ssh/id_rsa
    chmod 600 $HOME/.ssh/id_rsa.pub
  fi

if [[ -v AWS_BACKUP_BUCKET || -v SFTP_SERVER ]]; then
  for SITE in `ls -d $SITES_DIR`; do
    SITE=`basename $SITE`
    database=$SITE

    if [ $NUMBER_OF_SITES -gt 1 ]; then
      if [[ $SITE == 'all' ]]; then
        continue;
      fi
      if [[ $SITE == 'default' && $SKIP_DEFAULT == 'true' ]]; then
          continue;
      fi
    fi

    # get the directories from SFTP that can be deleted because they are old.
    if [[ -v SFTP_DIRECTORY && -v SITE && -v SFTP_SERVER ]]; then
      echo "Checking old backups"
      if [[ ! -v SFTP_DAYS_EXP ]]; then
        SFTP_DAYS_EXP=180
      fi
      ssh -p $SFTP_PORT ${SFTP_USERNAME}@${SFTP_SERVER} "find ~/$SFTP_DIRECTORY/drush-backups/$PROJECT_NAME -mindepth 1 -type d -mtime +$SFTP_DAYS_EXP -printf '%p\n' |grep -v '\-d01' |xargs -I {} rm -r -v \"{}\""
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
    DUMP_FOLDER=$HOME/drush-backups/${PROJECT_NAME}/${SITE}/$(date +%Y-m%m-d%d)
    DUMP_FILE=${DUMP_FOLDER}/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql.gz
    mkdir -p "${DUMP_FOLDER}"
    echo "Creating database dump to ${DUMP_FILE}";
    time mysqldump --max-allowed-packet=16M --single-transaction --skip-opt -e --quick --skip-disable-keys --skip-add-locks -a --add-drop-table --triggers --routines -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" | gzip -9 > "${DUMP_FILE}"
    if [[ -n $SECRET_ENC_PASS ]] && [[ "$ENABLE_ENCRYPTION" == "1" ]]; then
      # encrypt the db backup.
      if [[ -n $ENCRYPTION_ALG ]]; then
        echo "Encrypting backup at ${DUMP_FOLDER}/${DB_NAME}_$(date +%Y%m%d_%H%M%S)-enc.sql.gz"
        openssl enc -${ENCRYPTION_ALG} -salt -in $DUMP_FILE -out ${DUMP_FOLDER}/${DB_NAME}_$(date +%Y%m%d_%H%M%S)-enc.sql.gz -pass pass:$SECRET_ENC_PASS
        # delete the unencrypted file so that it doesn't get uploaded to the server.
        rm $DUMP_FILE
      else
        echo "Encryption failed because ENCRYPTION_ALG variable is not set."
      fi
    else
      echo "Encryption failed because SECRET_ENC_PASS variable is not set or because encryption is disabled."
    fi
    echo "DONE"

  done

  # loop through backups and upload to S3/SFTP until none left.
  find $HOME/drush-backups -type f -name *gz -print | while read dump;
  do
    if [[ -v AWS_BACKUP_BUCKET ]]; then
      upload_dump_to_s3 $dump;
    fi
  done

  # upload backups in bulk to SFTP.
  if [[ -v SFTP_SERVER ]]; then
    echo "Uploading to SFTP server."
    if [[ -n "$SFTP_PORT" ]]; then
      rsync -Parvx -e "ssh -p $SFTP_PORT" --progress ./drush-backups ${SFTP_USERNAME}@${SFTP_SERVER}:~/${SFTP_DIRECTORY}
    else
      rsync -Parvx -e "ssh" --progress ./drush-backups ${SFTP_USERNAME}@${SFTP_SERVER}:~/${SFTP_DIRECTORY}
    fi

  fi

  # clean up remaining files after they have been uploaded
  find $HOME/drush-backups -mindepth 1 -type d -print0 |xargs --null -I {} rm -r -v "{}"
fi
