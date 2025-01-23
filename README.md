# Container Migration - Docker vs Podman

**About**

This project investigates the live migration of containers between two servers using CRIU with Docker and Podman. The primary objective is to compare and contrast the performance of these two containerization technologies in terms of downtime, resource utilization, and ease of setup during live migration.

**Prerequisites**

* **Hardware:**
    * 2 machines (Host & Target): 4 CPUs, 4GB RAM, 20GB free disk space, Ubuntu 22.04.1 
* **Software:**
    * Docker Engine or Podman
    * CRIU
    * Node.js and npm 
    * Shared Storage (e.g., NFS, SCP) 

**Installation**

1. **Install Docker or Podman:**
    * **Docker:**
        * https://docs.docker.com/engine/install/
    * **Podman:**
        * https://podman.io/docs/installation

2. **Install criu:**
    * https://criu.org/Installation

**Limitations**

* **Root permissions and CRIU dependency:** Requires root privileges for checkpointing and restoring containers. 
* **Kernel/OS and CRIU compatibility:** Compatibility issues may arise between the kernel version, operating system, and CRIU version.
* **Limited support for stateful applications:** May not be suitable for all stateful applications, especially those with complex state management.
* **No support for volumes and external storage:** Challenges in handling persistent data stored in volumes or external storage during migration.
* **Complex network configurations:** Migrating containers with complex network configurations can be challenging and may require additional steps.

**Demo**
