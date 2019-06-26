# Description:
#   Example scripts for you to examine and try out.
#
# Notes:
#   They are commented out by default, because most of them are pretty silly and
#   wouldn't be useful and amusing enough for day to day huboting.
#   Uncomment the ones you want to try and experiment with.
#
#   These are from the scripting documentation: https://github.com/github/hubot/blob/master/docs/scripting.md

module.exports = (robot) ->
    robot.router.post '/hubot/gh-repo-events?room=%23github-events', (req, res) ->
        room = req.params.room
        data   = if req.body.payload? then JSON.parse req.body.payload else req.body

        robot.messageRoom "== Push data received: #{data.commits}"

        res.send 'OK'