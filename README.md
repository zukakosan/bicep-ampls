# Architecture
# Deploy Process
Simply deploy `main.bicep`

create resource group
```bash
$ az group create --name <YOUR-RG-NAME> --location japaneast
```
deploy `main.bicep` with/without parameter file
```bash
$ az deployment group create --resource-group <YOUR-RG-NAME> --template-file main.bicep --parameters .\params-samples.json
```


# Attention
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
