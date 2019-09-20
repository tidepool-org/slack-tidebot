# Description:
#   Create Github Pull Requests with tidebot.
#
# Dependencies:
#   "githubot": "^1.0.1"
#
# Configuration:
#   HUBOT_GITHUB_TOKEN (see https://github.com/iangreenleaf/githubot)
#
# Commands:
#   tidebot create pr from <repo>/<branch> into <base> for <reviewer_username> to review "<body>"
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


githubToken = process.env.HUBOT_GITHUB_TOKEN

module.exports = (robot) ->
  github = require('githubot')(robot)

  robot.respond /create pr from ([-_\.a-zA-z0-9\/]+)\/([-_\.a-zA-z0-9\/]+)(?: into ([-_\.a-zA-z0-9\/]+))(?: for ([-_\.a-zA-z0-9\/]+) to review)?(?: "(.*)")?$/i, (msg) ->
    return if missingEnv(msg)

    base = msg.match[3]

    data = {
      title: "PR to merge #{msg.match[2]} into #{base}",
      head: msg.match[2],
      base: base,
      body: msg.match[5] || 'PR for review',
    }
    reviewers = {
        reviewers: [msg.match[4]]
    }

    github.handleErrors (response) ->
      switch response.statusCode
        when 404
          msg.send 'Error: Sorry TidePooler, this is not a valid repo that I have access to.'
        when 422
          msg.send "Error: Yo TidePooler, the pull request has already been created or the branch does not exist."
        else
          msg.send 'Error: Sorry TidePooler, something is wrong with your request.'

    github.post "repos/Tidepool-org/#{msg.match[1]}/pulls", data, (pr) ->
      msg.send "Success! Pull request created for #{msg.match[2]}. #{pr.html_url}"
    #   github.post "repos/Tidepool-org/integration-test/contents/flux/environments/develop/tidepool-helmrelease.yaml"
    github.post "repos/Tidepool-org/#{msg.match[1]}/pulls/#{pr.number}/requested_reviewers", reviewers, (test) ->
      msg.send test.html test.requested_reviewers[0].login
  missingEnv = (msg) ->
    unless githubToken?
      msg.send 'HUBOT_GITHUB_TOKEN is missing. Please ensure that it is set. See https://github.com/summera/hubot-github-create-pullrequests for more details about generating one.'

    !githubToken?
# integration-test/flux/environments/develop/tidepool-helmrelease.yaml