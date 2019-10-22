#!/bin/bash
source ../.env
n=$1
counter=0
curlOutput=$(curl -X GET -H "Authorization: token $webhookToken" https://api.github.com/repos/tidepool-org/$n/hooks)
echo $curlOutput | jq "."
until [ "$tidebotWebhookLink" == "null" ]
do
tidebotWebhookLink=$(echo $curlOutput | jq ".[$counter].config.url")
if [ $tidebotWebhookLink == '"http://tidebot.tidepool.org/hubot/gh-repo-events?room=github-events"' ] ; then
    hookID=$(echo $curlOutput | jq ".[$counter].id")
    curl -X DELETE -H "Authorization: token $webhookToken" https://api.github.com/repos/tidepool-org/$n/hooks/$hookID
    echo "Tidebot webhook was deleted"
else
    echo "Tidebot webhook does not exist or has already been deleted"
fi
((counter++))
done
echo All done