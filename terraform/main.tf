terraform {

  backend "s3" {
    bucket = "tcpdump-orchestrator"
    key = "terraform.tfstate"

    endpoint = "https://s3.cloud.int"
    region = "main"
    skip_credentials_validation = true
    skip_metadata_api_check = true
    skip_region_validation = true
    force_path_style = true
  }


  required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }

    kubernetes = {      
    }

    helm = {      
    }    
  }
}

# Create the DNS domain plmn A
provider "openstack" {
}

# Provider configuration for Kubernetes
provider "kubernetes" { 
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "openstack_dns_zone_v2" "domain" {
  name  = "${var.namespace}.${local.domain}."
  email = "admin@${local.domain}"
  ttl   = 60
}


# Create a Kubernetes namespaces
resource "kubernetes_namespace" "orchestrator" {
  metadata {
    name = "${var.namespace}"
    labels = {
      environment = "main"
      team        = "devops"    
      istio-injection = "enabled"    
    }
    annotations = {
      description = "Namespace for orchestrator"
    }
  }
}


resource "kubernetes_secret" "harbor_registry_secret" {
  metadata {
    name      = local.harbor_secret
    namespace = var.namespace
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${local.harbor_url}" = {
          username = var.harbor_user
          password = var.harbor_pass
          auth     = base64encode("${var.harbor_user}:${var.harbor_pass}")
        }
      }
    })
  }

  depends_on = [ kubernetes_namespace.orchestrator ]
}



# PLMN A:
# Create DNS records for each host
resource "openstack_dns_recordset_v2" "hosts" {
  
  zone_id = openstack_dns_zone_v2.domain.id
  name    = "${local.orc8r_name}.${var.namespace}.${local.domain}."
  type    = "A"
  ttl     = 60
  records = [ var.istio_lb_ip ]
}


resource "helm_release" "open5gs_orchestrator" {
  name       = var.orchestration_installation_name
  namespace  = var.namespace
  repository = var.harbor_project
  chart      = var.helm_chart_name
  version    = var.helm_version
  values     = [file("../values.yaml")]
  wait       = true
  timeout    = 600  
  depends_on = [  kubernetes_namespace.orchestrator,
                  kubernetes_secret.harbor_registry_secret,
                  openstack_dns_recordset_v2.hosts]
}


locals {
  config = yamldecode(file("${path.module}/../values.yaml"))
  harbor_secret = "${local.config.imagePullSecret}"
  harbor_url    = "${local.config.image.registryUrl}"
  domain        = "${local.config.global.domain}"
  orc8r_name    = "${local.config.orchestrator.name}"
}


variable namespace {
  type = string
}

variable harbor_user {
  type = string 
}

variable harbor_pass {
  type = string 
}

variable istio_lb_ip{
  type = string
}

variable orchestration_installation_name{
  type = string
}

variable harbor_project{
  type = string
}

variable helm_chart_name{
  type = string
}

variable helm_version{
  type = string
}