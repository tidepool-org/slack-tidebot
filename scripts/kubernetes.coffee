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
    "tidebot": "cluster-shared"
    "qa1": "cluster-qa1",
    "qa2": "cluster-qa2",
    "int": "cluster-integration",
    "integration": "cluster-integration",
    "prd": "cluster-production",
    "production": "cluster-production",
    "test": "integration-test",
    "stg": "cluster-staging"
    "staging": "cluster-staging"
}

announceRepoEvent = (adapter, datas, eventType, cb) ->
  if eventActions[eventType]?
    eventActions[eventType](adapter, datas, cb)
  else
    cb("Received a new #{eventType} event, just so you know.")

module.exports = (robot) ->
    github = require('githubot')(robot)
    
    robot.router.post '/hubot/gh-repo-events', (req, res) ->
        eventType = req.headers["x-github-event"]
        adapter = robot.adapterName
        room = "github-events" || process.env["HUBOT_GITHUB_EVENT_NOTIFIER_ROOM"] || process.env["HUBOT_SLACK_ROOMS"]
        datas = req.body
        authorized = datas.comment.author_association
        if !(authorized == "COLLABORATOR" || authorized == "MEMBER" || authorized == "OWNER")
            console.log "user is not authorized to for this command"
            return
        if datas.comment == undefined
            announceRepoEvent adapter, datas, eventType, (what) ->
                robot.messageRoom room, what
            res.send ("OK")
        else
            comments = datas.comment.body
            sender = datas.sender.login
            serviceRepo = datas.repository.name
            branches = datas.issue.pull_request.url
            github.get branches, (branch) ->
                # function that takes users pr comment and extracts the Repo and Environment
                prCommentEnvExtractor = (comments) ->
                    match = comments.match(/^.*?\/\bdeploy\s+([-_\.a-zA-z0-9]+)\s*?/)
                    if match == null
                        console.log "This command to deploy to #{match[1]} is not valid or the environment #{match[1]} does not exist."
                    {
                        Env: match[1]
                        Repo: environmentToRepoMap[match[1]],
                    }
                serviceBranch = branch.head.ref
                config = prCommentEnvExtractor(comments)
                tidebotK8GithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/pkgs/#{config.Env}/tidebot-helmrelease.yaml"
                kubernetesGithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/environments/#{config.Env}/tidepool/tidepool-helmrelease.yaml"
                environmentValuesYamlFile = "repos/tidepool-org/#{config.Repo}/contents/values.yaml"
                
                repoToServices = (serviceRepo) ->
                    if serviceRepo == "platform"
                        ["data", "blob", "auth", "image", "migrations", "notification", "task", "tools", "user"]
                    else
                        [serviceRepo]
                
                yamlFileEncode = (ref, changeAnnotations) ->
                    yamlFileDecoded = Base64.decode(ref.content)
                    yamlFileParsed = YAML.parse(yamlFileDecoded)
                    dockerImageFilter = "glob:" + serviceBranch + "-*"
                    theList = repoToServices serviceRepo
                    for platform in theList
                        repoDestination = "fluxcd.io/tag." + platform
                        if changeAnnotations
                            yamlFileParsed.metadata.annotations[repoDestination] = dockerImageFilter
                        else if serviceRepo == "slack-tidebot"
                            pkgs.tidebot.gitops[platform] = dockerImageFilter
                        else
                            yamlFileParsed.environments[config.Env].tidepool.gitops[platform] = dockerImageFilter
                    newYamlFileUpdated = YAML.stringify(yamlFileParsed)
                    Base64.encode(newYamlFileUpdated)
                    
                deployYamlFile = (ref, newYamlFileEncoded, sender, serviceRepo, serviceBranch, config) ->
                    {
                        message: "#{sender} deployed #{serviceRepo} #{serviceBranch} branch to #{config.Env} environment",
                        content: newYamlFileEncoded,
                        sha: ref.sha
                    }
                github.handleErrors (response) ->
                    console.log "Oh no! #{JSON.stringify(response)}!"
                
                github.get environmentValuesYamlFile, (ref) ->
                    yamlFileEncodeForValues = yamlFileEncode(ref, false)
                    deploy = deployYamlFile ref, yamlFileEncodeForValues, sender, serviceRepo, serviceBranch, config
                    github.put environmentValuesYamlFile, deploy, (ref) ->
                        console.log "#{deploy.message}"
                        robot.messageRoom room, "#{deploy.message}"
                
                if serviceRepo == "slack-tidebot"
                    github.get tidebotK8GithubYamlFile, (ref) -> 
                        yamlFileEncodeForKubeConfig = yamlFileEncode(ref, true)
                        deploy = deployYamlFile ref, yamlFileEncodeForKubeConfig, sender, serviceRepo, serviceBranch, config
                        github.put tidebotK8GithubYamlFile, deploy, (ref) ->
                            console.log "#{deploy.message}"
                            robot.messageRoom room, "#{deploy.message}"
                
                else
                    github.get kubernetesGithubYamlFile, (ref) -> 
                        yamlFileEncodeForKubeConfig = yamlFileEncode(ref, true)
                        deploy = deployYamlFile ref, yamlFileEncodeForKubeConfig, sender, serviceRepo, serviceBranch, config
                        github.put kubernetesGithubYamlFile, deploy, (ref) ->
                            console.log "#{deploy.message}"
                            robot.messageRoom room, "#{deploy.message}"
            
            announceRepoEvent adapter, datas, eventType, (what) ->
                robot.messageRoom room, what
            res.send "OK"

