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
{ Octokit } = require("octokit");
{ Webhooks } = require("@octokit/webhooks");
eventActions = require('./all')
eventTypesRaw = process.env['HUBOT_GITHUB_EVENT_NOTIFIER_TYPES']
Base64 = require('js-base64').Base64;
eventTypes = []
inputToRepoMap = JSON.parse(process.env.inputToRepoMap)
inputToNamespaceMap = JSON.parse(process.env.inputToNamespaceMap)
serviceRepoToPackage = JSON.parse(process.env.serviceRepoToPackage)
organization = "tidepool-org"

announceRepoEvent = (adapter, datas, eventType, cb) ->
  if eventActions[eventType]?
    eventActions[eventType](adapter, datas, cb)
  else
    cb("Received a new #{eventType} event, just so you know.")

module.exports = (robot) ->
    if process.env.inputToRepoMap == undefined
        console.log "Input to Repo config not found"
        return
    if process.env.inputToNamespaceMap == undefined
        console.log "Input to Environment config not found"
        return
    if process.env.serviceRepoToPackage == undefined
        console.log "Service Repo to Service config not found"
        return

    github = require('githubot')(robot)
    webhooks = new Webhooks({
      secret: process.env["HUBOT_GITHUB_WEBHOOK_SECRET"]
    })

    robot.router.post '/hubot/gh-repo-events', (req, res) ->
        webhooks.verify(req.body, req.headers["x-hub-signature-256"]).then () ->
            eventType = req.headers["x-github-event"]
            adapter = robot.adapterName
            room = "github-events" || process.env["HUBOT_GITHUB_EVENT_NOTIFIER_ROOM"] || process.env["HUBOT_SLACK_ROOMS"]
            datas = req.body

            if datas.comment == undefined
                announceRepoEvent adapter, datas, eventType, (what) ->
                    robot.messageRoom room, what
                    res.send ("OK")
                return
            comments = datas.comment.body
            getComment = datas.comment.url
            commentTimeCreated = datas.comment.updated_at
            authorAssociation = datas.comment.author_association
            sender = datas.sender.login

            octokit = new Octokit({ auth: process.env['HUBOT_GITHUB_TOKEN'] });
            prom = octokit.request('GET /orgs/{org}/memberships/{username}', {
              org: organization,
              username: sender
            })

            prom.then (result) ->
                if result.status != 200
                    console.log "user is not authorized for this command"
                    return

                if datas.issue == undefined
                    return
                issueNumber = datas.issue.number
                commentNumber = datas.issue.comments
                branches = datas.issue.pull_request.url


                serviceRepo = datas.repository.name
                console.log "At #{commentTimeCreated}, #{authorAssociation} #{sender} posted comment ##{commentNumber} '#{comments}' to PR in #{serviceRepo} issue ##{issueNumber}"
                console.log "Comment URL #{getComment}"
                match = comments.match(/^.*?\/\b(deploy|query|default)\s+([-_\.a-zA-z0-9]+)\s*([-_\.a-zA-z0-9]+)?\s*?/)

                github.get branches, (branch) ->
                    console.log "User comment and Service Branch info retrieved ready to execute command"
                    if match == null
                        console.log "/ command complete and no longer active"
                        return

                    # function that takes users pr comment and extracts the Repo and Environment
                    prCommentEnvExtractor = () ->
                        {
                            Namespace: inputToNamespaceMap[match[2]],
                            Repo: inputToRepoMap[match[2]],
                            Service: serviceRepoToPackage[serviceRepo]
                        }

                    serviceBranch = branch.head.ref
                    config = prCommentEnvExtractor()
                    if config.Repo == undefined
                        console.log "Tidebot does not have a Repo config for #{match[2]} here is the config \n #{JSON.stringify(inputToRepoMap)}"
                        return
                    if config.Namespace == undefined
                        console.log "Tidebot does not have a Namespace config for #{match[2]} here is the config \n #{JSON.stringify(inputToNamespaceMap)}"
                        return
                    if config.Service == undefined
                        console.log "Tidebot does not have a Package config for #{serviceRepo} here is the config \n #{JSON.stringify(serviceRepoToPackage)}"
                        return

                    tidepoolGithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/generated/#{config.Namespace}/#{config.Service}/fluxpolicies.yaml"
                    if config.Service != "tidepool"
                        tidepoolGithubYamlFile = "repos/tidepool-org/#{config.Repo}/contents/generated/#{config.Namespace}/#{config.Service}/fluxpolicy.yaml"
                    console.log "Path to helmrelease yaml #{tidepoolGithubYamlFile}"
                    environmentValuesYamlFile = "repos/tidepool-org/#{config.Repo}/contents/values.yaml"
                    tidebotPostPrComment = "repos/tidepool-org/#{serviceRepo}/issues/#{issueNumber}/comments"

                    repoToServices = () ->
                        platformServices = ["data", "blob", "auth", "image", "migrations", "notification", "task", "tools", "user", "prescription"]
                        if serviceRepo == "platform" && !match[3]?
                            console.log "Service repo is platform. Adding all platform services to kubernetes"
                            platformServices
                        else if serviceRepo == "platform" && match[3]?
                            for service in platformServices
                                if match[3] == service
                                    console.log "Service repo is platform. Adding #{service} platform service to kubernetes"
                                    [service]
                        else
                            [serviceRepo]

                    yamlFileEncode = (ref, changeImagePolicies) ->
                        # Docker images are based on branch name. But "/" are replaced with "-"
                        # For example, the branch "pazaan/fix-errors" becomes a docker image called "pazaan-fix-errors"
                        branch = serviceBranch.replace(/\//g, "-")

                        yamlFileDecoded = Base64.decode(ref.content)
                        documents = YAML.parseAllDocuments(yamlFileDecoded)

                        parsed = []
                        for document in documents
                            parsed.push document.toJSON()

                        # Update flux image policy manifests
                        if changeImagePolicies
                            console.log "Updating image policies"

                            # Convert to a map {serviceName: automationManifest}
                            imagePolicies = {}
                            for i in [0...parsed.length]
                                imagePolicies[parsed[i].metadata.name] = parsed[i]

                            services = repoToServices()
                            for service in services
                                if service of imagePolicies
                                    pattern = '^' + branch + '-[0-9A-Fa-f]{40}-(?P<ts>[0-9]+)$'
                                    if match[1] == "default"
                                        pattern = imagePolicies[service].metadata.annotations['automation.tidepool.org/default-pattern']

                                    imagePolicies[service].spec.filterTags.pattern = pattern

                            documents = []
                            documents = (val for service, policy of imagePolicies)

                        else
                            # Update cluster values.yaml
                            document = documents[0].toJSON()

                            console.log "Updating cluster values.yaml"
                            services = repoToServices()
                            for service in services
                                if match[1] == "default"
                                   delete document.namespaces[config.Namespace][config.Service].gitops[service]
                                else
                                   document.namespaces[config.Namespace][config.Service].gitops[service] = branch

                            # Do not change the output to yaml sequence
                            documents = document

                        updated = YAML.stringify(documents)
                        Base64.encode(updated)

                    yamlFileDecodeForQuery = (ref) ->
                        yamlFileDecoded = Base64.decode(ref.content)
                        yamlFileParsed = YAML.parse(yamlFileDecoded)
                        theList = repoToServices()
                        for platform in theList
                            if config.Service != "tidepool"
                                serviceImage = yamlFileParsed.spec.template.spec.containers[0].image
                                if serviceImage?
                                    {body: "image: " + serviceImage}
                            else if yamlFileParsed.spec.values[platform]?
                                serviceImage = yamlFileParsed.spec.values[platform].deployment.image
                                {body: "image: " + serviceImage}
                            else if !platform? && match[3]?
                                null
                            else
                                { body: "ERROR: Can not find deployed #{platform} or #{platform} has not been deployed to #{config.Namespace}" }

                    deployYamlFile = (ref, newYamlFileEncoded, changeAnnotations) ->
                        {
                            message: if changeAnnotations then "#{sender} updated helmrelease.yaml file in #{config.Namespace}" else "#{sender} updated values.yaml file in #{config.Namespace}",
                            content: newYamlFileEncoded,
                            sha: ref.sha
                        }

                    tidebotCommentBodyInitializer = () ->
                        if match[1] == "default"
                            branch = "Master"
                        else
                            branch = serviceBranch
                        {
                            package: if config.Service then { body: "#{sender} updated helmrelease.yaml file in #{config.Namespace}" } else {body: "OK"},
                            success: { body: "#{sender} deployed #{serviceRepo} #{branch} branch to #{config.Namespace} namespace" },
                            values: { body: "#{sender} updated values.yaml file in #{config.Namespace}" },
                            tidepool: { body: "#{sender} updated helmrelease.yaml file in #{config.Namespace}" }
                        }

                    tidebotPostPrFunction = (ref) ->
                        currentDeployedBranch = yamlFileDecodeForQuery ref
                        for service in currentDeployedBranch
                            if service? && service != undefined
                                github.post tidebotPostPrComment, service, (req) ->
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

                        github.get tidepoolGithubYamlFile, (ref) ->
                                deployServiceAndStatusComment ref, true, tidebotCommentBody, "tidepool", tidepoolGithubYamlFile
                        return

                    else if match[1] == "query"
                        github.get tidepoolGithubYamlFile, (ref) ->
                                tidebotPostPrFunction ref
                        return
                announceRepoEvent adapter, datas, eventType, (what) ->
                    robot.messageRoom room, what
            .catch (error) ->
                console.log "membership check failed #{error}"
        .catch (error) ->
            console.log "webhook signature verification failed #{error}"
