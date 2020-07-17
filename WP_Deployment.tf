variable "WORDPRESS_DB_HOST" {
  default = "mysql-service"
}
variable "WORDPRESS_DB_PASSWORD" {
  default = "1234"
}
variable "MYSQL_ROOT_PASSWORD" {
  default = "12345"
}

provider "kubernetes" {
  load_config_file = "true"

  # host = "https://104.196.242.174"

  # client_certificate     = "${file("~/.kube/client-cert.pem")}"
  # client_key             = "${file("~/.kube/client-key.pem")}"
  # cluster_ca_certificate = "${file("~/.kube/cluster-ca-cert.pem")}"
}

resource "kubernetes_secret" "wordpress_mysql" {
  metadata {
    name = "secret-store"
    labels = {
      app         = "wordpress_mysql"
      environment = "dev"
    }
  }

  data = {
    WORDPRESS_DB_HOST     = var.WORDPRESS_DB_HOST
    WORDPRESS_DB_PASSWORD = var.WORDPRESS_DB_PASSWORD
    MYSQL_ROOT_PASSWORD   = var.MYSQL_ROOT_PASSWORD
  }
}

resource "kubernetes_service" "wordpress" {
  metadata {
    name = "wordpress-service"
    labels = {
      app         = "wordpress"
      environment = "dev"
    }
  }
  spec {
    port {
      port        = 80
      target_port = 80
      node_port   = 32500
    }
    selector = {
      app         = kubernetes_deployment.wordpress.metadata[0].labels.app
      environment = kubernetes_deployment.wordpress.metadata[0].labels.environment
    }
    type = "NodePort"
  }
}

resource "kubernetes_service" "mysql" {
  metadata {
    name = "mysql-service"
    labels = {
      app         = "mysql"
      environment = "dev"
    }
  }
  spec {
    port {
      port        = 3306
      target_port = 3306
    }
    selector = {
      app         = kubernetes_deployment.mysql.metadata[0].labels.app
      environment = kubernetes_deployment.mysql.metadata[0].labels.environment
    }
    cluster_ip = "None"
  }
}

resource "kubernetes_persistent_volume_claim" "wordpress_pvc" {
  metadata {
    name = "wordpress-pvc"
    labels = {
      app         = "wordpress"
      environment = "dev"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "mysql_pvc" {
  metadata {
    name = "mysql-pvc"
    labels = {
      app         = "mysql"
      environment = "dev"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "mysql" {
  metadata {
    name = "mysql-deployment"
    labels = {
      app         = "mysql"
      environment = "dev"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app         = "mysql"
        environment = "dev"
      }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "50%"
        max_unavailable = "50%"
      }
    }

    template {
      metadata {
        labels = {
          app         = "mysql"
          environment = "dev"
        }
      }

      spec {
        volume {
          name = "mysql-persistent-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.mysql_pvc.metadata[0].name
          }
        }
        container {
          image = "mysql:5.7"
          name  = "mysql-container"

          port {
            container_port = 3306
            name           = "mysql"
          }

          volume_mount {
            mount_path = "/var/lib/mysql"
            name       = "mysql-persistent-storage"
          }

          env {
            name = "MYSQL_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.wordpress_mysql.metadata[0].name
                key  = "MYSQL_ROOT_PASSWORD"
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "wordpress" {
  metadata {
    name = "wordpress-deployment"
    labels = {
      app         = "wordpress"
      environment = "dev"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app         = "wordpress"
        environment = "dev"
      }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "50%"
        max_unavailable = "50%"
      }
    }

    template {
      metadata {
        labels = {
          app         = "wordpress"
          environment = "dev"
        }
      }

      spec {
        volume {
          name = "wordpress-persistent-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.wordpress_pvc.metadata[0].name
          }
        }
        container {
          image = "wordpress"
          name  = "wordpress-container"

          port {
            container_port = 80
            name           = "wordpress"
          }

          volume_mount {
            mount_path = "/var/www/html"
            name       = "wordpress-persistent-storage"
          }


          env {
            name = "WORDPRESS_DB_HOST"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.wordpress_mysql.metadata[0].name
                key  = "WORDPRESS_DB_HOST"
              }
            }
          }

          env {
            name = "WORDPRESS_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.wordpress_mysql.metadata[0].name
                key  = "WORDPRESS_DB_PASSWORD"
              }
            }
          }
        }
      }
    }
  }
}
