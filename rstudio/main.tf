terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
  }
}

locals {
  cpu-limit = "2"
  memory-limit = "4G"
  cpu-request = "500m"
  memory-request = "1G" 
  home-volume = "10Gi"
  image = "ghcr.io/sempie/rstudio:v0.1"
}

provider "coder" {

}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default = false
}

variable "workspaces_namespace" {
  description = <<-EOF
  Kubernetes namespace to deploy the workspace into

  EOF
  default = ""
}

data "coder_parameter" "dotfiles_url" {
  name        = "Dotfiles URL (optional)"
  description = "Personalize your workspace e.g., https://github.com/sharkymark/dotfiles.git"
  type        = "string"
  default     = ""
  mutable     = true 
  icon        = "https://git-scm.com/images/logos/downloads/Git-Icon-1788C.png"
  order       = 1
}

data "coder_parameter" "appshare" {
  name        = "App Sharing"
  type        = "string"
  description = "What sharing level do you want for the IDEs?"
  mutable     = true
  default     = "owner"
  icon        = "/emojis/1f30e.png"

  option {
    name = "Accessible outside the Coder deployment"
    value = "public"
    icon = "/emojis/1f30e.png"
  }
  option {
    name = "Accessible by authenticated users of the Coder deployment"
    value = "authenticated"
    icon = "/emojis/1f465.png"
  } 
  option {
    name = "Only accessible by the workspace owner"
    value = "owner"
    icon = "/emojis/1f510.png"
  } 
  order       = 2      
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}

resource "coder_agent" "coder" {
  os   = "linux"
  arch = "amd64"

# The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  display_apps {
    vscode = false
    vscode_insiders = false
    ssh_helper = false
    port_forwarding_helper = false
    web_terminal = true
  }

  dir = "/home/coder"
  startup_script = <<EOT
#!/bin/bash

# install code-server
curl -fsSL https://code-server.dev/install.sh | sh 
code-server --auth none --port 13337 >/dev/null 2>&1 &

# configure nginx
cat <<EOF > /home/coder/.nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
        worker_connections 768;
        # multi_accept on;
}

http {
  map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
  }

  server {
    listen 8788;

    client_max_body_size 0; # Disables checking of client request body size

    location /@${data.coder_workspace.me.owner}/${lower(data.coder_workspace.me.name)}.coder/apps/rstudio/ {
      rewrite ^/@${data.coder_workspace.me.owner}/${lower(data.coder_workspace.me.name)}.coder/apps/rstudio/(.*)\$ /\$1 break;
      proxy_set_header X-RSC-Request \$scheme://\$http_host\$request_uri;
      proxy_pass http://localhost:8787;
      proxy_redirect / /@${data.coder_workspace.me.owner}/${lower(data.coder_workspace.me.name)}.coder/apps/rstudio/;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_http_version 1.1;
      proxy_set_header X-RStudio-Root-Path /@${data.coder_workspace.me.owner}/${lower(data.coder_workspace.me.name)}.coder/apps/rstudio;
      proxy_set_header Host \$host;
    }
    location /healthz {
      return 200;
    }
  }
}
EOF

# start rstudio
/usr/lib/rstudio-server/bin/rserver --server-daemonize=1 --auth-none=1 >/dev/null 2>&1 &

# start nginx
sudo nginx -c /home/coder/.nginx.conf

# clone repo
if [ ! -d "connect-examples" ]; then
  git clone --progress https://github.com/rstudio/connect-examples.git &
fi
if [ ! -d "shiny-examples" ]; then
  git clone --progress https://github.com/rstudio/shiny-examples.git &
fi

# use coder CLI to clone and install dotfiles
if [[ ! -z "${data.coder_parameter.dotfiles_url.value}" ]]; then
  coder dotfiles -y ${data.coder_parameter.dotfiles_url.value}
fi

# enable git auth for rstudio 
echo "GIT_SSH_COMMAND='$GIT_SSH_COMMAND'" | sudo tee -a /usr/lib/R/etc/Renviron.site
echo "GIT_ASKPASS=$GIT_ASKPASS" | sudo tee -a /usr/lib/R/etc/Renviron.site
echo "CODER_AGENT_URL=$CODER_AGENT_URL" | sudo tee -a /usr/lib/R/etc/Renviron.site
echo "CODER_AGENT_AUTH=token" | sudo tee -a /usr/lib/R/etc/Renviron.site
echo "CODER_AGENT_TOKEN=$CODER_AGENT_TOKEN" | sudo tee -a /usr/lib/R/etc/Renviron.site

EOT
}

# code-server
resource "coder_app" "code-server" {
  agent_id      = coder_agent.coder.id
  slug          = "code-server"  
  display_name  = "code-server"
  icon          = "/icon/code.svg"
  url           = "http://localhost:13337?folder=/home/coder"
  subdomain = false
  share     = "${data.coder_parameter.appshare.value}"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  } 
}

# rstudio
resource "coder_app" "rstudio" {
  agent_id      = coder_agent.coder.id
  slug          = "rstudio"  
  display_name  = "RStudio"
  icon          = "/icon/rstudio.svg"
  url           = "http://localhost:8788/@${data.coder_workspace.me.owner}/${lower(data.coder_workspace.me.name)}.coder/apps/rstudio/"
  subdomain = false
  share     = "${data.coder_parameter.appshare.value}"

  healthcheck {
    url       = "http://localhost:8788/healthz"
    interval  = 3
    threshold = 10
  } 
}

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
    namespace = var.workspaces_namespace
  }
  spec {
    security_context {
      run_as_user = "1000"
      fs_group    = "1000"
    }     
    container {
      name    = "rstudio"
      image   = local.image
      command = ["sh", "-c", coder_agent.coder.init_script]
      image_pull_policy = "Always"
      security_context {
        run_as_user = "1000"
      }
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.coder.token
      }
      resources {
        requests = {
          cpu    = local.cpu-request
          memory = local.memory-request
        }        
        limits = {
          cpu    = local.cpu-limit
          memory = local.memory-limit
        }
      }                       
      volume_mount {
        mount_path = "/home/coder"
        name       = "home-directory"
      }        
    }
    volume {
      name = "home-directory"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home-directory.metadata.0.name
      }
    }         
  }
}

resource "kubernetes_persistent_volume_claim" "home-directory" {
  metadata {
    name      = "home-coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
    namespace = var.workspaces_namespace
  }
  wait_until_bound = false   
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${local.home-volume}"
      }
    }
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_pod.main[0].id
  item {
    key   = "image"
    value = "${kubernetes_pod.main[0].spec[0].container[0].image}"
  }  
}

