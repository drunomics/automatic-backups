# Automatic Backups Platform.sh with AWS S3

Provide a central script that can be used in .platform.app.yml cron to back up db and files of the platform.sh hosted
drupal website to a AWS S3 bucket. It works for single and multisite projects.

## Prerequisites

There are a few variables that need to be setup on platform.sh that are mandatory for the script to work.
1. env:AWS_BACKUP_BUCKET - holds the bucket name. Needs to be available atr runtime.
2. env:AWS_ACCESS_KEY_ID - holds the access key of a user that has access to the bucket. Needs to be available at runtime.
3. env:AWS_SECRET_ACCESS_KEY - holds the secret access key of a user that has access to the bucket. Needs to be available at runtime. Sensitive information.
Having awscli installed on platform.sh environment. 

## Installation
```
cd to-project-path
git clone git@github.com:drunomics/automatic-backups.git
```

## Usage

After cloning/copying the files in the project root directory, the scripts inside it can be used in .platform.app.yml.
1. First in the hooks section, under build the installation for awscli needs to be added. 
E.g.:
```
hooks:
    # Install AWS https://gitlab.com/contextualcode/platformsh-store-logs-at-s3/tree/master
    build: |
        pip install futures && pip install awscli --upgrade --user 2>/dev/null
```
2. Then in the mounts section a folder called drush-backups is needed. 
3. Structure of the files directory needs to look like this: /docroot/sites/site-name/files. 
4. Crons for platform.sh needs to be configured to use the scripts from automatic-backups directory. E.g.:
```
crons:
    drush-db-backup:
       spec: '0 1 * * *'
       cmd: |
       # db backup
       ./automatic-backups/platform_db_backup.sh
    aws-s3-files-daily:
       spec: '0 1 * * *'
       cmd: |
       # upload files to s3
       ./automatic-backups/files_daily.sh
```

5. Structure in S3 bucket will look like this: 
   1. There will be a global parent folder with same name as the name set in .platform.app.yml.
   2. Inside it there will be a sql directory which will hold directories for each existing branch, and inside the later one there will be the db files.
   3. Inside the parent directory will also be a folder called files-{site-name} which will hold the files of each site.
