#!/bin/bash

NC='\033[0m'          # Text Reset
BGreen='\033[1;32m'   # Green
BYellow='\033[1;33m'  # Yellow
#BBlack='\033[1;30m'  # Black
#BRed='\033[1;31m'    # Red
BBlue='\033[1;34m'    # Blue
#BPurple='\033[1;35m' # Purple
#BCyan='\033[1;36m'   # Cyan
#BWhite='\033[1;37m'  # White

istioctl create-remote-secret \
  --context="${CTX_CLUSTER1}" \
  --name=cluster1 | \
  oc --context="${CTX_CLUSTER2}" apply -f -
  
istioctl create-remote-secret \
  --context="${CTX_CLUSTER2}" \
  --name=cluster2 | \
  oc --context="${CTX_CLUSTER1}" apply -f -

