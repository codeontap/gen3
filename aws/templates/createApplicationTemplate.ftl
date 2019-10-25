[#ftl]
[#if (deploymentUnit == "model")  &&
    (!((deploymentUnitSubset!"") == "genplan"))]
    [#assign deploymentFrameworkModel = ""]
[/#if]
[#include "/bootstrap.ftl" ]

[#assign outputType = commandLineOptions.Deployment.Output.Type]

[#-- Add tests to initialised test outputs --]
[#if commandLineOptions.Input.TestCase?has_content &&
        (commandLineOptions.Deployment.Unit.Subset!"") == "testplan" ]
    [@addTestPlanToDefaultJsonOutput tests=testsList /]
[/#if]

[#-- Special processing --]
[#switch getDeploymentUnit()]
    [#case "iam"]
        [#if commandLineOptions.Deployment.Unit.Subset?has_content &&
            (commandLineOptions.Deployment.Unit.Subset == "pregeneration") ]
            [#assign allDeploymentUnits = true]
            [#assign ignoreDeploymentUnitSubsetInOutputs = true]
            [#break]
        [/#if]
        [#-- Fall through to lg processing --]
    [#case "lg"]
        [#if (commandLineOptions.Deployment.Unit.Subset!"") == "genplan"]
            [@initialiseDefaultScriptOutput format=commandLineOptions.Deployment.Output.Format /]
            [@addDefaultGenerationPlan subsets="template" /]
        [#else]
            [#if !(commandLineOptions.Deployment.Unit.Subset?has_content)]
                [#assign allDeploymentUnits = true]
                [#assign commandLineOptions =
                    mergeObjects(
                        commandLineOptions,
                        {
                            "Deployment" : {
                                "Unit" : {
                                    "Subset" : getDeploymentUnit()
                                }
                            }
                        }
                    ) ]
                [#assign ignoreDeploymentUnitSubsetInOutputs = true]
            [/#if]
        [/#if]
        [#break]
    [#case "model"]
        [#if (commandLineOptions.Deployment.Unit.Subset!"") == "genplan"]
            [@initialiseDefaultScriptOutput format=commandLineOptions.Deployment.Output.Format /]
            [@addDefaultGenerationPlan subsets="config" /]
        [#else]
            [#assign commandLineOptions =
                mergeObjects(
                    commandLineOptions,
                    {
                        "Output" : {
                            "Type" : "model"
                        }
                    }
                ) ]
        [/#if]

[/#switch]

[@generateOutput
    deploymentFramework=commandLineOptions.Deployment.Framework.Name
    type=commandLineOptions.Deployment.Output.Type
    format=commandLineOptions.Deployment.Output.Format
    level="application"
/]
