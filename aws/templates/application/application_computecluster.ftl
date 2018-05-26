[#-- COMPUTECLUSTER --]
[#if componentType == COMPUTECLUSTER_COMPONENT_TYPE]

    [#list requiredOccurrences(
            getOccurrences(tier, component),
            deploymentUnit) as occurrence]

        [@cfDebug listMode occurrence false /]

        [#assign core = occurrence.Core ]
        [#assign solution = occurrence.Configuration.Solution ]
        [#assign resources = occurrence.State.Resources ]
        [#assign links = solution.Links ]

        [#assign dockerHost = solution.DockerHost]

        [#assign computeClusterRoleId = resources["role"].Id ]
        [#assign computeClusterInstanceProfileId = resources["instanceProfile"].Id ]
        [#assign computeClusterAutoScaleGroupId = resources["autoScaleGroup"].Id ]
        [#assign computeClusterLaunchConfigId = resources["launchConfig"].Id ]
        [#assign computeClusterSecurityGroupId = resources["securityGroup"].Id ]

        [#assign targetGroupPermission = false ]
        [#assign targetGroups = [] ]
        [#assign loadBalancers = [] ]
        [#assign environmentVariables = {}]

        [#assign configSetName = componentType]        
        [#assign configSets =  
                getInitConfigDirectories() + 
                getInitConfigBootstrap(component.Role!"") ]

        [#assign scriptsPath =
                formatRelativePath(
                getRegistryEndPoint("scripts", occurrence),
                getRegistryPrefix("scripts", occurrence),
                productName,
                getOccurrenceBuildUnit(occurrence),
                getOccurrenceBuildReference(occurrence)
                ) ]   

        [#assign scriptsFile = 
            formatRelativePath(
                scriptsPath,
                "scripts.zip"
            )
        ]

        [#assign containerId =
            solution.Container?has_content?then(
                solution.Container,
                getComponentId(component)
            ) ]

        [#assign environmentContext =
            {
                "Id" : containerId,
                "Name" : containerId,
                "Instance" : core.Instance.Id,
                "Version" : core.Version.Id,
                "DefaultEnvironment" : defaultEnvironment(occurrence),
                "Environment" : {},
                "Links" : getLinkTargets(occurrence),
                "DefaultCoreVariables" : true,
                "DefaultEnvironmentVariables" : true,
                "DefaultLinkVariables" : true
            }
        ]

        [#-- Add in container specifics including override of defaults --]
        [#assign containerListMode = "model"]
        [#assign containerId = formatContainerFragmentId(occurrence, environmentContext)]
        [#include containerList?ensure_starts_with("/")]

        [#assign environmentVariables += getFinalEnvironment(occurrence, environmentContext).Environment ]

        [#assign configSets += 
            getInitConfigScriptsDeployment(scriptsFile, environmentVariables, false) +
            getInitConfigEnvFacts(environmentVariables, false)]

        [#assign ingressRules = []]

        [#list solution.Ports?values as port ]
            [#if port.LB.Configured]
                [#assign links += getLBLink(occurrence, port)]
            [#else]
                [#assign portCIDRs = getGroupCIDRs(port.IPAddressGroups) ]
                [#if portCIDRs?has_content]
                    [#assign ingressRules +=
                        [{
                            "Port" : port.Name,
                            "CIDR" : portCIDRs
                        }]]
                [/#if]
            [/#if]
        [/#list]
            
        [#if deploymentSubsetRequired("iam", true) &&
                isPartOfCurrentDeploymentUnit(computeClusterRoleId)]
            [@createRole
                mode=listMode
                id=computeClusterRoleId
                trustedServices=["ec2.amazonaws.com" ]
                policies=
                    [
                        getPolicyDocument(
                            s3ReadPermission(scriptsPath) +
                            s3ListPermission(codeBucket) +
                            s3ReadPermission(codeBucket) +
                            s3ListPermission(operationsBucket) +
                            s3WritePermission(operationsBucket, "DOCKERLogs") +
                            s3WritePermission(operationsBucket, "Backups"),
                            "basic")
                    ] + targetGroupPermission?then(
                        [
                            getPolicyDocument(
                                lbRegisterTargetPermission(),
                                "loadbalancing")
                        ],
                        [])
            /]
        
        [/#if]
                
        [#list links?values as link]
            [#assign linkTarget = getLinkTarget(occurrence, link) ]

            [@cfDebug listMode linkTarget false /]

            [#if !linkTarget?has_content]
                [#continue]
            [/#if]

            [#assign linkTargetCore = linkTarget.Core ]
            [#assign linkTargetConfiguration = linkTarget.Configuration ]
            [#assign linkTargetResources = linkTarget.State.Resources ]
            [#assign linkTargetAttributes = linkTarget.State.Attributes ]

            [#switch linkTargetCore.Type]
                [#case LB_PORT_COMPONENT_TYPE]
                    [#assign targetGroupPermission = true]

                    [#switch linkTargetAttributes["ENGINE"]]

                        [#case "application"]
                        [#case "network"]
                            [#if link.TargetGroup?has_content ]
                                [#assign targetId = (linkTargetResources["targetgroups"][link.TargetGroup].Id) ]
                                [#if targetId?has_content]

                                    [#if deploymentSubsetRequired(COMPUTECLUSTER_COMPONENT_TYPE, true)]
                                        [#if isPartOfCurrentDeploymentUnit(targetId)]

                                            [@createTargetGroup
                                                mode=listMode
                                                id=targetId
                                                name=formatName(linkTargetCore.FullName,link.TargetGroup)
                                                tier=link.Tier
                                                component=link.Component
                                                destination=ports[link.Port]
                                            /]
                                            [#assign listenerRuleId = formatALBListenerRuleId(occurrence, link.TargetGroup) ]
                                            [@createListenerRule
                                                mode=listMode
                                                id=listenerRuleId
                                                listenerId=linkTargetResources["listener"].Id
                                                actions=getListenerRuleForwardAction(targetId)
                                                conditions=getListenerRulePathCondition(link.TargetPath)
                                                priority=link.Priority!100
                                                dependencies=targetId
                                            /]

                                            [#assign componentDependencies += [targetId]]

                                        [/#if]
                                        [#assign targetGroups += [ getReference(targetId, ARN_ATTRIBUTE_TYPE) ] ]
                                    [/#if]
                                [/#if]
                            [/#if]
                            [#break]

                        [#case "classic" ]
                            [#assign lbId =  linkTargetAttributes["LB"] ]                                     
                            [#-- Classic ELB's register the instance so we only need 1 registration --]
                            [#assign loadBalancers += [ getExistingReference(lbId) ]]
                            [#break]
                        [/#switch]
                    [#break]
                [#case EFS_MOUNT_COMPONENT_TYPE]
                    [#assign configSets += 
                        getInitConfigEFSMount(
                            linkTargetCore.Id, 
                            linkTargetAttributes.EFS, 
                            linkTargetAttributes.DIRECTORY, 
                            link.Id
                        )]
                    [#break]
            [/#switch]
        [/#list]

        [#if deploymentSubsetRequired(COMPUTECLUSTER_COMPONENT_TYPE, true)]

            [@createComponentSecurityGroup
                mode=listMode
                tier=tier
                component=component /]
    
            [#assign processorProfile = getProcessor(tier, component, "ComputeCluster")]
            
            [#assign maxSize = processorProfile.MaxPerZone]
            [#if multiAZ]
                [#assign maxSize = maxSize * zones?size]
            [/#if]
            [#if maxSize <= solution.MinUpdateInstances ]
                [#assign maxSize = maxSize + solution.MinUpdateInstances ]
            [/#if]

            [#assign storageProfile = getStorage(tier, component, "ComputeCluster")]

            [#assign desiredCapacity = multiAZ?then( 
                processorProfile.DesiredPerZone * zones?size,
                processorProfile.DesiredPerZone
            )]
        
            [@cfResource
                mode=listMode
                id=computeClusterInstanceProfileId
                type="AWS::IAM::InstanceProfile"
                properties=
                    {
                        "Path" : "/",
                        "Roles" : [getReference(computeClusterRoleId)]
                    }
                outputs={}
            /]

            [@cfResource
                mode=listMode
                id=computeClusterAutoScaleGroupId
                type="AWS::AutoScaling::AutoScalingGroup"
                metadata=getInitConfig(configSetName, configSets )
                properties=
                    {
                        "Cooldown" : "30",
                        "LaunchConfigurationName": getReference(computeClusterLaunchConfigId),
                        "TerminationPolicies" : [
                            "OldestLaunchConfiguration",
                            "OldestInstance",
                            "ClosestToNextInstanceHour"
                        ],
                        "MetricsCollection" : [ 
                            {
                                "Granularity" : "1Minute"
                            }
                        ]
                    } +
                    multiAZ?then(
                        {
                            "MinSize": processorProfile.MinPerZone * zones?size,
                            "MaxSize": maxSize,
                            "DesiredCapacity": desiredCapacity,
                            "VPCZoneIdentifier": getSubnets(tier)
                        },
                        {
                            "MinSize": processorProfile.MinPerZone,
                            "MaxSize": maxSize,
                            "DesiredCapacity": desiredCapacity,
                            "VPCZoneIdentifier" : getSubnets(tier)[0..0]
                        }
                    ) + 
                    attributeIfContent(
                        "LoadBalancerNames",
                        loadBalancers,
                        loadBalancers
                    ) +
                    attributeIfContent(
                        "TargetGroupARNs",
                        targetGroups,
                        targetGroups
                    )
                tags=
                    getCfTemplateCoreTags(
                        formatComponentFullName(tier, component),
                        tier,
                        component,
                        "",
                        true)
                outputs={}
                updatePolicy=solution.ReplaceOnUpdate?then(
                    {
                        "AutoScalingReplacingUpdate" : {
                            "WillReplace" : true
                        }
                    },
                    {
                        "AutoScalingRollingUpdate" : {
                            "WaitOnResourceSignals" : true,
                            "MinInstancesInService" : solution.MinUpdateInstances
                        }
                    }
                )   
                creationPolicy={
                    "ResourceSignal" : {
                        "Count" : desiredCapacity,
                        "Timeout" : "PT15M"
                    }
                }
            /]
                    
            [#assign imageId = dockerHost?then(
                regionObject.AMIs.Centos.ECS,
                regionObject.AMIs.Centos.EC2
            )]

            [@createEC2LaunchConfig 
                mode=listMode 
                id=computeClusterLaunchConfigId
                processorProfile=processorProfile
                storageProfile=storageProfile
                securityGroupId=computeClusterSecurityGroupId
                instanceProfileId=computeClusterInstanceProfileId
                resourceId=computeClusterAutoScaleGroupId
                imageId=imageId
                routeTable=tier.Network.RouteTable
                configSet=configSetName
                enableCfnSignal=true
                environmentId=environmentId
            /]
        [/#if]
    [/#list]
[/#if]