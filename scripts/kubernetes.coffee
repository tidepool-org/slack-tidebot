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
#   /depoly <repo> comment on pr
#
# Notes:
#   You will need to create and set HUBOT_GITHUB_TOKEN.
#   The token will need to be made from a user that has access to repo(s)
#   you want hubot to interact with.
#
# do we want to allow this script to deploy to production
YAML = require('yaml')
HubotSlack = require('hubot-slack')
eventActions = require('./all')
eventTypesRaw = process.env['HUBOT_GITHUB_EVENT_NOTIFIER_TYPES']
Base64 = require('js-base64').Base64;
eventTypes = []
environmentToRepoMap = {
    "qa1": "cluster-development",
    "qa2": "cluster-development",
    "int": "cluster-integration",
    "prd": "cluster-production"
}
environmentToEnv = {
    "dev": "qa1",
    "stg": "qa2",
    "int": "cluster-integration",
    "prd": "cluster-production"
}
module.exports = (robot) ->
    github = require('githubot')(robot)
    robot.router.post '/hubot/gh-repo-events', (req, res) ->
        prCommentEnvExtractor = (comments) ->
            match = comments.match(/^.*?\/\bdeploy\s+([-_\.a-zA-z0-9]+)\s*([-_\.a-zA-z0-9\/]+)?/)
            {
                Repo: match[1],
                Env: match[2]
            }
        room = "github-events" || process.env["HUBOT_GITHUB_EVENT_NOTIFIER_ROOM"] || process.env["HUBOT_SLACK_ROOMS"]
        datas = req.body
        comments = datas.comment.body
        repository = datas.repository.name
        branches = datas.issue.pull_request.url
        branch = (branches) ->
            x=0
            github.get branches, (branch) ->
                x=branch
            x.head.ref
        console.log(branch)
        eventType = req.headers["x-github-event"]
        adapter = robot.adapterName
        console.log("#{comments}")
        console.log("fun")
        config = prCommentEnvExtractor(comments)
        githubManifest = github.get "repos/tidepool-org/#{config.Repo}/contents/flux/environments/#{config.Env}/tidepool-helmrelease.yaml", (ref) -> 
            console.log(config.Repo)
            console.log(config.Env)
            # manifest = githubManifest
            console.log(githubManifest)
            deploy = {
                message: "Deployed #{config.Repo}",
                content: Base64.decode(githubManifest.content),
                sha: manifest.sha
            }
        # announceRepoEvent adapter, datas, eventType, (what) ->
        # finish = switch match[1]
        #     when "qa1" then statements
        #     when "prd" then statements
        #     when "develop-branch" then statements
        #     when "qa2" then statements
        #     when "release-branch" then statements
        #     when "ci-{date-random}" then statements
        #     when "external" then statements
        #     when "staging" then statements
        #     when "chartmuseum" then statements
        #     when "thanos" then statements
        #     else statements
        robot.messageRoom room, "#{githubManifest.deploy.sha}"
        res.send "#{githubManifest.deploy.content}"

# announceRepoEvent = (adapter, datas, eventType, cb) ->
#   if eventActions[eventType]?
#     eventActions[eventType](adapter, datas, cb)
#   else
#     cb("Received a new #{eventType} event, just so you know.")
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
        # github.post "repos/Tidepool-org/integration-test/contents/flux/environments/develop/tidepool-helmrelease.yaml", deploy, (change) ->
        
        
        # ^.*?\b\/deploy\b(.*?[-_\.0-9a-zA-Z].*)?$
        # ^.*?\/\bdeploy\b.*?([-_\.a-zA-z0-9]+) add a $ at end if you want the last word captured
# function that takes users pr comment and extracts the Repo and Environment

