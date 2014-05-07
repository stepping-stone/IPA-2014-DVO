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
# Licensed under the EUPL, Version 1.1.
#
# You may not use this work except in compliance with the
# Licence.
# You may obtain a copy of the Licence at:
#
# http://www.osor.eu/eupl
#
# Unless required by applicable law or agreed to in
# writing, software distributed under the Licence is
# distributed on an "AS IS" basis,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
# See the Licence for the specific language governing
# permissions and limitations under the Licence.
#
# Description:
# <LONGER-DESCRIPTION>
#
# Usage:
# mediaWikiBackup.sh <OPTIONS-AND-ARGUMENTS>
#
# Example:
# mediaWikiBackup.sh <EXAMPLE-OPTIONS-AND-ARGUMENTS>
################################################################################



################################################################################
# Define variables and source libraries
################################################################################

##########
# Source the configuration file. It shall be under ../etc/mediaWikiBackup.conf
CONFIG_FILE="$(dirname $0)/../etc/$( basename $0 .sh ).conf"

source "$CONFIG_FILE"

##########
# Source some libraries
# LIB_DIR=${LIB_DIR:="$(dirname $0)/../lib/bash"}
LIB_DIR=${LIB_DIR:="/usr/share/stepping-stone/lib/bash"}

source "${LIB_DIR}/input-output.lib.sh" && source "${LIB_DIR}/syslog.lib.sh"
if [ ${?} != 0 ]
then
   echo "Could not source the needed libs" >&2
   exit 1
fi

info "Starting $(basename $0)"

##########
# Set the commands (if they have not been set before)

WEBAP_CMD="/usr/sbin/webapp-config"

LOCK_MSG="${LOCK_MSG_EN}"

errorCount=0

################################################################################
# Functions
################################################################################

# Check if the last command run successful
# $1: Name of the command
# $2: Exit status of the command
# $3: What to print if it failed
# $4: Severity as one of debug, info, error, die
function checkCmd () {
   if [ ${?} != 0 ]
   then
      severity="error"
      if [ "${4}" != "" ]
      then
         severity="${4}"
      fi

      ${severity} "Command ${1} failed with status ${2}: ${3}"
      errorCount=$((errorCount + 1))
   else
      debug "Successfully run ${1} "
   fi
}

################################################################################
# The actual start of the script
################################################################################

##############
# Initialization

# Check if all commands are present
for cmd in "${WEBAP_CMD}"
do
   test -x ${!cmd} || die "Missing command ${cmd}"
done

# Find instances to backup
if [ "${INSTANCES}" == "" ]
then
   cmd="$WEBAP_CMD --list-installs mediawiki"
   INSTANCES="$( ${cmd} )"
   checkCmd "${cmd}" "$?" "output is '${INSTANCES}'" "die"
fi

info "Found the following instances: $( echo "${INSTANCES}" | tr "\n" " " )"

##############
# Locking
#

for instance in ${INSTANCES}
do
   info "Locking ${instance}"

   # Write the lockfile to prevent users from editing and show them a message
   lockFile="${instance}/${LOCK_FILE}"
   if [ -e ${lockFile} ]
   then
      error "The lockfile ${lockFile} already exists. Continuing anyway, but the database dump for this instance might not be consistent."
      errorCount=$((errorCount + 1))
   else
      # Write the message to the lock file
      echo "${LOCK_MSG}" >${lockFile}
      checkCmd "writing to ${lockFile}" "$?" ""
      # Change permission so that the webserver can read the file
      chmod a+r ${lockFile}
      checkCmd "chmod on ${lockFile}" "$?" ""
   fi

done


##############
# Dumping
#
info "Dumping the databases"
${DBDUMP_CMD}
checkCmd "${DBDUMP_CMD}" "$?" "Check the mysql-dump script log"


##############
# Copying
#
info "Runnig the copy command"
${POST_JOB}
checkCmd "${POST_JOB}" "$?" "Check the online backup script log"


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
   error "There have been errors. Exiting."
   exit 1
fi
