# Architecture
This Bicep deploys Azure Monitor Private Link Scope environment with reporting windows VM.
![](/imgs/ampls-architecture.png)

# Deploy Process
Simply deploy `main.bicep`.

Create resource group.
```bash
$ az group create --name <YOUR-RG-NAME> --location <LOCATION>
```
Deploy `main.bicep` with/without parameter file.
```bash
$ az deployment group create --resource-group <YOUR-RG-NAME> --template-file main.bicep --parameters .\params-samples.json
```


# Notes
There are some points to mention.

## Deploy Error
If you encount the error like bellow, please redeploy bicep file with the same command.
```
"The resource write operation failed to complete successfully, because it reached terminal provisioning state 'Failed'.","details":[{"code":"BadRequest","message":"Call to microsoft.insights/privateLinkScopes failed. Error message: Mismatching RequiredMembers in Request","details"
```
redeploy without even thinking
```bash
$ az deployment group create --resource-group <YOUR-RG-NAME> --template-file main.bicep --parameters .\params-samples.json
```

## Don't use complete mode
ARM / bicep template deployment in complete mode of private endpoints is not supported because there is no method of referencing the private endpoint network interface in the ARM template to prevent the deletion that happens. 
The suggestion is to use incremental mode deployment to perform this deployment. 

# Check AMPLS is working
Open Log Analytics Workspace [Logs] Tab and display `Heartbeat` table. Check the `ComputerIP` is displayed in IPv6 format. This means the log comes through private endpoint.
![](/imgs/law.png)