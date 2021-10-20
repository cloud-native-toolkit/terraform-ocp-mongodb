#  MongoDB-CE / OCP terraform module

![Verify and release module](https://github.com/cloud-native-toolkit/terraform-ocp-mongodb/workflows/Verify%20and%20release%20module/badge.svg)

Deploys MongoDB Community Edition on RedHat OpenShift within a given namespace.  This module also enables security and creates required certifcates that can be used for secure connections.  

## Supported platforms

- OCP 4.6+

## Module dependencies

The module uses the following elements

### Terraform providers

- helm - used to configure the scc for OpenShift
- null - used to run the shell scripts

### Environment

- kubectl - used to apply yaml 

## Suggested companion modules

The module itself requires some information from the cluster and needs a
namespace to be created. The following companion
modules can help provide the required information:

- Cluster - https://github.com/ibm-garage-cloud/terraform-cluster-ibmcloud
- Namespace - https://github.com/ibm-garage-cloud/terraform-cluster-namespace

## Example usage

```hcl-terraform
module "dev_ocp_mongoce" {
  source = "github.com/cloud-native-toolkit/terraform-ocp-mongodb"

  cluster_config_file      = module.cluster.config_file_path
  cluster_type             = module.cluster.platform.type_code
  cluster_ingress_hostname = module.cluster.platform.ingress
  tls_secret_name          = module.cluster.platform.tls_secret
  
  mongo_namespace    = var.mongo_namespace
}
```

