# Description:
#   Deploy to kubernetes based off of user comment </deploy> <environment> in PR comment.
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
#   /deploy <environment> 
#
# Notes:
#   You will need to create and set HUBOT_GITHUB_TOKEN.
#   The token will need to be made from a user that has access to repo(s)
#   you want hubot to interact with.
#
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
    "prd": "cluster-production",
    "test": "integration-test"
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
        room = "github-events" || process.env["HUBOT_GITHUB_EVENT_NOTIFIER_ROOM"] || process.env["HUBOT_SLACK_ROOMS"]
        datas = req.body
        comments = datas.comment.body
        sender = datas.sender.login
        serviceRepo = datas.repository.name
        branches = datas.issue.pull_request.url
        github.get branches, (branch) ->
            # function that takes users pr comment and extracts the Repo and Environment
            prCommentEnvExtractor = (comments) ->
                match = comments.match(/^.*?\/\bdeploy\s+([-_\.a-zA-z0-9]+)\s*?/)
                {
                    Env: match[1]
                    Repo: environmentToRepoMap[match[1]],
                }
            serviceBranch = branch.head.ref
            config = prCommentEnvExtractor(comments)
            kubernetesGithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/clusters/development/flux/environments/#{config.Env}/tidepool-helmrelease.yaml"
            
            github.get kubernetesGithubYamlFile, (ref) -> 
                yamlFileDecoded = Base64.decode(ref.content)
                yamlFileParsed = YAML.parse(yamlFileDecoded)
                repoDestination = "flux.weave.works/tag." + serviceRepo
                dockerImageFilter = "glob:" + serviceBranch + "-*"
                yamlFileParsed.metadata.annotations[repoDestination] = dockerImageFilter
                newYamlFileUpdated = YAML.stringify(yamlFileParsed)
                newYamlFileEncoded = Base64.encode(newYamlFileUpdated)
                deploy = {
                    message: "#{sender} deployed #{serviceRepo} to #{config.Env}",
                    content: newYamlFileEncoded,
                    sha: ref.sha
                }
                
                github.put kubernetesGithubYamlFile, deploy, (ref) ->
                    res.send "OK"
            
                robot.messageRoom room, "#{deploy.message}"
                res.send "#{deploy.message}"
        res.send "OK"

