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
#   tidebot create pr from <Tidepool-org>/<repo>/<branch> into <base> for <reviewer_username> to review "<body>"
#
# Notes:
# repo (required): Repository where your branch exists.
# branch (required): Name of branch.
# base (optional): Name of branch you would like to request to merge into. Master by default.
# body (optional): Message to create with pull request. Empty by default.
#   By default, the target branch will be master and the body empty.
#
#   You will need to create and set HUBOT_GITHUB_TOKEN.
#   The token will need to be made from a user that has access to repo(s)
#   you want hubot to interact with.
#

module.exports = (robot) ->
    # robot.router.post '/hubot/gh-repo-events?room=github-events', (req, res) ->
    #     room = req.params.room
    #     data = if req.body.payload? then JSON.parse req.body.payload else req.body
    #     comment = data.comment
    robot.hear /\/deploy/, (res) ->
        res.send "this may not work"