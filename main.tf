##############################################################################
# IBM Cloud Provider 1.35.0
##############################################################################

terraform {
  required_providers {
    ibm = {
      source = "ibm-cloud/ibm"
      version = "1.50"
    }
  }
}

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  generation       = 2
  region           = var.VPC_Region
  ibmcloud_timeout = 300
  resource_group   = var.Resource_Group
}

##############################################################################
# Variable block - See each variable description
##############################################################################

variable "VPC_Region" {
  default     = "eu-de"
  description = "The region where the VPC, networks, and Check Point VSI will be provisioned."
}

variable "Resource_Group" {
  default     = "secrsi-rg-sandbox"
  description = "The resource group that will be used when provisioning the Check Point VSI. If left unspecififed, the account's default resource group will be used."
}

variable "VPC_Name" {
  default     = "secrsi-vpc-connectivity"
  description = "The VPC where the Check Point VSI will be provisioned."
}

variable "Management_Subnet_ID" {
  default     = "02c7-65467ae1-c1ca-4e29-aebb-6098234f82a4"
  description = "The ID of the Check Point management subnet."
}

variable "External_Subnet_ID" {
  default     = "02c7-cadb31fd-fbb6-4ba5-bac5-4ffefa91a6c4"
  description = "The ID of the subnet that exists in front of the Check Point Security Gateway that will be provisioned (the 'external' network)."
}

variable "Internal_Subnet_ID" {
  default     = "02c7-40600da5-2597-4c6b-91bb-cb0655ddd3f8"
  description = "The ID of the subnet that exists behind  the Check Point Security Gateway that will be provisioned (the 'internal' network)."
}

variable "SSH_Key" {
  default     = "secrsi-nelson"
  description = "The pubic SSH Key that will be used when provisioning the Check Point VSI."
}

variable "VNF_CP-GW_Instance" {
  default     = "secrsi-checkpoint-gateway2"
  description = "The name of the Check Point Security Gatewat that will be provisioned."
}

variable "VNF_Security_Group" {
  default     = "secrsi-vpc-connectivity-sg-checkpoint2"
  description = "The name of the security group assigned to the Check Point VSI."
}

variable "VNF_Profile" {
  default     = "cx2-8x16"
  description = "The VNF profile that defines the CPU and memory resources. This will be used when provisioning the Check Point VSI."
}

variable "CP_Version" {
  default     = "R8110"
  description = "The version of Check Point to deploy. R8110, R81, R8040, R8030"
}

variable "CP_Type" {
  default     = "Gateway"
  description = "(HIDDEN) Gateway or Management"
}

variable "vnf_license" {
  default     = ""
  description = "(HIDDEN) Optional. The BYOL license key that you want your cp virtual server in a VPC to be used by registration flow during cloud-init."
}

variable "ibmcloud_endpoint" {
  default     = "cloud.ibm.com"
  description = "(HIDDEN) The IBM Cloud environmental variable 'cloud.ibm.com' or 'test.cloud.ibm.com'"
}

variable "delete_custom_image_confirmation" {
  default     = ""
  description = "(HIDDEN) This variable is to get the confirmation from customers that they will delete the custom image manually, post successful installation of VNF instances. Customer should enter 'Yes' to proceed further with the installation."
}

variable "ibmcloud_api_key" {
  default     = ""
  description = "(HIDDEN) holds the user api key"
}

variable "TF_VERSION" {
 default = "0.13"
 description = "terraform engine version to be used in schematics"
}

##############################################################################
# Data block 
##############################################################################

data "ibm_is_subnet" "cp_subnet0" {
  identifier = var.Management_Subnet_ID
}

data "ibm_is_subnet" "cp_subnet1" {
  identifier = var.External_Subnet_ID
}

data "ibm_is_subnet" "cp_subnet2" {
  identifier = var.Internal_Subnet_ID
}

data "ibm_is_ssh_key" "cp_ssh_pub_key" {
  name = var.SSH_Key
}

data "ibm_is_instance_profile" "vnf_profile" {
  name = var.VNF_Profile
}

