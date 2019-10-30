#!/bin/bash
source ../.env
json='{
  "name": "web",
  "active": true,
  "events": [
     "commit_comment",
     "create",
     "delete",
     "deployment",
     "deployment_status",
     "issue_comment",
     "issues",
     "page_build",
     "pull_request_review_comment",
     "pull_request",
     "push",
     "repository",
     "release",
     "status",
     "ping",
     "pull_request_review"
  ],
  "config": {
    "url": "URL",
    "content_type": "json",
    "insecure_ssl": "0"
  }
}'
Data="http://tidebot.tidepool.org/hubot/gh-repo-events?room=github-events"
newJson=$(echo $json | sed -e "s!URL!$Data!")
n=$1
curlOutput=$(curl -X POST -H "Authorization: token $webhookToken" -d "$newJson" https://api.github.com/repos/tidepool-org/$n/hooks)
errorMessage=$(echo $curlOutput | jq '.errors[0].message')
errorCount=$(echo $curlOutput | jq '.errors' | grep { | wc -l)
if [ $errorCount != "0" ] ; then
      echo "There was an issue with adding the webhook: $errorMessage. You either do not have access to editing this repository, hook already exists, or the repository does not exist. Please recheck your input"
else 
      echo $curlOutput
      echo "Tidebot webhook was added to https://github.com/tidepool-org/$n/settings/hooks"
 fi
 