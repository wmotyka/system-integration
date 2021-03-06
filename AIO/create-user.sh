#!/bin/bash
# ===============LICENSE_START=======================================================
# Acumos Apache-2.0
# ===================================================================================
# Copyright (C) 2018 AT&T Intellectual Property. All rights reserved.
# ===================================================================================
# This Acumos software file is distributed by AT&T and Tech Mahindra
# under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# This file is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===============LICENSE_END=========================================================
#
#.What this is: Utility to create a user via the Acumos common-dataservice API.
#. Used by peer-test.sh to create an admin user for federation setup etc. Also
#. useful to automate creation of test users for various test cases.
#.
#.Prerequisites:
#.- Acumos deployed via oneclick_deploy.sh, and acumos-env.sh as updated by it
#.
#.Usage:
#.$ bash create-user.sh <username> <password> <firstName> <lastName> <emailId> [role]
#.  username: username for user
#.  password: password for user
#.  firstName: first name
#.  lastName: last name
#.  emailId: email address
#.  role: optional role to set for the user (e.g. "admin")
#

trap 'fail' ERR

function fail() {
  log "$1"
  exit 1
}

function log() {
  fname=$(caller 0 | awk '{print $2}')
  fline=$(caller 0 | awk '{print $1}')
  echo; echo "$fname:$fline ($(date)) $1"
}

function register_user() {
  curl -k -s -o ~/json -X POST \
    https://$ACUMOS_HOST:$ACUMOS_KONG_PROXY_SSL_PORT/api/users/register \
    -H "Content-Type: application/json" \
    -d "{\"request_body\":{ \"firstName\":\"$firstName\",
         \"lastName\":\"$lastName\", \"emailId\":\"$emailId\",
         \"username\":\"$username\", \"password\":\"$password\",
         \"active\":true}}"
}

function find_role() {
  trap 'fail' ERR
  log "Finding role name $1"
  curl -s -o ~/json -u $ACUMOS_CDS_USER:$ACUMOS_CDS_PASSWORD \
    http://$ACUMOS_CDS_HOST:$ACUMOS_CDS_PORT/ccds/role
  roles=$(jq -r '.content | length' ~/json)
  i=0; roleId=""
  trap - ERR
  while [[ $i -lt $roles && "$roleId" == "" ]] ; do
    name=$(jq -r ".content[$i].name" ~/json)
    if [[ "$name" == "$1" ]]; then
      roleId=$(jq -r ".content[$i].roleId" ~/json)
    fi
    ((i++))
  done
  trap 'fail' ERR
}

function create_role() {
  trap 'fail' ERR
  log "Create role name $1"
  curl -s -o ~/json -u $ACUMOS_CDS_USER:$ACUMOS_CDS_PASSWORD -X POST \
  http://$ACUMOS_CDS_HOST:$ACUMOS_CDS_PORT/ccds/role \
    -H "accept: */*" -H "Content-Type: application/json" \
    -d "{\"name\": \"$1\", \"active\": true}"
  created=$(jq -r '.created' ~/json)
  if [[ "$created" == "null" ]]; then
    cat ~/json
    fail "Role $1 creation failed"
  fi
  roleId=$(jq -r '.roleId' ~/json)
}

function assign_role() {
  trap 'fail' ERR
  log "Assign role name $2 to user $1"
  curl -s -o ~/json -u $ACUMOS_CDS_USER:$ACUMOS_CDS_PASSWORD \
    http://$ACUMOS_CDS_HOST:$ACUMOS_CDS_PORT/ccds/user
  users=$(jq -r '.content | length' ~/json)
  i=0; userId=""
  trap - ERR
  while [[ $i -lt $users && "$userId" == "" ]] ; do
    loginName=$(jq -r ".content[$i].loginName" ~/json)
    if [[ "$loginName" == "$1" ]]; then
      userId=$(jq -r ".content[$i].userId" ~/json)
    fi
    ((i++))
  done
  trap 'fail' ERR
  find_role $2
  curl -s -o ~/json -u $ACUMOS_CDS_USER:$ACUMOS_CDS_PASSWORD -X POST \
    http://$ACUMOS_CDS_HOST:$ACUMOS_CDS_PORT/ccds/user/$userId/role/$roleId
  status=$(jq -r '.status' ~/json)
  if [[ $status -ne 200 ]]; then
    cat ~/json
    fail "Role assignment failed, status $status"
  fi
}

function setup_user() {
  trap 'fail' ERR
  log "Create user $username"
  register_user
  while [[ $(grep -c "An unexpected error occurred" ~/json) -gt 0 ]] ; do
    log "Portal user registration API is not yet active, waiting 10 seconds"
    sleep 10
    register_user
  done
  if [[ "$(jq -r '.error_code' ~/json)" != "100" ]]; then
    cat ~/json
    fail "User account creation failed"
  fi
  echo "Portal user account $username created"

  if [[ "$role" != "" ]]; then
    find_role $role
    if [[ "$roleId" == "" ]]; then
      create_role $role
    fi
    assign_role $username $role
  fi
  log "Resulting user account record"
  curl -s -u $ACUMOS_CDS_USER:$ACUMOS_CDS_PASSWORD http://$ACUMOS_CDS_HOST:$ACUMOS_CDS_PORT/ccds/user/$userId
}

source acumos-env.sh

if [[ $# -ge 5 ]]; then
  username=$1
  password=$2
  firstName=$3
  lastName=$4
  emailId=$5
  role=$6
  setup_user
  log "User creation is complete"
else
  grep '#. ' $0 | sed -i -- 's/#.//g'
fi
