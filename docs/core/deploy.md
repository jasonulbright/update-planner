# Deploy page

The Deploy page runs the only step that changes the site. It creates one software update group and one deployment of that group for each wave that holds updates.

## What it does

The page shows the deployments that the plan would create. **Dry Run** runs the deploy step with `-WhatIf` and creates nothing. **Deploy...** asks for a confirmation, then creates the deployments. Both buttons stay off until you turn on **Enable Actions**.

The tool never edits or deletes an existing deployment or group. It does not create deployment packages, and it does not download content.

## When to use it

- Use **Dry Run** to see what the plan would create.
- Use **Deploy...** only after you reviewed the plan and the report.

## Requirements

- A plan.
- **Enable Actions** is on.
- For **Deploy...**: a right to create software update deployments on the site.
- No wave targets a built-in collection. See below.

## Steps

### See the deployments that the plan would create

1. Build a plan.
2. Select **Deploy** in the sidebar.
3. Read the upper grid. It has one row for each wave that holds updates.

![The Deploy page with the Enable Actions switch off](../images/deploy-off.png)

Each deployment, and its software update group, is named `UpdatePlanner <plan ID> Wave <n> <collection name>`. The grid has the columns **Deployment Name**, **Collection**, **ID**, **Updates**, **Start** and **Deadline**.

### Run a dry run

1. Select the **Enable Actions** switch. It shows **On**.
2. Select **Dry Run**. The overlay shows "Running the deploy step with -WhatIf...". A dry run does not open the site drive.
3. Read the lower grid. Each row shows **Dry run** in **Result** and the message "Would create this deployment. Nothing was created."
4. Read the log. It ends with "DryRun: 3 results, 0 created, 0 failed."

![The Deploy page with the switch on and both buttons on](../images/deploy-on.png)

![The overlay of a dry run](../images/deploy-dry-run-running.png)

![The Deploy page after a dry run](../images/deploy-dry-run.png)

A dry run writes one record to the action log. See [Files and logs](../reference/files-and-logs.md).

### Create the deployments

1. Select **Deploy...**. The tool first checks the plan (see [Deploy to a built-in collection](#deploy-to-a-built-in-collection)). Then a confirmation with the title **Create Deployments** shows.
2. Read the text. The tool builds it as follows. `<n>` is the number of waves that hold updates. There is one line for each of these waves.

   ```text
   Create <n> software update groups and <n> deployments on site <site code> (provider <SMS Provider>)?

   <collection>: <number> updates, <start> to <deadline>

   This changes the site. To undo, delete the deployments and the software update groups whose name holds the plan ID <plan ID>. Update Planner never edits or deletes an existing deployment or group.
   ```

3. Select **Yes** to create the deployments. The log writes `Deploy plan <plan ID>: <n> deployments.` and the overlay shows "Creating the deployments...". Select **No**, or press Esc, to stop. The log writes "Deploy cancelled."

![The confirmation before the tool creates the deployments](../images/deploy-confirm.png)

![The Deploy page after No](../images/deploy-cancelled.png)

After **Yes**, the lower grid shows one row for each wave with **Created** and the assignment ID, or **Failed** and the message. The status bar shows "Apply finished: <n> created, <n> failed." The action log gets one record.

To undo a run, delete the deployments and the software update groups whose name holds the plan ID. Review a created deployment in the console before a real rollout.

### Deploy to a built-in collection

A wave that targets a built-in collection (an ID that starts with `SMS`) blocks **Deploy...**.

1. Add a built-in collection, for example All Systems, as a wave. Build the plan.
2. Select **Deploy** in the sidebar. Turn on **Enable Actions**.
3. Select **Deploy...**. A message box with the title **Deploy Blocked** names the wave and the collection: `<wave>: the collection <ID> is built in. Deployments to built-in collections are blocked.` The log writes "Deploy blocked:" with the same text. Nothing is created.

A plan in which no wave holds an update is blocked the same way, with the message "The plan holds no update to deploy."

![The message that blocks a deployment to a built-in collection](../images/deploy-blocked.png)

**Dry Run** still works for such a plan. The plan shows what the deployment would target.

### Deploy page in the light theme

![The Deploy page in the light theme after a dry run](../images/deploy-light.png)

![The confirmation in the light theme](../images/deploy-confirm-light.png)

## Options and settings of this page

| Control | Default | Effect |
|---|---|---|
| **Enable Actions** | Off | Turns on **Dry Run** and **Deploy...**. The state is not saved. The tool starts with the switch off. |
| **Dry Run** | - | Runs the deploy step with `-WhatIf`. Creates nothing. |
| **Deploy...** | - | Asks for a confirmation, then creates the deployments. |

A group holds the update IDs of the wave. The deployment of the group sets the collection, the start time, the deadline (required), notification on and local time. The deployment does not allow installation or restart outside the maintenance window after the deadline. See [Plan rules](../reference/plan-rules.md).

The status bar shows "actions enabled" or "read only".

## Limits

- **Yes** is the default button of the confirmation. Pressing Enter creates the deployments. **No** is the cancel button. Pressing Esc stops.
- The tool creates deployments only for waves that hold updates.
- A time zone difference can show another clock time on the site server. See [Plan rules](../reference/plan-rules.md).

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| Dry Run and Deploy... are off. | **Enable Actions** is off, or no plan exists. | Build a plan and turn on **Enable Actions**. |
| Deploy blocked: Wave 4 All Systems: the collection SMS00001 is built in. Deployments to built-in collections are blocked. | A wave targets a built-in collection. | Remove the wave and build the plan again. |
| Failed ... in the **Result** column | The site refused a deployment. The **Message** column shows the reason. | Note the plan ID and read every result. A software update group of that wave can exist without a deployment: check the console and delete the unused group. Fix the cause. Build the plan again. Review every wave before you deploy again. |

## Links

- [Manually deploy software updates](https://learn.microsoft.com/intune/configmgr/sum/deploy-use/manually-deploy-software-updates): Describes how to deploy software updates.
- [Monitor software updates](https://learn.microsoft.com/intune/configmgr/sum/deploy-use/monitor-software-updates): Describes how to check the state of a deployment.
