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
LIB_DIR=${LIB_DIR:="$(dirname $0)/../lib/bash"}

#source "${LIB_DIR}/input-output.lib.sh"
#source "${LIB_DIR}/syslog.lib.sh"

##########
# Set the commands (if they have not been set before)

WEBAP_CMD="/usr/sbin/webapp-config"

LOCK_MSG="${LOCK_MSG_EN}"

UMASK=${UMASK:='077'}


################################################################################
# Functions
################################################################################

function info ()
{
   echo "$1" >&2
}

function error ()
{
   echo "$1" >&2
}

function die ()
{
   echo "$1" >&2
   exit 1
}


################################################################################
# The actual start of the script
################################################################################

##############
# Initialization

# Check if all commands are present

# Find instances to backup
if [ "${INSTANCES}" == "" ]
then
   INSTANCES="$( $WEBAP_CMD --list-installs mediawiki )"
fi

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
   else
      echo "${LOCK_MSG}" >${lockFile}
      chmod a+r ${lockFile}
   fi

done

echo "sleeping"
sleep 10

##############
# Dumping
#
info "Dumping the databases"
dumpLog="$( ${DBDUMP_CMD} &2>1 )"
if [ ${?} != 0 ]
then
   error "Dumping the databases failed with the following error:"
   error "${dumpLog}"
else
   info "Success. The dump says:"
   info "${dumpLog}"
fi

##############
# Copying
#
info "Runnig the copy command"
# copyLog="$( )"

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
   fi

done

