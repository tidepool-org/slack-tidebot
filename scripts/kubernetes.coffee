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
# test
YAML = require('yaml')
HubotSlack = require('hubot-slack')
eventActions = require('./all')
eventTypesRaw = process.env['HUBOT_GITHUB_EVENT_NOTIFIER_TYPES']
Base64 = require('js-base64').Base64;
eventTypes = []
inputToRepoMap = {
    "shared": "cluster-shared",
    "qa1": "cluster-qa1",
    "dev": "cluster-qa1",
    "qa2": "cluster-qa2",
    "int": "cluster-integration",
    "integration": "cluster-integration",
    "prd": "cluster-production",
    "prod": "cluster-production",
    "production": "cluster-production",
    "test": "integration-test",
    "stg": "cluster-staging",
    "staging": "cluster-staging"
}
inputToEnvironmentMap = {
    "qa1": "qa1",
    "dev": "qa1",
    "qa2": "qa2",
    "int": "external",
    "integration": "external",
    "prd": "production",
    "prod": "production",
    "production": "production",
    "test": "integration-test",
    "stg": "staging",
    "staging": "staging"
}
serviceRepoToService = {
    "slack-tidebot": "tidebot"
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
        if datas.comment == undefined
            announceRepoEvent adapter, datas, eventType, (what) ->
                robot.messageRoom room, what
            res.send ("OK")
            return
        
        authorized = datas.comment.author_association
        if !(authorized == "COLLABORATOR" || authorized == "MEMBER" || authorized == "OWNER")
            console.log "user is not authorized to for this command"
            return
        comments = datas.comment.body
        getComment = datas.comment.url
        issueNumber = datas.issue.number
        sender = datas.sender.login
        serviceRepo = datas.repository.name
        branches = datas.issue.pull_request.url
        console.log "Get Service Repo Information"
        github.get branches, (branch) ->
            console.log "Get Service Branch Information"
            # function that takes users pr comment and extracts the Repo and Environment
            prCommentEnvExtractor = (comments) ->
                match = comments.match(/^.*?\/\bdeploy\s+([-_\.a-zA-z0-9]+)\s*?/)
                if match == null
                    console.log "This command to deploy to #{match[1]} is not valid or the environment #{match[1]} does not exist."
                {
                    Env: inputToEnvironmentMap[match[1]],
                    Repo: inputToRepoMap[match[1]],
                    Service: serviceRepoToService[serviceRepo]
                }
            serviceBranch = branch.head.ref
            config = prCommentEnvExtractor(comments)
            packageK8GithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/pkgs/#{config.Service}/#{config.Service}-helmrelease.yaml"
            tidepoolGithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/environments/#{config.Env}/tidepool/tidepool-helmrelease.yaml"
            environmentValuesYamlFile = "repos/tidepool-org/#{config.Repo}/contents/values.yaml"
            tidebotPostPrComment = "repos/tidepool-org/#{config.Repo}/issues/#{issueNumber}/comments"
            console.log "#{tidebotPostPrComment}: This is the comment post endpoint /repos/:owner/:repo/issues/:issue_number/comments #{issueNumber} PR issue number should match"
            
            repoToServices = (serviceRepo) ->
                if serviceRepo == "platform"
                    console.log "Service repo is platform. adding platform services to kubernetes"
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
                        console.log "Change Annotations is true so parsed yaml file == tidepoolGithubYamlFile"
                        yamlFileParsed.metadata.annotations[repoDestination] = dockerImageFilter
                    else if config.Service
                        console.log "Change Annotations is false and service is an external service so parsed yaml file == external environmentValuesYamlFile"
                        yamlFileParsed.pkgs[config.Service].gitops = dockerImageFilter
                    else
                        console.log "Change Annotations is false and service is a tidepool service so parsed yaml file == environmentValuesYamlFile"
                        configString = JSON.stringify(config.Env)
                        console.log "#{configString} THIS SHOULD BE INTEGRATION-TEST"
                        console.log "Parsed YAML file #{yamlFileParsed}"
                        yamlFileParsed.environments[config.Env].tidepool.gitops[platform] = dockerImageFilter
                newYamlFileUpdated = YAML.stringify(yamlFileParsed)
                Base64.encode(newYamlFileUpdated)
                
            deployYamlFile = (ref, newYamlFileEncoded, sender, serviceRepo, serviceBranch, config) ->
                {
                    message: "#{sender} deployed #{serviceRepo} #{serviceBranch} branch to #{config.Env} environment",
                    content: newYamlFileEncoded,
                    sha: ref.sha
                }
            tidebotCommentBodyInitializer = (sender, serviceRepo, serviceBranch, config) ->
                if config.Service
                    {
                        packagek8: { body: "#{sender} updated #{config.Service}-helmrelease.yaml file in #{config.Env}" }
                    }
                {
                    success: { body: "#{sender} deployed #{serviceRepo} #{serviceBranch} branch to #{config.Env} environment" },
                    values: { body: "#{sender} updated values.yaml file in #{config.Env}" },
                    tidepoolGithub: { body: "#{sender} updated tidepool-helmrelease.yaml file in #{config.Env}" }
                }
            tidebotCommentBody = tidebotCommentBodyInitializer sender, serviceRepo, serviceBranch, config
            tidebotCommentBodyString = JSON.stringify(tidebotCommentBody)
            console.log "#{tidebotCommentBodyString}: Full Original tidebout comment body"
            github.handleErrors (response) ->
                errorMessage = { body: "Error: #{response.statusCode} #{response.error}!" }
                github.post tidebotPostPrComment, errorMessage, (errorMessage) ->
                    console.log "#{errorMessage}: This is the tidebot comment post body for errors"
            
            github.get environmentValuesYamlFile, (ref) ->
                console.log "Deploy values yaml retrieved for updating"
                yamlFileEncodeForValues = yamlFileEncode ref, false
                deployValues = deployYamlFile ref, yamlFileEncodeForValues, sender, serviceRepo, serviceBranch, config
                console.log deployValues
                github.put environmentValuesYamlFile, deployValues, (ref) ->
                    console.log "#{deployValues.message}"
                    robot.messageRoom room, "#{deployValues.message}"
                    github.post tidebotPostPrComment, tidebotCommentBody.values, (req) ->
                        console.log tidebotCommentBody.values
                        console.log "#{req.body}: This is the tidebot comment post body for values service yaml"
            
            if config.Service
                github.get packageK8GithubYamlFile, (ref) -> 
                    console.log "Deploy package service yaml retrieved for updating"
                    yamlFileEncodeForKubeConfig = yamlFileEncode ref, true
                    deployPackage = deployYamlFile ref, yamlFileEncodeForKubeConfig, sender, serviceRepo, serviceBranch, config
                    console.log deployPackage
                    github.put packageK8GithubYamlFile, deployPackage, (ref) ->
                        console.log "#{deployPackage.message}"
                        robot.messageRoom room, "#{deployPackage.message}"
                        github.post tidebotPostPrComment, tidebotCommentBody.packagek8, (req, res) ->
                            console.log tidebotCommentBody.packagek8
                            console.log "#{req.body}: This is the tidebot comment post body for package service yaml"
            
            else
                github.get tidepoolGithubYamlFile, (ref) -> 
                    console.log "Deploy tidepool service yaml retrieved for updating"
                    yamlFileEncodeForKubeConfig = yamlFileEncode ref, true
                    deployTidepool = deployYamlFile ref, yamlFileEncodeForKubeConfig, sender, serviceRepo, serviceBranch, config
                    console.log deployTidepool
                    github.put tidepoolGithubYamlFile, deployTidepool, (ref) ->
                        console.log "#{deployTidepool.message}"
                        robot.messageRoom room, "#{deployTidepool.message}"
                        github.post tidebotPostPrComment, tidebotCommentBody.tidepoolGithub, (req) ->
                            console.log tidebotCommentBody.tidepoolGithub
                            console.log "#{req.body}: This is the tidebot comment post body for tidepool service yaml"
            
            github.post tidebotPostPrComment, tidebotCommentBody.success, (req) ->
                console.log tidebotCommentBody.success
                console.log "#{req.body}: This is the tidebot comment post body for success"
            announceRepoEvent adapter, datas, eventType, (what) ->
                robot.messageRoom room, what
            res.send "OK"

