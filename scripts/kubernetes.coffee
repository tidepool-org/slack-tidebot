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
            match = comments.match(/^.*?\/\b(deploy|query)\s+([-_\.a-zA-z0-9]+)\s*?/)
            # function that takes users pr comment and extracts the Repo and Environment
            prCommentEnvExtractor = () ->
                if match == null
                    console.log "This command to deploy to #{match[1]} is not valid or the environment #{match[1]} does not exist."
                {
                    Env: inputToEnvironmentMap[match[2]],
                    Repo: inputToRepoMap[match[2]],
                    Service: serviceRepoToService[serviceRepo]
                }
                
            serviceBranch = branch.head.ref
            config = prCommentEnvExtractor()
            packageK8GithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/pkgs/#{config.Service}/#{config.Service}-helmrelease.yaml"
            tidepoolGithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/environments/#{config.Env}/tidepool/tidepool-helmrelease.yaml"
            environmentValuesYamlFile = "repos/tidepool-org/#{config.Repo}/contents/values.yaml"
            tidebotPostPrComment = "repos/tidepool-org/#{config.Repo}/issues/#{issueNumber}/comments"
            
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
                        yamlFileParsed.environments[config.Env].tidepool.gitops[platform] = dockerImageFilter
                newYamlFileUpdated = YAML.stringify(yamlFileParsed)
                Base64.encode(newYamlFileUpdated)

            yamlFileDecodeForQuery = (ref) ->
                yamlFileDecoded = Base64.decode(ref.content)
                yamlFileParsed = YAML.parse(yamlFileDecoded)
                theList = repoToServices serviceRepo
                for platform in theList
                    repoDestination = "fluxcd.io/tag." + platform
                    if config.service
                        {body: platform + ": " + yamlFileParsed.pkgs[config.Service].gitops[platform]}
                    else
                        {body: platform + ": " + yamlFileParsed.metadata.annotations[repoDestination]}

            deployYamlFile = (ref, newYamlFileEncoded, sender, serviceRepo, serviceBranch, config, changeAnnotations) ->
                {
                    message: if changeAnnotations then "#{sender} updated helmrelease.yaml file in #{config.Env}" else "#{sender} updated values.yaml file in #{config.Env}",
                    content: newYamlFileEncoded,
                    sha: ref.sha
                }
            
            tidebotCommentBodyInitializer = (sender, serviceRepo, serviceBranch, config) ->
                {
                    packagek8: if config.Service then { body: "#{sender} updated #{config.Service}-helmrelease.yaml file in #{config.Env}" } else {body: "OK"},                   
                    success: { body: "#{sender} deployed #{serviceRepo} #{serviceBranch} branch to #{config.Env} environment" },
                    values: { body: "#{sender} updated values.yaml file in #{config.Env}" },
                    tidepoolGithub: { body: "#{sender} updated tidepool-helmrelease.yaml file in #{config.Env}" }
                }
            tidebotCommentBody = tidebotCommentBodyInitializer sender, serviceRepo, serviceBranch, config
            tidebotCommentBodyString = JSON.stringify(tidebotCommentBody)
            console.log "FULL ORIGINAL TIDEBOT COMMENT BODY: #{tidebotCommentBodyString}"
            
            github.handleErrors (response) ->
                errorMessage = { body: "Error: #{response.statusCode} #{response.error}!" }
                github.post tidebotPostPrComment, errorMessage, (req) ->
                    console.log "TIDEBOT COMMENT POST ERROR MESSAGE: #{req.body}"
            
            if match[1] == "deploy"
                github.get environmentValuesYamlFile, (ref) ->
                    console.log "Deploy values yaml retrieved for updating"
                    yamlFileEncodeForValues = yamlFileEncode ref, false
                    deployValues = deployYamlFile ref, yamlFileEncodeForValues, sender, serviceRepo, serviceBranch, config, false
                    github.put environmentValuesYamlFile, deployValues, (ref) ->
                        console.log "THIS WILL SHOW IF VALUES FILE SUCCESSFULLY UPDATES: #{deployValues.message}"
                        robot.messageRoom room, "#{deployValues.message}"
                        console.log "COMMENT BODY AFTER SUCCESFULL VALUES FILE UPDATE #{tidebotCommentBody.values.body}"
                        console.log "COMMENT PATH: #{tidebotPostPrComment}"
                    github.post tidebotPostPrComment, tidebotCommentBody.values, (req) ->
                        console.log "THIS WILL SHOW IF TIDEBOT COMMENT POST FOR VALUES FILE IS SUCCESSFUL: #{req.body}"
                
                if config.Service
                    github.get packageK8GithubYamlFile, (ref) -> 
                        console.log "Deploy package service yaml retrieved for updating"
                        yamlFileEncodeForKubeConfig = yamlFileEncode ref, true
                        deployPackage = deployYamlFile ref, yamlFileEncodeForKubeConfig, sender, serviceRepo, serviceBranch, config, true
                        github.put packageK8GithubYamlFile, deployPackage, (ref) ->
                            console.log "THIS WILL SHOW IF PACKAGE YAML FILE SUCCESSFULLY UPDATES: #{deployPackage.message}"
                            robot.messageRoom room, "#{deployPackage.message}"
                            console.log "COMMENT BODY AFTER SUCCESFULL PACKAGE FILE UPDATE: #{tidebotCommentBody.packagek8.body}"
                            console.log "COMMENT PATH: #{tidebotPostPrComment}"                       
                        github.post tidebotPostPrComment, tidebotCommentBody.packagek8, (req) ->
                            console.log "THIS WILL SHOW IF TIDEBOT COMMENT POST FOR PACKAGE YAML FILE IS SUCCESSFUL: #{req.body}"
                
                else
                    github.get tidepoolGithubYamlFile, (ref) -> 
                        console.log "Deploy tidepool service yaml retrieved for updating"
                        yamlFileEncodeForKubeConfig = yamlFileEncode ref, true
                        deployTidepool = deployYamlFile ref, yamlFileEncodeForKubeConfig, sender, serviceRepo, serviceBranch, config, true
                        github.put tidepoolGithubYamlFile, deployTidepool, (ref) ->
                            console.log "THIS WILL SHOW IF TIDEPOOL SERVICE HELMRELEASE FILE SUCCESSFULLY UPDATES: #{deployTidepool.message}"
                            robot.messageRoom room, "#{deployTidepool.message}"
                            console.log "COMMENT BODY AFTER SUCCESFULL TIDEPOOL SERVICE HELRELEASE FILE UPDATE: #{tidebotCommentBody.tidepoolGithub.body}"
                            console.log "COMMENT PATH: #{tidebotPostPrComment}"
                        github.post tidebotPostPrComment, tidebotCommentBody.tidepoolGithub, (req) ->
                            console.log "THIS WILL SHOW IF TIDEBOT COMMENT POST FOR TIDEPOOL SERVICE HELMRELEASE FILE IS SUCCESSFUL: #{req.body}"
                
                github.post tidebotPostPrComment, tidebotCommentBody.success, (req) ->
                    console.log tidebotCommentBody.success
                    console.log "#{req.body}: This is the tidebot comment post body for success"
            
            else if match[1] == "query"
                if config.Service
                    github.get packageK8GithubYamlFile, (ref) -> 
                        currentDeployedBranch = yamlFileDecodeForQuery ref
                        github.post tidebotPostPrComment, currentDeployedBranch, (req) ->
                            console.log "THIS WILL SHOW IF TIDEBOT COMMENT POST FOR QUERIED BRANCH DEPLOYED: #{req.body}"
                else
                    github.get tidepoolGithubYamlFile, (ref) -> 
                        currentDeployedBranch = yamlFileDecodeForQuery ref
                        github.post tidebotPostPrComment, currentDeployedBranch, (req) ->
                            console.log "THIS WILL SHOW IF TIDEBOT COMMENT POST FOR QUERIED BRANCH DEPLOYED: #{req.body}"

        announceRepoEvent adapter, datas, eventType, (what) ->
            robot.messageRoom room, what
            res.send "OK"

