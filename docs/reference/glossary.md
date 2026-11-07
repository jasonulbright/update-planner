# Glossary

This page defines the terms of Update Planner.

## What it does

The page gives one meaning for each term. The tool and the other pages use the term in this meaning only.

## When to use it

Use this page when a term is not clear.

## Requirements

None.

## Terms

| Term | Meaning |
|---|---|
| Action log | The file `Logs\update-planner-actions.jsonl`. It holds one record for each dry run and each deployment. |
| Built-in collection | A collection whose ID starts with `SMS`, for example All Systems (`SMS00001`). The tool blocks a deployment to it. |
| Console | The Configuration Manager console. The tool needs it on this computer, because the ConfigurationManager module comes only with it. |
| Deadline | The date on which the installation becomes mandatory. It is the wave start date plus **Days to deadline**. |
| Deployment | A software update deployment on the site (`SMS_UpdatesAssignment`). The tool creates one for each wave. |
| Dry run | The deploy step with `-WhatIf`. It shows the deployments and creates nothing. |
| Enable actions | The switch on the Deploy page. It turns on **Dry run** and **Deploy...**. |
| Plan | The result of **Build plan**: the waves, the dates, the updates of each wave and the skipped updates. |
| Plan ID | An eight-character ID of one plan. It is in the deployment names and in the action log. |
| Provider | The SMS Provider: the computer that gives access to the site data. |
| Skipped update | An update that the plan did not put in a wave. The grid lists the reason. |
| Superseded | An update that a newer update replaces. |
| Wave | One step of the rollout. A wave has a collection, a start date, a deadline and a list of updates. |
| Wave collection | A device collection that is one wave. The first collection in the list is wave 1. |

## Steps

None.

## Limits

None.

## Troubleshooting

See [Troubleshooting](../troubleshooting.md).

## Links

None.
