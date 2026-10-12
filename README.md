# High-availability-PostgreSQL-Cluster-AWS



![Status](https://shields.io)
![Infrastructure](https://shields.io)
![Automation](https://shields.io)

This repository contains a complete configuration for deploying a production-grade, production-ready **High-Availability (HA) PostgreSQL Cluster** alongside its full **AWS Infrastructure**.

## 🚀 Project Overview

The architecture is built from the ground up to ensure zero single points of failure, leveraging cloud infrastructure automation and robust configuration management.

*   **Complete AWS Infrastructure:** Provisioned via **Terraform**, establishing secure VPC routing, subnets, security groups, and EC2 compute instances.
*   **High-Availability Layer:** Orchestrated using **Patroni** and **etcd** for distributed consensus, automated leader election, and seamless failover handling.
*   **Load Balancing:** Managed via **HAProxy** to distribute traffic and route database queries intelligently to the active leader or read-replicas.
*   **Automation:** Handled entirely by **Ansible** for predictable, repeatable software installations and cluster configuration.

---

## 🚧 Documentation & Features: In Progress

> [!NOTE]
> Detailed deployment guides, architectural diagrams, step-by-step setup guides, and advanced feature additions are currently **in progress**. 

This version represents the core functional codebase for the architecture. Expanded documentation and configuration templates are being actively committed. 

**Stay tuned!** ✨
