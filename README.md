# par-azure-vm-bastion

Terraform Template to deploy Windows VM with Bastion Host on Azure

## Prerequisites

- *Azure CLI* v2.46.0 or above
- *Terraform CLI* v1.3.7 or above

## Usage

### Create Resources

1. Log in to Azure and switch to your target subscription.

```sh
az login
az account set --subscription "YOUR_SUBSCRIPTION_NAME"
```

2. Terraform init and apply.

```sh
terraform init
terraform apply -var "resource_group_name=rg-your-resource-group" -var "suffix=vmtest"
```

If you get an error `Failed to connect to MSI` then logout and login with a service principal instead.

```bash
az logout
az login --service-principal \
  --tenant "00000000-0000-0000-0000-000000000000" \
  --username "00000000-0000-0000-0000-000000000000" \
  --password "ThisIsYourSecret"
```

3. Retrieve sysadmin username and password.

```sh
echo "USERNAME: $(terraform output -raw windows_virtual_machine_admin_username)"
echo "PASSWORD: $(terraform output -raw windows_virtual_machine_admin_password)"
```

4. Open [Azure Portal](https://portal.azure.com/) and go to your virtual machine and connect to the VM using Bastion using the `sysadmin` username and the password from 3.

5. Create another local admin account and log in using the new account next time. Do not use sysadmin account.

### Turn Off

Turn off virtual machine and delete Bastion host to save cost.

```sh
RESOURCE_GROUP_NAME="$(terraform output -raw resource_group_name)"
VM_NAME="$(terraform output -raw windows_virtual_machine_name)"
az vm stop --resource-group "${RESOURCE_GROUP_NAME}" --name "${VM_NAME}" --no-wait
terraform apply -var "resource_group_name=rg-your-resource-group" -var "suffix=vmtest" -var "bastion=false"
```

### Turn On

Turn on virtual machine and create Bastion host.

```sh
RESOURCE_GROUP_NAME="$(terraform output -raw resource_group_name)"
VM_NAME="$(terraform output -raw windows_virtual_machine_name)"
az vm start --resource-group "${RESOURCE_GROUP_NAME}" --name "${VM_NAME}" --no-wait
terraform apply -var "resource_group_name=rg-your-resource-group" -var "suffix=vmtest" -var "bastion=true"
```

### GitHub Actions

To use GitHub Actions to turn on or off the virtual machine, follow this instruction.

1. You should already have a service principal. If not, create one and make sure it has neccessary permissions to deploy resources in the resource group.
2. Go to your service principal and [configure a new OIDC federated crendential](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure) with the scope to your repository's environment named `azure`.
3. [Clone this repository](https://github.com/new?owner=ExxonMobil&template_name=par-azure-vm-bastion&template_owner=ExxonMobil) into yours.
4. Display and note these variables.

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

### Customization

You can customize using the the following variables:

| Variable | Description |
|---|---|
| location | Location name where all resources will be created. Default to resource group's location. Use command `az account list-locations --output table` to list all avaialble locations. |
| bastion | Whether to create bastion host. Default to `true`. To save cost, set to `false` to delete bastion host and set back to `true` when needed. It takes ~6-8 minutes to create or delete. |
