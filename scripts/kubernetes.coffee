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
inputToRepoMap = JSON.parse(process.env.inputToRepoMap)
inputToEnvironmentMap = JSON.parse(process.env.inputToEnvironmentMap)
serviceRepoToService = JSON.parse(process.env.serviceRepoToService)
inputToRepoMapLocal = {
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
inputToEnvironmentMapLocal = {
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
serviceRepoToServiceLocal = {
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
        commentNumber = datas.issue.comments
        commentTimeCreated = datas.comment.updated_at
        commenterAutho = datas.comment.author_association
        sender = datas.sender.login
        serviceRepo = datas.repository.name
        branches = datas.issue.pull_request.url
        console.log "At #{commentTimeCreated}, #{commenterAutho} #{sender} posted comment ##{commentNumber} '#{comments}' to PR in #{serviceRepo} issue ##{issueNumber}"
        console.log "Comment URL #{getComment}"
        match = comments.match(/^.*?\/\b(deploy|query|default)\s+([-_\.a-zA-z0-9]+)\s*?/)
        github.get branches, (branch) ->
            console.log "User comment and Service Branch info retrieved ready to execute command"
            if match == null
                console.log "/ command complete and no longer active"
                return
            # function that takes users pr comment and extracts the Repo and Environment
            prCommentEnvExtractor = () ->
                if process.env.inputToRepoMap == undefined
                    console.log "ENV variables failed: Used Hard Coded ENV Variables For Config"
                    {
                        Env: inputToEnvironmentMapLocal[match[2]],
                        Repo: inputToRepoMapLocal[match[2]],
                        Service: serviceRepoToServiceLocal[serviceRepo]
                    }
                else
                    {
                        Env: inputToEnvironmentMap[match[2]],
                        Repo: inputToRepoMap[match[2]],
                        Service: serviceRepoToService[serviceRepo]
                    }
                
            serviceBranch = branch.head.ref
            config = prCommentEnvExtractor()
            tidepoolGithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/environments/#{config.Env}/tidepool/tidepool-helmrelease.yaml"
            environmentValuesYamlFile = "repos/tidepool-org/#{config.Repo}/contents/values.yaml"
            tidebotPostPrComment = "repos/tidepool-org/#{serviceRepo}/issues/#{issueNumber}/comments"
            
            repoToServices = () ->
                if serviceRepo == "platform"
                    console.log "Service repo is platform. adding platform services to kubernetes"
                    ["data", "blob", "auth", "image", "migrations", "notification", "task", "tools", "user"]
                else
                    [serviceRepo]
            
            yamlFileEncode = (ref, changeAnnotations) ->
                yamlFileDecoded = Base64.decode(ref.content)
                yamlFileParsed = YAML.parse(yamlFileDecoded)
                dockerImageFilter = "glob:" + serviceBranch + "-*"
                if match[1] == "default"
                    dockerImageFilter =  "glob:master-*"
                theList = repoToServices()
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
                theList = repoToServices()
                for platform in theList
                    if config.Service
                        {body: "image: " + yamlFileParsed.spec.values.deployment.image}
                    else if yamlFileParsed.spec.values[platform] == undefined
                        { body: "ERROR: Can not find deployed #{serviceRepo} or #{serviceRepo} has not been deployed to #{config.Env}" }
                    else
                        {body: "image: " + yamlFileParsed.spec.values[platform].deployment.image}
                    

            deployYamlFile = (ref, newYamlFileEncoded, changeAnnotations) ->
                if config.Service
                    config.Env = "cluster-#{match[2]}"
                {
                    message: if changeAnnotations then "#{sender} updated helmrelease.yaml file in #{config.Env}" else "#{sender} updated values.yaml file in #{config.Env}",
                    content: newYamlFileEncoded,
                    sha: ref.sha
                }
            
            tidebotCommentBodyInitializer = () ->
                if config.Service
                    config.Env = "cluster-#{match[2]}"
                {
                    package: if config.Service then { body: "#{sender} updated #{config.Service}-helmrelease.yaml file in #{config.Env}" } else {body: "OK"},                   
                    success: { body: "#{sender} deployed #{serviceRepo} #{serviceBranch} branch to #{config.Env} environment" },
                    values: { body: "#{sender} updated values.yaml file in #{config.Env}" },
                    tidepool: { body: "#{sender} updated tidepool-helmrelease.yaml file in #{config.Env}" }
                }

            tidebotPostPrFunction = (ref) ->
                currentDeployedBranch = yamlFileDecodeForQuery ref
                github.post tidebotPostPrComment, currentDeployedBranch[0], (req) ->
                    console.log "THIS WILL SHOW IF TIDEBOT COMMENT POST FOR QUERIED BRANCH DEPLOYED: #{req.body}"

            deployServiceAndStatusComment = (ref, changeAnnotations, tidebotCommentBody, serviceType, yamlFileType) ->
                console.log "Deploy #{serviceType} service yaml retrieved for updating"
                yamlFileEncodeForKubeConfig = yamlFileEncode ref, changeAnnotations
                deployService = deployYamlFile ref, yamlFileEncodeForKubeConfig, changeAnnotations
                github.put yamlFileType, deployService, (req) ->
                    console.log "THIS WILL SHOW IF #{serviceType} SERVICE HELMRELEASE FILE SUCCESSFULLY UPDATES: #{deployService.message}"
                    robot.messageRoom room, "#{deployService.message}"
                github.post tidebotPostPrComment, tidebotCommentBody[serviceType], (req) ->
                    console.log "THIS WILL SHOW IF TIDEBOT COMMENT POST FOR #{serviceType} SERVICE HELMRELEASE FILE IS SUCCESSFUL: #{req.body}"
                if serviceType == "tidepool" || serviceType == "package"
                    github.post tidebotPostPrComment, tidebotCommentBody.success, (req) ->
                        console.log "#{req.body}: This is the tidebot comment post body for success"

            github.handleErrors (response) ->
                errorMessage = { body: "Error: #{response.statusCode} #{response.error}!" }
                github.post tidebotPostPrComment, errorMessage, (req) ->
                    console.log "TIDEBOT COMMENT POST ERROR MESSAGE: #{req.body}"
           
            if match[1] == "deploy" || match[1] == "default"
                tidebotCommentBody = tidebotCommentBodyInitializer()
                github.get environmentValuesYamlFile, (ref) ->
                    deployServiceAndStatusComment ref, false, tidebotCommentBody, "values", environmentValuesYamlFile
                
                if config.Service
                    packageK8GithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/pkgs/#{config.Service}/#{config.Service}-helmrelease.yaml"
                    github.get packageK8GithubYamlFile, (ref) -> 
                        deployServiceAndStatusComment ref, true, tidebotCommentBody, "package", packageK8GithubYamlFile
                
                else
                    github.get tidepoolGithubYamlFile, (ref) -> 
                        deployServiceAndStatusComment ref, true, tidebotCommentBody, "tidepool", tidepoolGithubYamlFile
                return
            
            else if match[1] == "query"
                if config.Service
                    packageK8GithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/pkgs/#{config.Service}/#{config.Service}-helmrelease.yaml"
                    github.get packageK8GithubYamlFile, (ref) -> 
                        tidebotPostPrFunction ref
                else
                    github.get tidepoolGithubYamlFile, (ref) -> 
                        tidebotPostPrFunction ref
                return
        announceRepoEvent adapter, datas, eventType, (what) ->
            robot.messageRoom room, what
