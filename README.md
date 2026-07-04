# cloud-ai-iac

Infrastructure as Code for deploying a private, high-performance AI inference server on Google Cloud Platform (GCP).

## 🚀 Overview

This project provides an OpenTofu configuration to quickly spin up a GPU-accelerated VM on GCP, pre-configured to run the Gemma-4 model using `llama.cpp`. It automates the entire setup from network configuration to model deployment, providing a turnkey solution for private AI inference.

### Key Specifications

| Component | Specification |
| :--- | :--- |
| **Model** | [gemma-4-31B-it-Q8_0.gguf](https://huggingface.co/unsloth/gemma-4-31B-it-GGUF) |
| **Hardware** | NVIDIA RTX PRO 6000 (96GB vRAM) |
| **Infrastructure** | G4 Spot Instance (`g4-standard-48`) |
| **Region** | `europe-west4` (Netherlands) |
| **Backend** | `llama.cpp` server with continuous batching and CUDA acceleration |

## ✨ Features

- **Automated Setup**: A comprehensive startup script handles CUDA dependency installation, `llama.cpp` compilation for Blackwell architecture, and model weight acquisition.
- **Optimized Performance**: Specifically tuned for high-concurrency usage with 4 agent slots and a large KV cache (~53GB) to fully utilize the 96GB vRAM.
- **Cost Efficiency**: Leveraging GCP Spot instances to minimize operational costs.
- **Network Isolation**: Custom VPC and strict firewall rules ensure that only authorized IP ranges can access the SSH and API endpoints.

## 🛠️ Prerequisites

Before deploying, ensure you have the following:

- [OpenTofu](https://opentofu.org/) installed.
- A GCP project with the **Compute Engine API** enabled.
- Authenticated GCP credentials:
  ```bash
  gcloud auth application-default login
  ```
- Quota for `NVIDIA_RTX_PRO_6000` GPUs in the `europe-west4` region.

## 📖 Usage

### 1. Configuration

Update your local IP address to allow SSH and API access. Edit `gcp-root-module/terraform.tfvars.json`:

```json
{
  "local_ipv4": "your.public.ip.address/32"
}
```

### 2. Deployment

Navigate to the GCP module directory and apply the configuration:

```bash
cd gcp-root-module
tofu init
tofu plan
tofu apply
```
*Note: After `tofu apply` completes, the external IP of the instance will be available in the output.*

### 3. Accessing the AI Server

Once the instance is running and the startup script finishes (this may take several minutes for compilation and download), the API will be available at:

`http://<INSTANCE_EXTERNAL_IP>:8080`

#### Integration with opencode
To use this private endpoint within [opencode](https://opencode.ai), update your `~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "private_gcp": {
      "name": "Private Gemma 4",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://<INSTANCE_EXTERNAL_IP>:8080/v1"
      },
      "models": {
        "/opt/ai/gemma-4-31B-it-Q8_0.gguf": {
          "name": "Gemma 4 32B"
        }
      }
    }
  },
  "disabled_providers": []
}
```

### 4. Cleanup

To avoid ongoing costs, destroy the infrastructure when finished:

```bash
tofu destroy
```

## 🛡️ Security & Production Readiness

- **Warning (PoC)**: This setup currently uses **HTTP** for simplicity. For production environments, it is strongly recommended to implement an HTTPS proxy (e.g., Nginx with Let's Encrypt) or use a GCP Load Balancer with SSL termination.
- **Firewall**: Access is restricted to the `local_ipv4` provided in the configuration and internal GCP health check ranges.
- **Spot Instances**: Be aware that Spot instances can be preempted by GCP at any time. For critical workloads, consider using standard instances.

## ⚙️ Technical Details

### Startup Process
The VM initializes by:
1. Installing `build-essential`, `cmake`, `git`, and `aria2`.
2. Downloading the Gemma-4 GGUF weights to `/opt/ai/`.
3. Compiling `llama.cpp` specifically for **Blackwell Architecture (SM100/SM120)** to ensure maximum GPU efficiency.
4. Setting up a `systemd` service (`llama.service`) to ensure the server starts automatically and restarts on failure.

### Performance Tuning
The server is launched with the following optimized flags:
- `-ngl 99`: Offloads all layers to the GPU.
- `-fa on`: Enables Flash Attention.
- `-cb`: Enables Continuous Batching.
- `-np 4`: Supports 4 concurrent request slots.
- `-c 393216`: Allocates a large context window for the KV cache.

## 📁 Project Structure

- `gcp-root-module/`: OpenTofu configuration for GCP deployment.
  - `main.tofu`: Primary resource definitions (VPC, VM, Firewall).
  - `variables.tofu`: Variable definitions.
  - `terraform.tfvars.json`: User-specific configuration.

## 📜 License

This project is licensed under the [Apache License 2.0](LICENSE).
