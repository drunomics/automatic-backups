# Automatic Backups for Platform.sh

Provide a central script that can be used in .platform.app.yml cron to back up db and files of the platform.sh hosted
drupal website to a AWS S3 bucket or to a SFTP server. It works for single and multisite projects.

# Having AWS S3 as 3rd party

## Prerequisites

There are a few variables that need to be setup on platform.sh that are mandatory for the script to work.
1. env:PROJECT_NAME - holds a specific machine-readable name for the project.
2. env:AWS_BACKUP_BUCKET - holds the bucket name. Needs to be available at runtime.
3. env:AWS_ACCESS_KEY_ID - holds the access key of a user that has access to the bucket. Needs to be available at runtime.
4. env:AWS_SECRET_ACCESS_KEY - holds the secret access key of a user that has access to the bucket. Needs to be available at runtime. Sensitive information.
Having awscli installed on platform.sh environment.
5. env:ENCRYPTION_ALG - holds the encryption algorithm used to encrypt db backups. To get a complete list, run 'openssl list -cipher-algorithms'.
6. env:ENABLE_ENCRYPTION - should hold 0 for No and 1 for Yes. Defaults to 0.
11. env:SECRET_ENC_PASS - should contain a secure string password that will encrypt/decrypt the backups. Sensitive variable.

# Having SFTP server as 3rd party

## Prerequisites
There are a few variables that need to be setup on platform.sh that are mandatory for the script to work.
1. env:PROJECT_NAME - holds a specific machine-readable name for the project.
2. env:SFTP_SERVER - holds the server name. Needs to be available at runtime.
3. env:SFTP_USERNAME - holds the user that has access to the server. Needs to be available at runtime.
4. env:SSH_SECRET_KEY - holds the ssh secret key of the user that has access to the server. Needs to be available at runtime. Sensitive information.
5. env:SSH_PUBLIC_KEY - holds the ssh public key of the user that has access to the server. Needs to be available at runtime. Sensitive information.
6. env:SFTP_DIRECTORY - holds the directory from the server where the user has access to copy/create files.
7. env:SFTP_PORT - holds the port of the server where the user has access to copy/create files (OPTIONAL).
8. env:SFTP_DAYS_EXP - holds the number of days a backup should be held on the server. When a file passes this
   expiration date only the files created on first day of the month will be kept.
9. env:ENCRYPTION_ALG - holds the encryption algorithm used to encrypt db backups.
10. env:ENABLE_ENCRYPTION - should hold 0 for No and 1 for Yes.
11. env:SECRET_ENC_PASS - should contain a secure string password that will encrypt/decrypt the backups. Sensitive variable.


## Installation
```
cd to-project-path
git clone git@github.com:drunomics/automatic-backups.git
```

## Usage

After cloning/copying the files in the project root directory, the scripts inside it can be used in .platform.app.yml.
Before adding the variables in platform.sh, create a bucket on AWS or a SFTP server, then add a IAM user and add full access for that user to the bucket and generate the access keys.
1. First in the hooks section, under build the installation for awscli(when using AWS S3) needs to be added.
E.g.:
```
hooks:
    # Install AWS https://gitlab.com/contextualcode/platformsh-store-logs-at-s3/tree/master
    build: |
        pip install futures && pip install awscli --upgrade --user 2>/dev/null
```
2. Then in the mounts section a folder called drush-backups is needed.
3. Structure of the files directory could look like this: /files/site-name/files, or /files/site-name, or /docroot/sites/site-name/files, or /web/sites/site-name/files. If
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

7. Encryption/Decryption
   1. By default, db backups are not encrypted before they are uploaded to the 3rd party storage. In order to enable encryption add variable env:ENABLE_ENCRYPTION with value 1.
In order to decrypt it, access to the platform.sh server is needed in order to get the secret password that was used to encrypt the file.
   2. For decryption: copy a backup file from the server with "scp -r ${SFTP_USERNAME}@${SFTP_SERVER}:~/${SFTP_DIRECTORY}/drush-backups/* ./drush-backups",
   then decrypt the file using "openssl enc -"$ENCRYPTION_ALG" -d -in drush-backups/app/$SITE/2022-m07-d27/{db_name}_20220727_135638-enc.sql.gz -out drush-backups/{db_name}_20220727_135638.sql.gz -pass pass:"$SECRET_ENC_PASS""(adapt file names by case),

## Restoring
First upload the file to platform.sh: 
``` rsync -avz path/to/backup/file "$(platform ssh --pipe)":drush-backups ```
Then run ```platform ssh```, ```cd drush-backups/```, ```gzip -d {db_name}_20220727_135638.sql.gz```, ```cd ../```, 
```drush sqlc < drush-backups/{DB_NAME}_20220727_135638.sql```.
To get the files from AWS, use this command: ```aws s3 cp s3://{bucket_name}/{site_name}/files-default/{env_name}/files {local_directory} --recursive```
To get files from SFTP use rsync: ```rsync -avz path/to/files "$(platform ssh --pipe)":files```.

## Backup rotation strategy
1. AWS S3: When the script is uploading the db backups on S3 it is also marking them with a certain tag. Dbs from the first day of the month are marked "archive"
   while all the other ones are marked "rolling". Based on this a lifecycle can be setup on AWS to clean-up old files.
   Instructions on how to create on are here: https://docs.aws.amazon.com/AmazonS3/latest/userguide/how-to-set-lifecycle-configuration-intro.html.
   The rule that needs to be added should target objects with tag sqldump and value rolling. Set an expiration limit and all the rolling tagged objects will get deleted.
   This won't apply for files directories. They are not tagged and they will get deleted if passed the expiration date.
2. SFTP: By default dbs will be help for 180 days unless env:SFTP_DAYS_EXP is set to another value. After this expiration date only the files created on first day of the month will be kept.
   Public files won't expire because there will be just one backup for month.