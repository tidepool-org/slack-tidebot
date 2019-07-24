# Description:
#   Deploy to kubernetes based off of user comment of </deploy> in PR comment.
#
# Dependencies:
#   "githubot": "^1.0.1"
#   "hubot-github-repo-event-notifier": "^1.8.1"
#   "hubot-github-adapter"
#
# Configuration:
#   HUBOT_GITHUB_TOKEN (see https://github.com/iangreenleaf/githubot)
#
# Commands:
#   /depoly <place to be deployed> comment on pr
#
# Notes:
#   You will need to create and set HUBOT_GITHUB_TOKEN.
#   The token will need to be made from a user that has access to repo(s)
#   you want hubot to interact with.
#
HubotSlack = require 'hubot-slack'

module.exports = (robot) ->
    # robot.router.post '/hubot/gh-repo-events', (req, res) ->
    #     room = github-events || process.env["HUBOT_GITHUB_EVENT_NOTIFIER_ROOM"] || process.env["HUBOT_SLACK_ROOMS"]
    #     data = if req.body.payload? then JSON.parse req.body.payload else req.body
    #     comment = data.comment.body
    #     console.log("#{comment}")
    #     console.log("fun")

    # robot.hear /^.*?\/\bdeploy\b.*?([-_\.a-zA-z0-9]+)/, (res) ->
    #     res.send "this is a test to deploy #{res.match[1]}"
        
    # robot.listen( 
    #     (message) ->
    #         match = message.match(/^.*?\/\bdeploy\b.*?([-_\.a-zA-z0-9]+)/)
    #     (res) ->
    #         res.reply "this is a test to deploy #{res.match[1]}")  
        # deploy = {
        #     message: "Deployed #{res.match[1]}",
        #     content: msg.match[3],
        #     sha: base,
        #     body: msg.match[6] || 'PR for review',
        # }
        # github.post "repos/Tidepool-org/integration-test/contents/flux/environments/develop/tidepool-helmrelease.yaml", data, (deploy) ->
        
        
        # ^.*?\b\/deploy\b(.*?[-_\.0-9a-zA-Z].*)?$
        # ^.*?\/\bdeploy\b.*?([-_\.a-zA-z0-9]+) add a $ at end if you want the last word captured