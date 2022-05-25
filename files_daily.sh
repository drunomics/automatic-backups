#!/usr/bin/env bash

# check if web or docroot is used and get the appropriate one.
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
if [[ $SITES_NO = 2 && $SITES_ALL = 1 && $SITES_DEFAULT = 1 ]]; then
  SKIP_DEFAULT=false
fi

for SITE in `ls -d $SITES_DIR`; do
  SITE=`basename $SITE`
  # skip only if multisite.
  if [[ $SITE == 'all' ]]; then
    continue;
  fi
  if [[ $SITE == 'default' && $SKIP_DEFAULT ]]; then
    continue;
  fi

  if [[ -v AWS_BACKUP_BUCKET ]]; then
    DAY=$(date -d "-1 day" +%Y-%m-%d) && aws s3 sync ~/docroot/sites/${SITE}/files s3://${AWS_BACKUP_BUCKET}/${PLATFORM_APPLICATION_NAME}/files-${SITE}/${PLATFORM_BRANCH}/files/${DAY}/ --storage STANDARD_IA
  fi
done
