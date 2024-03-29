#!/bin/bash
################################################################################
# mediaWikiBackup.sh - Backup a MediaWiki with consisteny of the filesystem and database
################################################################################
#
# Copyright (C) 2014 stepping stone GmbH
#                    Switzerland
#                    http://www.stepping-stone.ch
#                    support@stepping-stone.ch
#
# Authors:
#  David Vollmer <david.vollmer@stepping-stone.ch>
#  
# This program is free software: you can redistribute it and/or
# modify it under the terms of the GNU Affero General Public 
# License as published  by the Free Software Foundation, version
# 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public
# License along with this program.
# If not, see <http://www.gnu.org/licenses/>.
#
# Description:
# This scripts creates a lockfile in every MediaWiki instance found via webapp-
# config to prevent changes on the database, dumps the databases via an exeternal
# dump script, runs a so called post job to copy the files and dumps away and
# removes the locks again.
#
# Usage:
# mediaWikiBackup.sh
#
# Example:
# mediaWikiBackup.sh
################################################################################

################################################################################
# Source and define logging functions
################################################################################

LIB_DIR=${LIB_DIR:="/usr/share/stepping-stone/lib/bash"}

source "${LIB_DIR}/input-output.lib.sh" && source "${LIB_DIR}/syslog.lib.sh"
if [ "${?}" != "0" ]
then
   echo "Could not source the needed libs" >&2
   exit 1
fi

# Check if the last command run successful
# $1: Name of the command
# $2: Exit status of the command
# $3: What to print if it failed
# $4: Severity as one of debug, info, error, die
function checkReturnStatus () {
   if [[ "${2}" != "0" ]]
   then
      # use 'error' as default severity
      severity="error"

      if [ "${4}" != "" ]
      then
         # set severity to parameter 4 if its set
         severity="${4}"
      fi

      # send messages to the specific loglevel
      ${severity} "Command ${1} failed with status ${2}: ${3}"

      # increase the error counter
      errorCount=$((errorCount + 1))

   else
      debug "Successfully run ${1}."

   fi
}

# Send mail
# $1: recipient
# $2: sender
# $3: subject
# $4: body
function sendWarning () {
   recipient="${1}"
   sender="${2}"
   subject="${3}"
   body="${4}"

   if [ -z "${recipient}" ]
   then
      checkReturnStatus "${MAIL_CMD}" "1" "Recipient is not set" "info"
      return 0
   fi
    
   cat << EOM | ${MAIL_CMD} -v ${recipient}
From: <${sender}>
To: <${recipient}>
Date: $( date -R )
subject: ${subject}
${body}
EOM
   checkReturnStatus "${MAIL_CMD}" "$?" "Check log of ${MAIL_CMD}"
}

info "Starting $(basename $0)"

################################################################################
# Define variables
################################################################################

##########
# Source the configuration file. It shall be under ../etc/mediaWikiBackup.conf
CONFIG_FILE="$(dirname $0)/../etc/$( basename $0 .sh ).conf"

source "$CONFIG_FILE"
checkReturnStatus "source $CONFIG_FILE" "$?" "" "die"

##########
# Set the commands (if they have not been set before)

WEBAP_CMD="/usr/sbin/webapp-config"

LOCK_MSG="${LOCK_MSG_EN}"

SCRIPT_LOCK="/var/run/$( basename $0 ).lock"

errorCount=0


################################################################################
# The actual start of the script
################################################################################

##############
# Initialization

# Set a lock to prevent concurrent running of the script
(
flock -n 9 || checkReturnStatus "locking" "nolock" "We seem to be already running. If not, remove the lock file ${SCRIPT_LOCK} manually." "die"

# Check if all commands are present
for cmd in "${WEBAP_CMD} ${MAIL_CMD}"
do
   test -x ${!cmd} || die "Missing command ${cmd}"
done

# Check command line parameters
while getopts ":i:" option
do
   case $option in
   i )
      INSTANCES="${OPTARG}"
      ;;
   : )
      echo "Option -${OPTARG} requires a parameter. Usage: $( basename $0 ) [-i instancePath]" >&2
      exit 1
      ;;
   * )
      echo "Unknown parameter ${OPTARG}. Usage: $( basename $0 ) [-i instancePath]" >&2
      exit 1
      ;;
   esac
done

# Find instances to backup
if [ "${INSTANCES}" == "" ]
then
   cmd="$WEBAP_CMD --list-installs mediawiki"
   INSTANCES="$( ${cmd} )"
   checkReturnStatus "${cmd}" "$?" "output is '${INSTANCES}'" "die"
fi

info "Going to process the following instances: $( echo "${INSTANCES}" | tr "\n" " " )"

##############
# Locking the MediaWiki instances
#

for instance in ${INSTANCES}
do
   info "Locking ${instance}"

   if ! [[ -d ${instance} ]]
   then
      checkReturnStatus "test existence of ${instance}" "1" "is ${instance} really a mediawiki?"
      echo "failed lock of ${instance}"
      # Skip this instance if its missing
      continue
   fi

   # Write the lockfile to prevent users from editing and show them a message
   lockFile="${instance}/${LOCK_FILE}"
   if [ -e ${lockFile} ]
   then
      error "The lockfile ${lockFile} already exists. Continuing anyway, but the database dump for this instance might not be consistent."
      errorCount=$((errorCount + 1))

   else
      # Write the message to the lock file
      echo "${LOCK_MSG}" >${lockFile}
      checkReturnStatus "writing to ${lockFile}" "$?" ""
      # Change permission so that the webserver can read the file
      chmod a+r ${lockFile}
      checkReturnStatus "chmod on ${lockFile}" "$?" ""
   fi

done


##############
# Dumping
#
info "Dumping the databases"
${DBDUMP_CMD}
checkReturnStatus "${DBDUMP_CMD}" "$?" "Check the mysql-dump script log"


##############
# Post command
#
info "Runnig the post command"
${POST_JOB}
checkReturnStatus "${POST_JOB}" "$?" "Check the online backup script log"


##############
# Unlocking
#
for instance in ${INSTANCES}
do
   info "Unlocking ${instance}"

   lockFile="${instance}/${LOCK_FILE}"
   rm ${lockFile}
   if [ ${?} != 0 ]
   then
      error "Could not remove lockfile ${lockFile}."
      if [ -e ${lockFile} ]
      then
         error "This instance (${instance}) will be locked until you manually remove the lockfile!"
      else
         error "Because the lockfile is missing"
      fi
      errorCount=$((errorCount + 1))
   fi

done

if [ ${errorCount} == 0 ]
then
   info "Everything went fine. Exiting."
   exit 0
else
   sendWarning "${RCP_MAIL}" "${SND_MAIL}" "$( basename $0 ) on $( hostname ) ended with errors." "There have been error during the run of $( basename $0 ) on $( hostname ). Please log in to the machine and have a look at the logfile"
   error "There have been errors. Exiting."
   exit 1
fi

# Remove the lock from the script
) 9>${SCRIPT_LOCK}
