# Description:
#   Liveliness probe to keep the service alive 
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
#   NA
#
# Notes:
#   NA
#
module.exports = (robot) ->
    console.log "liveness probe installed"
    robot.router.get '/status', (req, res) ->
        res.send "OK"
