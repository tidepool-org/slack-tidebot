# Description:
#   start of github scripts.
#
# Notes:
#   They are commented out by default.
#

# module.exports = (robot) ->
#     robot.router.post '/hubot/gh-repo-events?room=github-events', (req, res) ->
#         room = req.params.room
#         data   = if req.body.payload? then JSON.parse req.body.payload else req.body

#         robot.messageRoom "== Push data received: #{data.commits}"

#         res.send 'OK'
#         # https://slack-tidebot.herokuapp.com/hubot/gh-repo-events?room=%23github-events