# Custom VPC Network
resource "google_compute_network" "dev_team_vpc" {
  name                    = "dev-team-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Dedicated Subnet for the Netherlands Region
resource "google_compute_subnetwork" "dev_team_subnet" {
  name          = "dev-team-subnet-euw4"
  ip_cidr_range = "10.10.0.0/24"
  network       = google_compute_network.dev_team_vpc.id
}

# Firewall Rules for Inference APIs and SSH
resource "google_compute_firewall" "dev_team_allow_inbound" {
  name    = "dev-team-allow-inbound"
  network = google_compute_network.dev_team_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22", "8000", "8080"] # SSH and standard vLLM/Ollama API ports
  }

  source_ranges = [var.local_ipv4, "35.235.240.0/20"] # "35.235.240.0/20" being an internal gcp one. 
}

# Dynamically fetch the latest image from the Deep Learning family
data "google_compute_image" "deeplearning_image" {
  family  = "common-cu129-ubuntu-2404-nvidia-580"
  project = "deeplearning-platform-release"
}


# G4 Spot Instance (Full RTX Pro 6000)
resource "google_compute_instance" "g4_llama_dev_team" {
  name         = "dev-team-llama-node"
  machine_type = "g4-standard-48"

  boot_disk {
    initialize_params {
      # Deep Learning VM for immediate CUDA support
      image = data.google_compute_image.deeplearning_image.self_link
      size  = 200 # Upgraded to 200GB to ensure space for 70B+ model weights
      type  = "hyperdisk-balanced"
    }
  }

  network_interface {
    # Attach to the custom subnet instead of default
    subnetwork = google_compute_subnetwork.dev_team_subnet.id

    access_config {
      # Allocates an ephemeral public IP for direct API access
    }
  }

  # Spot Market Configuration
  scheduling {
    preemptible                 = true
    provisioning_model          = "SPOT"
    instance_termination_action = "STOP"
    on_host_maintenance         = "TERMINATE"
    automatic_restart           = false
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e
    
    if [ ! -d "/opt/ai/llama.cpp" ]; then
      echo "First boot detected: Installing dependencies and downloading model..."
      apt-get update
      apt-get install -y build-essential cmake git aria2

      mkdir -p /opt/ai
      cd /opt/ai

      aria2c -x 16 -s 16 https://huggingface.co/unsloth/gemma-4-31B-it-GGUF/resolve/main/gemma-4-31B-it-Q8_0.gguf -o gemma-4-31B-it-Q8_0.gguf

      git clone https://github.com/ggerganov/llama.cpp.git
      cd llama.cpp
      mkdir build && cd build

      # Compile for Blackwell Architecture (SM100 / SM120)
      cmake .. \
        -DGGML_CUDA=ON \
        -DGGML_CUDA_F16=ON \
        -DGGML_CUDA_FA_ALL_QUANTS=ON \
        -DCMAKE_CUDA_ARCHITECTURES="100;120" \
        -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc

      cmake --build . --config Release -j $(nproc)
    else
      echo "Subsequent boot detected: Skipping download and compilation."
    fi

    cat << 'SVC' > /etc/systemd/system/llama.service
    [Unit]
    Description=llama.cpp server
    After=network.target

    [Service]
    Type=simple
    WorkingDirectory=/opt/ai/llama.cpp/build/bin
    
    # 4-Agent Dev Team Config for 96GB VRAM:
    # -cb (Continuous Batching)
    # -np 4 (4 concurrent agent slots)
    # -c 393216 (Allocates ~53GB for KV Cache, leaving 10GB for compute overhead)
    ExecStart=/opt/ai/llama.cpp/build/bin/llama-server -m /opt/ai/gemma-4-31B-it-Q8_0.gguf --host 0.0.0.0 --port 8080 -ngl 99 -fa on -cb -np 4 -c 393216
    Restart=always
    User=root

    [Install]
    WantedBy=multi-user.target
    SVC

    systemctl daemon-reload
    systemctl enable llama.service
    systemctl restart llama.service
  EOF

  # Hardware mapping for 1 full GPU
  guest_accelerator {
    type  = "nvidia-rtx-pro-6000"
    count = 1
  }

  service_account {
    # Grants permissions to pull data from GCP services like Cloud Storage
    scopes = ["cloud-platform"]
  }
}
