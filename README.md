# Deployment Stacks What-If demos (NIC 2026)

The demos from the NIC 2026 session **Beyond the Basics: Using the New What-If for Deployment
Stacks, Debugging, and AI-Assisted Bicep**, in Oslo on 14 October 2026.

There are two demos:

- **Stacks What-If.** A small app is deployed as a deployment stack, and a pull request opens SSH
  to the internet and takes the virtual network out of the template. The demo runs regular What-If
  and Stacks What-If on that pull request, shows detach versus delete, and then deploys it.
- **AI-assisted Bicep.** Resources built by hand in the portal get brought under a new stack by
  GitHub Copilot, using a skill, and Stacks What-If checks that nothing changes. Then Copilot
  switches a GitHub Actions pipeline over to the stack, with a Stacks What-If step before the
  deploy.

There's also a shorter validation demo with `bicep snapshot` and `bicep lint`, which runs locally.

## What's in here

| File or folder | What it is |
| --- | --- |
| `stacks-whatif-demo\` | `app.v1.bicep` is what's deployed, and `app.v2.bicep` is the pull request |
| `demo.ps1`, `Start-Demo.ps1` | The Stacks What-If demo. Each step shows the command, and Enter runs it |
| `ai-demo\` | The AI demo: the two skills in `.github\skills`, the recorded Copilot chat in `chat\`, the files Copilot wrote, the pipeline, and the prompts to run it live |
| `stacks-whatif-demo-debug\`, `Start-ValidationDemo.ps1` | The validation demo: a snapshot, a refactor that passes, and the pull request that doesn't, then lint |
| `Prepare-Stage.ps1`, `Prepare-Brownfield.ps1` | Create the Azure side, and put it back to the starting point after a run |
| `Setup-Laptop.ps1` | Checks the tools, sets everything up, and opens the demo windows |
| `demo.config.json` | Your subscription, resource group names and region |

## Before you start

- A **test** subscription you can create resource groups in. The demo creates
  `rg-demo-nic2026-stacks` and `rg-demo-nic2026-brownfield`, and step 10 really deploys to the stack.
- Windows, PowerShell 7, Az.Resources 10.2.1 or later, the Bicep CLI (0.41.2 or later for
  `bicep snapshot`), and VS Code with the Bicep extension. The Azure CLI 2.88 or later is optional,
  for `az stack-whatif`.

## Run it

1. Put your subscription ID in `demo.config.json`, and change the region if you want.
2. Double-click `SETUP-LAPTOP.cmd`. It asks before it installs anything. It also adds a VS Code
   keyboard shortcut that only works in the demo folder, so Enter in the editor goes to the demo
   terminal.
3. In the **Stacks What-If demo** window, press Ctrl+` to start. Each step shows the command first,
   Enter runs it, and Enter again goes to the next step.
4. After a run, double-click `SETUP-LAPTOP.cmd` again, or run `Prepare-Stage.ps1`, to put the stack
   back.

`.\Start-Demo.ps1 -Replay` shows saved results without Azure, once you've done one live run.

A few things to know:

- The noise in the regular What-If came from a tag policy on our test subscription. On yours it
  may look different, or there may be none.
- The Stacks What-If retention interval is 1 to 3 hours right now.
- The recorded chat in `ai-demo\chat` is a real Copilot session, with the IDs taken out. If you run
  it live, the answers can be a bit different.

## Clean up

- Run `Remove-Demo.ps1` to delete the demo resource group, and delete `rg-demo-nic2026-brownfield`
  in the portal.
- Take the demo shortcut out of VS Code: File > Preferences > Keyboard Shortcuts (JSON), and delete
  the entry that mentions `stacks-whatif-demo`.

## Learn more

- Stacks What-If docs: aka.ms/stackswhatif
- The GA announcement: aka.ms/stackswhatifGA
- bicep snapshot: aka.ms/bicep/snapshot
- Bicep MCP server: aka.ms/bicep/mcp
- Deployment Stacks feedback and issues: aka.ms/stacks-feedback
