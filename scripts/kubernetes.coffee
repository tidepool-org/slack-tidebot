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
            tidebotPostPrComment = "repos/tidepool-org/#{serviceRepo}/issues/#{issueNumber}/comments"
            
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
                    console.log "SERVICE REPO: #{platform}"
                    if config.Service
                        {body: "image: " + yamlFileParsed.spec.values.deployment.image}
                    else
                        {body: "image: " + yamlFileParsed.spec.values[platform].deployment.image}

            deployYamlFile = (ref, newYamlFileEncoded, sender, serviceRepo, serviceBranch, config, changeAnnotations) ->
                {
                    message: if changeAnnotations then "#{sender} updated helmrelease.yaml file in #{config.Env}" else "#{sender} updated values.yaml file in #{config.Env}",
                    content: newYamlFileEncoded,
                    sha: ref.sha
                }
            
            tidebotCommentBodyInitializer = (sender, serviceRepo, serviceBranch, config) ->
                {
                    package: if config.Service then { body: "#{sender} updated #{config.Service}-helmrelease.yaml file in #{config.Env}" } else {body: "OK"},                   
                    success: { body: "#{sender} deployed #{serviceRepo} #{serviceBranch} branch to #{config.Env} environment" },
                    values: { body: "#{sender} updated values.yaml file in #{config.Env}" },
                    tidepool: { body: "#{sender} updated tidepool-helmrelease.yaml file in #{config.Env}" }
                }

            tidebotPostPrFunction = (ref) ->
                currentDeployedBranch = yamlFileDecodeForQuery ref
                if currentDeployedBranch == undefined
                    error = { body: "ERROR: Can not find deployed #{serviceRepo} or #{serviceRepo} has not been deployed to #{config.Env}" }
                    github.post tidebotPostPrComment, error, (req) ->
                        console.log req.body
                else
                    console.log currentDeployedBranch[0]
                    console.log "COMMENT POST ENDPOINT #{tidebotPostPrComment}"
                    github.post tidebotPostPrComment, currentDeployedBranch[0], (req) ->
                        console.log "THIS WILL SHOW IF TIDEBOT COMMENT POST FOR QUERIED BRANCH DEPLOYED: #{req.body}"

            deployServiceAndStatusComment = (ref, changeAnnotations, serviceType, yamlFileType, deployType) ->
                console.log "Deploy #{serviceType} service yaml retrieved for updating"
                yamlFileEncodeForKubeConfig = yamlFileEncode ref, changeAnnotations
                deployTidepool = deployYamlFile ref, yamlFileEncodeForKubeConfig, sender, serviceRepo, serviceBranch, config, changeAnnotations
                github.put yamlFileType, deployType, (req) ->
                    console.log "THIS WILL SHOW IF #{serviceType} SERVICE HELMRELEASE FILE SUCCESSFULLY UPDATES: #{deployType.message}"
                    robot.messageRoom room, "#{deployType.message}"
                    console.log "COMMENT BODY AFTER SUCCESFULL #{serviceType} SERVICE HELRELEASE FILE UPDATE: #{tidebotCommentBody[serviceType].body}"
                    console.log "COMMENT PATH: #{tidebotPostPrComment}"
                github.post tidebotPostPrComment, tidebotCommentBody[serviceType], (req) ->
                    console.log "THIS WILL SHOW IF TIDEBOT COMMENT POST FOR #{serviceType} SERVICE HELMRELEASE FILE IS SUCCESSFUL: #{req.body}"
            
            github.handleErrors (response) ->
                errorMessage = { body: "Error: #{response.statusCode} #{response.error}!" }
                github.post tidebotPostPrComment, errorMessage, (req) ->
                    console.log "TIDEBOT COMMENT POST ERROR MESSAGE: #{req.body}"
            
            if match[1] == "deploy"
                tidebotCommentBody = tidebotCommentBodyInitializer sender, serviceRepo, serviceBranch, config
                tidebotCommentBodyString = JSON.stringify(tidebotCommentBody)
                console.log "FULL ORIGINAL TIDEBOT COMMENT BODY: #{tidebotCommentBodyString}"
                github.get environmentValuesYamlFile, (ref) ->
                    deployServiceAndStatusComment ref, false, tidebotCommentBody, "values", environmentValuesYamlFile, deployValues
                
                if config.Service
                    github.get packageK8GithubYamlFile, (ref) -> 
                        deployServiceAndStatusComment ref, true, tidebotCommentBody, "package", packageK8GithubYamlFile, deployPackage
                
                else
                    github.get tidepoolGithubYamlFile, (ref) -> 
                        deployServiceAndStatusComment ref, true, tidebotCommentBody, "tidepool", tidepoolGithubYamlFile, deployTidepool
                
                github.post tidebotPostPrComment, tidebotCommentBody.success, (req) ->
                    console.log tidebotCommentBody.success
                    console.log "#{req.body}: This is the tidebot comment post body for success"
            
            else if match[1] == "query"
                if config.Service
                    github.get packageK8GithubYamlFile, (ref) -> 
                        tidebotPostPrFunction ref
                else
                    github.get tidepoolGithubYamlFile, (ref) -> 
                        tidebotPostPrFunction ref

        announceRepoEvent adapter, datas, eventType, (what) ->
            robot.messageRoom room, what
            res.send "OK"