data "ibm_is_region" "region" {
  name = var.VPC_Region
}

data "ibm_is_vpc" "cp_vpc" {
  name = var.VPC_Name
}

data "ibm_resource_group" "rg" {
  name = var.Resource_Group
}

##############################################################################
# Create Security Group
##############################################################################

resource "ibm_is_security_group" "ckp_security_group" {
  name           = var.VNF_Security_Group
  vpc            = data.ibm_is_vpc.cp_vpc.id
  resource_group = data.ibm_resource_group.rg.id
}

#Egress All Ports
resource "ibm_is_security_group_rule" "allow_egress_all" {
  depends_on = [ibm_is_security_group.ckp_security_group]
  group      = ibm_is_security_group.ckp_security_group.id
  direction  = "outbound"
  remote     = "0.0.0.0/0"
}

#Ingress All Ports
resource "ibm_is_security_group_rule" "allow_ingress_all" {
  depends_on = [ibm_is_security_group.ckp_security_group]
  group      = ibm_is_security_group.ckp_security_group.id
  direction  = "inbound"
  remote     = "0.0.0.0/0"
}

##############################################################################
# Create Check Point Gateway
##############################################################################

locals {
  image_name = "${var.CP_Version}-${var.CP_Type}"
  image_id = lookup(local.image_map[local.image_name], var.VPC_Region)
}

resource "ibm_is_subnet_reserved_ip" "mgmt" {
  subnet    = data.ibm_is_subnet.cp_subnet0.id
  name      = "secrsi-checkpoint-reserved-ip0"
  address        = "10.10.11.132"
}

resource "ibm_is_subnet_reserved_ip" "external" {
  subnet    = data.ibm_is_subnet.cp_subnet1.id
  name      = "secrsi-checkpoint-reserved-ip1"
  address        = "10.10.11.4"
}

resource "ibm_is_subnet_reserved_ip" "internal" {
  subnet    = data.ibm_is_subnet.cp_subnet2.id
  name      = "secrsi-checkpoint-reserved-ip2"
  address        = "10.10.11.68"
}

resource "ibm_is_instance" "cp_gw_vsi" {
  depends_on     = [ibm_is_security_group_rule.allow_ingress_all]
  name           = var.VNF_CP-GW_Instance
  image          = local.image_id
  profile        = data.ibm_is_instance_profile.vnf_profile.name
  resource_group = data.ibm_resource_group.rg.id

  #eth0 - Management Interface
  primary_network_interface {
    name            = "eth0"
    subnet          = data.ibm_is_subnet.cp_subnet0.id
    primary_ip {
      reserved_ip = ibm_is_subnet_reserved_ip.mgmt.reserved_ip
    }
    security_groups = [ibm_is_security_group.ckp_security_group.id]
    allow_ip_spoofing = true
  }

  #eth1 - External Interface
  network_interfaces {
    name            = "eth1"
    subnet          = data.ibm_is_subnet.cp_subnet1.id
    primary_ip {
      reserved_ip = ibm_is_subnet_reserved_ip.external.reserved_ip
    }
    security_groups = [ibm_is_security_group.ckp_security_group.id]
    allow_ip_spoofing = true
  }

  #eth2 - Internal Interface
  network_interfaces {
    name            = "eth2"
    subnet          = data.ibm_is_subnet.cp_subnet2.id
    primary_ip {
      reserved_ip = ibm_is_subnet_reserved_ip.internal.reserved_ip
    }
    security_groups = [ibm_is_security_group.ckp_security_group.id]
    allow_ip_spoofing = true
  }

  vpc  = data.ibm_is_vpc.cp_vpc.id
  zone = data.ibm_is_subnet.cp_subnet0.zone
  keys = [data.ibm_is_ssh_key.cp_ssh_pub_key.id]

  #Custom UserData
  #user_data = file("user_data")

  timeouts {
    create = "15m"
    delete = "15m"
  }

  provisioner "local-exec" {
    command = "sleep 30"
  }
}
