# Container Migration - Docker vs Podman

**About**

This project investigates the live migration of containers between two servers using CRIU with Docker and Podman. The primary objective is to compare and contrast the performance of these two containerization technologies in terms of downtime, resource utilization, and ease of setup during live migration.

**Prerequisites**

* **Hardware:**
    * 2 servers (Host & Target): 4 CPUs, 4GB RAM, 20GB free disk space, Ubuntu 22.04.1 
* **Software:**
    * Vagrant.
    * Docker Engine or Podman.
    * CRIU.
    * Shared Storage (e.g., NFS, SCP).

**Installation**

1. **Install Docker or Podman:**
    * **Docker:**
        * https://docs.docker.com/engine/install/
    * **Podman:**
        * https://podman.io/docs/installation

2. **Install criu:**
    * https://criu.org/Installation

**Project Setup**

1. Clone this repository ```git clone https://github.com/v3locide/Migration-Docker-vs-Podman.git```
2. Deploy the Host and Target VMs using the provided Vagrant files (or you can create your VMs manually).
```bash
cd Host
vagrant up
cd ../Target/
vagrant up
```
4. **After deploying both servers and installing the required tools in each of them**, clone this repository again in both servers (Host + Target) ```git clone https://github.com/v3locide/Migration-Docker-vs-Podman.git``` (alternatively, you can make the repository as a shared directory between both VMs from your local machine). 
5. make sure the script files in ```./Host/``` and ```./Target/``` are executable in both servers.
```bash
# Host server:
cd Host
chmod +x docker_host_stats.sh # Host migration script with docker.
chmod +x podman_host_stats.sh # Host migration script with podman.

# Target server:
chmod +x docker_target_stats.sh # Target migration script with docker.
chmod +x podman_target_stats.sh # Target migration script with podman.
```
6. Run the scripts for migration:
  * Docker:
```bash
# Host server:
cd Host
./docker_host_stats.sh

# Target server:
cd Target
./docker_target_stats.sh
```
* Podman:
```bash
# Host server:
cd Host
./podman_host_stats.sh

# Target server:
cd Target
./podman_target_stats.sh
```

**Limitations**

* **Root permissions and CRIU dependency:** Requires root privileges for checkpointing and restoring containers. 
* **Kernel/OS and CRIU compatibility:** Compatibility issues may arise between the kernel version, operating system, and CRIU version.
* **Limited support for stateful applications:** May not be suitable for all stateful applications, especially those with complex state management.
* **No support for volumes and external storage:** Challenges in handling persistent data stored in volumes or external storage during migration.
* **Complex network configurations:** Migrating containers with complex network configurations can be challenging and may require additional steps.

**Demo**
   * I made a demo video so you can see how the live container migration  of a simple web application works with Docker and Podman: https://youtu.be/4bwLuNuX3Cg
