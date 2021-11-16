locals {
  bin_dir = module.setup_clis.bin_dir
  tmp_dir = "${path.cwd}/.tmp"
}


module setup_clis {
  source = "github.com/cloud-native-toolkit/terraform-util-clis.git"

  clis = ["helm"]
}

resource "null_resource" "deploy_MongoCRD" {
  triggers = {
    namespace = var.mongo_namespace
    kubeconfig = var.cluster_config_file
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/deployMongoCRD.sh ${self.triggers.namespace}"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }

  provisioner "local-exec" {
    when = destroy
    command = "${path.module}/scripts/deployMongoCRD.sh ${self.triggers.namespace} destroy"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
} 

resource "null_resource" "deploy_mongoClusterRole" {
  triggers = {
    namespace = var.mongo_namespace
    msaname = var.mongo_serviceaccount
    kubeconfig = var.cluster_config_file
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/configMongoClusterRole.sh ${self.triggers.msaname} ${self.triggers.namespace}"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }

  provisioner "local-exec" {
    when = destroy
    command = "${path.module}/scripts/configMongoClusterRole.sh ${self.triggers.msaname} ${self.triggers.namespace} destroy"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}

resource "null_resource" "add_scc" {
  depends_on = [null_resource.deploy_mongoClusterRole]
  triggers = {
    kubeconfig = var.cluster_config_file
    namespace = var.mongo_namespace
    msaname = var.mongo_serviceaccount
    bin_dir = module.setup_clis.bin_dir
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/configSCC.sh ${self.triggers.bin_dir} ${self.triggers.msaname} ${self.triggers.namespace}"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }

  provisioner "local-exec" {
    when = destroy
    command = "${path.module}/scripts/configSCC.sh ${self.triggers.bin_dir} ${self.triggers.msaname} ${self.triggers.namespace} destroy"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}

resource "null_resource" "deploy_operator" {
  depends_on = [null_resource.add_scc]
  triggers = {
    kubeconfig = var.cluster_config_file
    namespace = var.mongo_namespace
    msaname = var.mongo_serviceaccount
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/installOperator.sh ${self.triggers.msaname} ${self.triggers.namespace}"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }

  provisioner "local-exec" {
    when = destroy
    command = "${path.module}/scripts/installOperator.sh ${self.triggers.msaname} ${self.triggers.namespace} destroy"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}

#  CREATE A CA CERTIFICATE

resource "tls_private_key" "ca" {
  algorithm   = "RSA"
  rsa_bits    = "2048"
}

resource "tls_self_signed_cert" "ca" {
  key_algorithm     = "${tls_private_key.ca.algorithm}"
  private_key_pem   = "${tls_private_key.ca.private_key_pem}"
  is_ca_certificate = true
  set_subject_key_id = true

  subject {
    common_name  = "*.mas-mongo-ce-svc.${var.mongo_namespace}.svc.cluster.local"
    organization = "Example, LLC"
  }
  
  validity_period_hours = 730 * 24
  allowed_uses = [
    "digital_signature",
    "content_commitment",
    "key_encipherment",
    "data_encipherment",
    "key_agreement",
    "cert_signing",
    "crl_signing",
    "encipher_only",
    "decipher_only",
    "any_extended",
    "server_auth",
    "client_auth",
    "code_signing",
    "email_protection",
    "ipsec_end_system",
    "ipsec_tunnel",
    "ipsec_user",
    "timestamping",
    "ocsp_signing"
  ]
  dns_names = [ "*.mas-mongo-ce-svc.${var.mongo_namespace}.svc.cluster.local","127.0.0.1","localhost" ]

}

# CREATE A TLS CERTIFICATE SIGNED USING THE CA CERTIFICATE

resource "tls_private_key" "cert" {
  algorithm   = "RSA"
  rsa_bits    = "2048"
}

resource "local_file" "cafile" {
  sensitive_content = "${tls_self_signed_cert.ca.cert_pem}"
  file_permission = "0600"
  filename    = "${local.tmp_dir}/ca.pem"
}

resource "tls_cert_request" "cert" {
  key_algorithm   = "${tls_private_key.cert.algorithm}"
  private_key_pem = "${tls_private_key.cert.private_key_pem}"

  dns_names = [ "*.mas-mongo-ce-svc.${var.mongo_namespace}.svc.cluster.local","127.0.0.1","localhost" ]

  subject {
    common_name  = "*.mas-mongo-ce-svc.${var.mongo_namespace}.svc.cluster.local"
    organization = "Example, LLC"
  }
}

resource "tls_locally_signed_cert" "cert" {
  cert_request_pem = "${tls_cert_request.cert.cert_request_pem}"

  ca_key_algorithm   = "${tls_private_key.ca.algorithm}"
  ca_private_key_pem = "${tls_private_key.ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.ca.cert_pem}"
  is_ca_certificate = true

  validity_period_hours = 730 * 24
  allowed_uses = [
    "digital_signature",
    "content_commitment",
    "key_encipherment",
    "data_encipherment",
    "key_agreement",
    "cert_signing",
    "crl_signing",
    "encipher_only",
    "decipher_only",
    "any_extended",
    "server_auth",
    "client_auth",
    "code_signing",
    "email_protection",
    "ipsec_end_system",
    "ipsec_tunnel",
    "ipsec_user",
    "timestamping",
    "ocsp_signing"
  ]

}

resource "local_file" "srvkeyfile" {
  sensitive_content = "${tls_private_key.cert.private_key_pem}"
  file_permission = "0600"
  filename    = "${local.tmp_dir}/server.key"
}

  resource "local_file" "srvcrtfile" {
  sensitive_content = "${tls_locally_signed_cert.cert.cert_pem}"
  file_permission = "0600"
  filename    = "${local.tmp_dir}/server.crt"
}

resource "null_resource" "deploy_certs" {
  depends_on = [null_resource.deploy_operator]
  triggers = {
    kubeconfig = var.cluster_config_file
    namespace = var.mongo_namespace
    certpath = local.tmp_dir
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/deployCerts.sh ${self.triggers.namespace} ${self.triggers.certpath}"
    
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }

  provisioner "local-exec" {
    when = destroy
    command = "${path.module}/scripts/deployCerts.sh ${self.triggers.namespace} ${self.triggers.certpath} destroy"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}

resource "null_resource" "deploy_instance" {
  depends_on = [null_resource.deploy_operator]
  triggers = {
    namespace = var.mongo_namespace
    mongopass = var.mongo_password
    storclass = var.mongo_storageclass
    kubeconfig = var.cluster_config_file
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/deployInstance.sh ${self.triggers.namespace} ${self.triggers.mongopass} ${self.triggers.storclass}"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }

  provisioner "local-exec" {
    when = destroy
    command = "${path.module}/scripts/deployInstance.sh ${self.triggers.namespace} null null destroy"

    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}

data "local_file" "svcname" {
    depends_on = [null_resource.deploy_instance]
    
    filename = "${local.tmp_dir}/mas-svc-name"
}
