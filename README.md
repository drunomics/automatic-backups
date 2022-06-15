# Automatic Backups for Platform.sh

Provide a central script that can be used in .platform.app.yml cron to back up db and files of the platform.sh hosted
drupal website to a AWS S3 bucket or to a SFTP server. It works for single and multisite projects.

# Having AWS S3 as 3rd party

## Prerequisites

There are a few variables that need to be setup on platform.sh that are mandatory for the script to work.
1. env:PROJECT_NAME - holds a specific machine readable name for the project.
2. env:AWS_BACKUP_BUCKET - holds the bucket name. Needs to be available at runtime.
3. env:AWS_ACCESS_KEY_ID - holds the access key of a user that has access to the bucket. Needs to be available at runtime.
4. env:AWS_SECRET_ACCESS_KEY - holds the secret access key of a user that has access to the bucket. Needs to be available at runtime. Sensitive information.
Having awscli installed on platform.sh environment. 

# Having SFTP server as 3rd party

## Prerequisites 
There are a few variables that need to be setup on platform.sh that are mandatory for the script to work.
1. env:PROJECT_NAME - holds a specific machine readable name for the project.
2. env:SFTP_SERVER - holds the server name. Needs to be available at runtime.
3. env:SFTP_USERNAME - holds the user that has access to the server. Needs to be available at runtime.
4. env:SSH_SECRET_KEY - holds the ssh secret key of the user that has access to the server. Needs to be available at runtime. Sensitive information.
5. env:SSH_PUBLIC_KEY - holds the ssh public key of the user that has access to the server. Needs to be available at runtime. Sensitive information.
6. env:SFTP_DIRECTORY - holds the directory from the server where the user has access to copy/create files.
7. env:SFTP_PORT - holds the port of the server where the user has access to copy/create files.
8. env:SFTP_DAYS_EXP - holds the number of days a backup should be help on the server. When a file passes this
   expiration date only the files created on first day of the month will be kept.


## Installation
```
cd to-project-path
git clone git@github.com:drunomics/automatic-backups.git
```

## Usage

After cloning/copying the files in the project root directory, the scripts inside it can be used in .platform.app.yml.
1. First in the hooks section, under build the installation for awscli(when using AWS S3) needs to be added. 
E.g.:
```
hooks:
    # Install AWS https://gitlab.com/contextualcode/platformsh-store-logs-at-s3/tree/master
    build: |
        pip install futures && pip install awscli --upgrade --user 2>/dev/null
```
2. Then in the mounts section a folder called drush-backups is needed. 
3. Structure of the files directory could look like this: /files/site-name/files, or /docroot/sites/site-name/files, or /web/sites/site-name/files. If  
4. Crons for platform.sh needs to be configured to use the scripts from automatic-backups directory. E.g.:
```
crons:
    drush-db-backup:
       spec: '0 1 * * *'
       cmd: ./automatic-backups/platform_db_backup.sh
    aws-s3-files-daily:
       spec: '0 2 * * *'
       cmd: ./automatic-backups/files_daily.sh
```
Note: better to not run db and files cron at the same time.

5. Structure in S3 bucket will look like this: 
   1. There will be a global parent folder with same name as the name set in env:PROJECT_NAME variable .platform.app.yml.
   2. Inside it there will be a sql directory which will hold directories for each existing branch, and inside the later one there will be the db files.
   3. Inside the parent directory will also be a folder called files-{site-name} which will hold the files of each site.

6. Structure of directories on SFTP server will look like this:
   1. There will be a global folder defined in env:SFTP_DIRECTORY which will hold a folder with the files and one with the dbs.

7. Clean-up of old backups: 
   1. AWS S3: When the script is uploading the db backups on S3 it is also marking them with a certain tag. Dbs from the first day of the month are marked "archive" 
   while all the other ones are marked "rolling". Based on this a lifecycle can be setup on AWS to clean-up old files.
   Instructions on how to create on are here: https://docs.aws.amazon.com/AmazonS3/latest/userguide/how-to-set-lifecycle-configuration-intro.html. 
   The rule that needs to be added should target objects with tag sqldump and value rolling. Set an expiration limit and all the rolling tagged objects will get deleted.
   This won't apply for files directories. They are not tagged and they will get deleted if passed the expiration date.
   2. SFTP: By default dbs will be help for 180 days unless env:SFTP_DAYS_EXP is set to another value. After this expiration date only the files created on first day of the month will be kept.
Public file won't expire because there will be just one backup for month.