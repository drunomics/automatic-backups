#!/usr/bin/env bash

for SITE in `ls -d docroot/sites/*/`; do
  SITE=`basename $SITE`

  if [[ $SITE == 'all' ]] || [[ $SITE == 'default' ]]; then
    continue;
  fi

  if [[ -v AWS_BACKUP_BUCKET ]]; then
    DAY=$(date -d "-1 day" +%Y-%m) && aws s3 sync ~/docroot/sites/${SITE}/files s3://${AWS_BACKUP_BUCKET}/${PLATFORM_APPLICATION_NAME}/files-${SITE}/${PLATFORM_BRANCH}/files/${DAY}/ --storage STANDARD_IA
  fi
done
