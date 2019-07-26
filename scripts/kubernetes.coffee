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
eventActions = require('./all')
eventTypesRaw = process.env['HUBOT_GITHUB_EVENT_NOTIFIER_TYPES']
eventTypes = []
announceRepoEvent = (adapter, data, eventType, cb) ->
  if eventActions[eventType]?
    eventActions[eventType](adapter, data, cb)
  else
    cb("Received a new #{eventType} event, just so you know.")
module.exports = (robot) ->
    robot.router.post '/hubot/gh-repo-events?room=github-events', (req, res) ->
        room = "github-events" || process.env["HUBOT_GITHUB_EVENT_NOTIFIER_ROOM"] || process.env["HUBOT_SLACK_ROOMS"]
        data = req.body
        comments = datas.comment.body
        eventType = req.headers["x-github-event"]
        adapter = robot.adapterName
        console.log("#{comments}")
        console.log("fun")
        # res.send "#{comments}"

        try

            filter_parts = eventTypes
                .filter (e) ->
                # should always be at least two parts, from eventTypes creation above
                parts = e.split(":")
                event_part = parts[0]
                action_part = parts[1]

                if event_part != eventType
                    return false # remove anything that isn't this event

                if action_part == "*"
                    return true # wildcard on this event

                if !data.hasOwnProperty('action')
                    return true # no action property, let it pass

                if action_part == data.action
                    return true # action match

                return false # no match, fail

            if filter_parts.length > 0
                announceRepoEvent adapter, comments, eventType, (what) ->
                    robot.messageRoom room, what
            else
                console.log "Ignoring #{eventType}:#{data.action} as it's not allowed."
        catch error
            robot.messageRoom room, "Whoa, I got an error: #{error}"
            console.log "Github repo event notifier error: #{error}. Request: #{req.body}"
        res.send "OK why wont this work"
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