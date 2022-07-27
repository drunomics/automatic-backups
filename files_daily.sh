#!/usr/bin/env bash

# check if web or docroot is used and get the appropriate one.
if [ -d "files" ]; then
  SITES_DIR=files/*/
elif [ -d "web" ]; then
  SITES_DIR=web/sites/*/
  echo "Using ${SITES_DIR}"
else
  SITES_DIR=docroot/sites/*/
  echo "Using ${SITES_DIR}"
fi

# check if PROJECT_NAME variable is set, if not, default to $PLATFORM_APPLICATION_NAME.
if [[ ! -v PROJECT_NAME ]]; then
  PROJECT_NAME=$PLATFORM_APPLICATION_NAME
fi

# check how many sites (ignore [^ name created by using pattern in mounts)
NUMBER_OF_SITES=$(find $SITES_DIR -maxdepth 0 -type d ! -name '[^' | wc -l)
SITES_ALL=$(find $SITES_DIR -maxdepth 0 -name "all" | wc -l)
SITES_DEFAULT=$(find $SITES_DIR -maxdepth 0 -name "*default" | wc -l)

SKIP_DEFAULT='true'
# if these conditions are met then it's not multisite
# and default directory should be used.
if [[ $NUMBER_OF_SITES = 2 && $SITES_ALL = 1 && $SITES_DEFAULT = 1 ]]; then
  SKIP_DEFAULT='false'
fi

for SITE in `ls -d $SITES_DIR`; do
  SITE=`basename $SITE`
  # skip only if multisite.
  if [ $NUMBER_OF_SITES -gt 1 ]; then
    if [[ $SITE == 'all' ]]; then
      continue;
    fi
    if [[ $SITE == 'default' && $SKIP_DEFAULT == 'true' ]]; then
      continue;
    fi
  fi

  # special scenario created by having modular mount for files.
  if [[ $SITE == '[^' ]]; then
    continue;
  fi

  if [[ -v AWS_BACKUP_BUCKET ]]; then
    if [ -d "files" ]; then
      DAY=$(date -d "-1 day" +%Y-%m) && aws s3 sync ~/files/${SITE}/files s3://${AWS_BACKUP_BUCKET}/${PROJECT_NAME}/files-${SITE}/${PLATFORM_BRANCH}/files/${DAY}/ --storage STANDARD_IA
    elif [ -d "web" ]; then
      DAY=$(date -d "-1 day" +%Y-%m) && aws s3 sync ~/web/sites/${SITE}/files s3://${AWS_BACKUP_BUCKET}/${PROJECT_NAME}/files-${SITE}/${PLATFORM_BRANCH}/files/${DAY}/ --storage STANDARD_IA
    else
      DAY=$(date -d "-1 day" +%Y-%m) && aws s3 sync ~/docroot/sites/${SITE}/files s3://${AWS_BACKUP_BUCKET}/${PROJECT_NAME}/files-${SITE}/${PLATFORM_BRANCH}/files/${DAY}/ --storage STANDARD_IA
    fi
  elif [[ -v SFTP_SERVER ]]; then
    DAY=$(date -d "-1 day" +%Y-%m)
    # only use port when
    SSH_COMMAND="ssh"
    if [[ -n "$SFTP_PORT" ]]; then
      SSH_COMMAND="ssh -p $SFTP_PORT"
    fi
    # first create directory with files for current day in order to be able to move the folder to SFTP.
    mkdir -p drush-backups/${PROJECT_NAME}/site-${SITE}/${PLATFORM_BRANCH}/${DAY}
    rsync -e $SSH_COMMAND -rvxl --progress drush-backups/${PROJECT_NAME} ${SFTP_USERNAME}@${SFTP_SERVER}:~/${SFTP_DIRECTORY}
    echo "Copying files to server."
    if [ -d "files" ]; then
      rsync -e $SSH_COMMAND -avzl --progress ~/files/${SITE} ${SFTP_USERNAME}@${SFTP_SERVER}:~/${SFTP_DIRECTORY}/${PROJECT_NAME}/site-${SITE}/${PLATFORM_BRANCH}/${DAY}
    elif [ -d "web" ]; then
      rsync -e $SSH_COMMAND -avzl --progress ~/web/sites/${SITE}/files ${SFTP_USERNAME}@${SFTP_SERVER}:~/${SFTP_DIRECTORY}/${PROJECT_NAME}/site-${SITE}/${PLATFORM_BRANCH}/${DAY}
    else
      rsync -e $SSH_COMMAND -avzl --progress ~/docroot/sites/${SITE}/files ${SFTP_USERNAME}@${SFTP_SERVER}:~/${SFTP_DIRECTORY}/${PROJECT_NAME}/site-${SITE}/${PLATFORM_BRANCH}/${DAY}
    fi
  fi
done

if [[ -v SFTP_SERVER ]]; then
  # after copying the files remove new-ly created directory.
  find $HOME/drush-backups/${PROJECT_NAME} -mindepth 1 -type d -print0 |xargs --null -I {} rm -r -v "{}"
fi
