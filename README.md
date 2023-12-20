# par-azure-vm-bastion

Terraform Template to deploy Windows VM with Bastion Host on Azure

## Prerequisites

- Active Azure subscription
- Azure AD service principal with permission to modify the target resource group
- Azure CLI v2.46.0 or above
- Terraform CLI v1.3.7 or above

## Create Resources

### Using Terraform Cloud

1. In [Terraform Cloud](https://app.terraform.io/), create a new workspace.
2. Chooose `Version Control Workflow`.
3. Click `GitHub App` and select this repository.
4. Once workspace is created, input `resource_group_name` and `suffix` variable.
5. Configure the following environment variables accordingly:

   - `ARM_CLIENT_ID`
   - `ARM_CLIENT_SECRET` - don't forget to mark as 'sensitive'
   - `ARM_TENANT_ID`
   - `ARM_SUBSCRIPTION_ID`
   
6. Click `+ New run` and then `Start run`.
7. The plan should run successfully. Review the plan then click `Confirm & apply` and then `Confirm plan`.
8. All resources should be created successfully

### Using CLI

1. Log in to Azure and switch to your target subscription.

```sh
az login --service-principal \
  --tenant "00000000-0000-0000-0000-000000000000" \
  --username "00000000-0000-0000-0000-000000000000" \
  --password "ThisIsYourSecret"
az account set --subscription "YOUR_SUBSCRIPTION_NAME"
```

2. Init and apply.

```sh
terraform init
terraform apply -var "resource_group_name=rg-your-resource-group" -var "suffix=vmtest"
```

## Retrieve Admin Credential

### Using Terraform Cloud

1. Go to States and open the latest one.
2. Input the following into the filter to get username and password resoectively:
   
   - `.outputs.windows_virtual_machine_admin_username.value`
   - `.outputs.windows_virtual_machine_admin_password.value`

### Using CLI

```sh
echo "USERNAME: $(terraform output -raw windows_virtual_machine_admin_username)"
echo "PASSWORD: $(terraform output -raw windows_virtual_machine_admin_password)"
```

## Connect to VM

1. Open [Azure Portal](https://portal.azure.com/). Go to your virtual machine and connect to the VM using Bastion.

2. Create another local admin account and log in using the new account next time. Do not use sysadmin account.

## Turn VM Off and On

### Using CLI

Use these commands to turn off virtual machine and delete Bastion host to save cost.

```sh
RESOURCE_GROUP_NAME="$(terraform output -raw resource_group_name)"
VM_NAME="$(terraform output -raw windows_virtual_machine_name)"
az vm stop --resource-group "${RESOURCE_GROUP_NAME}" --name "${VM_NAME}" --no-wait
terraform apply -var "resource_group_name=rg-your-resource-group" -var "suffix=vmtest" -var "bastion=false"
```

Use these commands to turn on virtual machine and create Bastion host.

```sh
RESOURCE_GROUP_NAME="$(terraform output -raw resource_group_name)"
VM_NAME="$(terraform output -raw windows_virtual_machine_name)"
az vm start --resource-group "${RESOURCE_GROUP_NAME}" --name "${VM_NAME}" --no-wait
terraform apply -var "resource_group_name=rg-your-resource-group" -var "suffix=vmtest" -var "bastion=true"
```

### Using GitHub Actions

To use GitHub Actions to turn on or off the virtual machine, follow this instruction.

1. Go to your service principal and [configure a new OIDC federated crendential](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure) with the scope to your repository's environment named `azure`.
2. Retrieve variables.

```sh
echo "RESOURCE_GROUP_NAME  : $(terraform output -raw resource_group_name)"
echo "VM_NAME              : $(terraform output -raw windows_virtual_machine_name)"
echo "BASTION_NAME         : $(terraform output -raw azurerm_bastion_host_name)"
echo "PUBLIC_IP_NAME       : $(terraform output -raw public_ip_name)"
echo "VNET_NAME            : $(terraform output -raw virtual_network_name)"
echo "AZURE_CLIENT_ID      : $(terraform output -raw azurerm_client_id)"
echo "AZURE_TENANT_ID      : $(terraform output -raw azurerm_tenant_id)"
echo "AZURE_SUBSCRIPTION_ID: $(terraform output -raw azurerm_subscription_id)"
```

3. Go to your repository settings and create environment `azure`.
4. Add all variables from 2 as environment variables.
5. Run the workflow `Start VM` or `Stop VM` as you wish.

## Customizations

You can customize using the the following variables:

| Variable | Description |
|---|---|
| location | Location name where all resources will be created. Default to resource group's location. Use command `az account list-locations --output table` to list all avaialble locations. |
| bastion | Whether to create bastion host. Default to `true`. To save cost, set to `false` to delete bastion host and set back to `true` when needed. It takes ~6-8 minutes to create or delete. |

## Troubleshooting

### EncryptionAtHost is not enabled

If you get the error `'Microsoft.Compute/EncryptionAtHost' feature is not enabled for this subscription` when apply. 

1. Execute the following command to enable this feature in your subscription:

```sh
az feature register --namespace Microsoft.Compute --name EncryptionAtHost
```

2. Wait until the feature is registered (state = `Registered`). This might take around 20 minutes. You may use this command to monitor:

```sh
watch az feature show --namespace Microsoft.Compute --name EncryptionAtHost
```

3. Execute this command to ensure the change is propagated:
   
```sh
az provider register -n Microsoft.Compute
```
