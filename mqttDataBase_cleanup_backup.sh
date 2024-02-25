#!/bin/bash

# Define variables
BACKUP_DIR="/var/backups/mongodb"
LOGFILE_DIR="/var/log/mongodb"
DATABASE="mqttDataBase"
COLLECTION="driverHistoryCollection"
DATE=$(date +'%Y-%m-%d')
LOG_FILE="${LOGFILE_DIR}/${DATABASE}_cleanup_backup.log"  # Modified log file name
# get current data time utc formate
currentDate=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
# get date time ISO format from last one year now compare only date assume time as 00:00:00
oneYearAgo=$(date -u -d "$(date -u -d "$currentDate" -I) -1 year" +"%Y-%m-%dT00:00:00.000Z")

# Define functions
log_message() {
    local level=$1
    local message=$2
    echo "$(date +'%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE"
}


# Check if backup directory exists, if not, create it
if [ -d "$BACKUP_DIR" ]; then
    log_message "INFO" "Backup directory '$BACKUP_DIR' found."
else
    mkdir -p "$BACKUP_DIR"
    log_message "INFO" "Backup directory '$BACKUP_DIR' not found. Created directory."
fi

# Check if backup directory exists, if not, create it
if [ -d "$LOGFILE_DIR" ]; then
    log_message "INFO" "Backup directory '$LOGFILE_DIR' found."
else
    mkdir -p "$LOGFILE_DIR"
    log_message "INFO" "Backup directory '$LOGFILE_DIR' not found. Created directory."
fi


# 1 - verify the is fullbackup found
if ls "${BACKUP_DIR}/${DATABASE}_base_backup_"*; then
    log_message "INFO" "Base backup archive found. Skipping full backup and cleanup."
else
    # this entire database backup, which made before any clean up activity start,
    log_message "INFO" "Starting mqttDataBase database base backup process..."
    mongodump --db ${DATABASE} --gzip --archive="$BACKUP_DIR/${DATABASE}_base_backup_$DATE.archive" >> "$LOG_FILE" 2>&1

    if [ $? -ne 0 ]; then
        log_message "ERROR" "mqttDataBase database base backup process failed. See $LOG_FILE for details."
        exit 1
    fi
    log_message "INFO" "mqttDataBase database base backup process completed successfully."
fi


# 2 - get less than 1 year data from driverHistoryCollection, make backup and compress
log_message "INFO" "Starting driverHistoryCollection collection less than 1 year data backup process..."
mongodump --gzip --archive="$BACKUP_DIR/${DATABASE}_${COLLECTION}_less_than_one_year_$DATE.archive" --db=mqttDataBase --collection=driverHistoryCollection --query '{"timestamp": {"$gte": {"$date": "'$oneYearAgo'"}}}' >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    log_message "ERROR" "driverHistoryCollection collection less than 1 year data backup process failed. See $LOG_FILE for details."
    exit 1
fi
log_message "INFO" "driverHistoryCollection collection less than 1 year data backup process completed successfully."


# 3 - get more than 1 year data from driverHistoryCollection, make backup and compress
log_message "INFO" "Starting driverHistoryCollection collection last l year data backup process..."
mongodump --gzip --archive="$BACKUP_DIR/${DATABASE}_${COLLECTION}_more_than_one_year_$DATE.archive" --db=mqttDataBase --collection=driverHistoryCollection --query '{"timestamp": {"$lte": {"$date": "'$oneYearAgo'"}}}' >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "ERROR" "driverHistoryCollection collection more than 1 year data backup process failed. See $LOG_FILE for details."
    exit 1
fi
log_message "INFO" "driverHistoryCollection collection more than 1 year data backup process completed successfully."



# 4 after successfully backup and compress with above steps, remove more than 1 year data from driverHistoryCollection
log_message "INFO" "Starting remove driverHistoryCollection collection more than 1 year data process..."
mongosh --quiet --eval "
    const collection = db.getCollection('driverHistoryCollection');
    const result = collection.drop();
    print('Dropped collection: ' + (result ? 'Success' : 'Failed'));

    db.createCollection('driverHistoryCollection');
    print('Created collection: driverHistoryCollection');

    const indexResult = db.driverHistoryCollection.createIndex({'timestamp': 1});
    print('Created index: ' + indexResult);
" mongodb://localhost:27017/mqttDataBase  >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "ERROR" "remove driverHistoryCollection collection more than 1 year data process failed. See $LOG_FILE for details."
    exit 1
fi
log_message "INFO" "remove driverHistoryCollection collection more than 1 year data process completed successfully."


# 5 this is driverHistoryCollection restore which is contain only less than 1 year data only,
log_message "INFO" "Starting restore driverHistoryCollection less than 1 year data process..."
mongorestore --db ${DATABASE} --gzip --archive="$BACKUP_DIR/${DATABASE}_${COLLECTION}_less_than_one_year_$DATE.archive" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "ERROR" "restore driverHistoryCollection less than 1 year data process failed. See $LOG_FILE for details."
    exit 1
fi
log_message "INFO" "restore driverHistoryCollection less than 1 year data process completed successfully."