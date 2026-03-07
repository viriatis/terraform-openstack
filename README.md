# Ansible Playbooks

## Description

This repository contains an exercise using Sunbeam Openstack on Ubuntu Desktop 24.04 freshly created and using terraform to create an instance of nginx.

## Getting Started

### Dependencies

* Terraform 1.14.3 or higher
* Tested on Ubuntu 24.04

### Install Sunbeam Openstack

Install Sunbeam Openstack in another machine, VM or computer with Ubuntu ([Installation Guide](<./docs/0. Dependencies.md>))


It is recomended the following requirements:

* 4+ core amd64 processor
* minimum of 16 GiB of RAM
* minimum of 100 GiB SSD storage on the rootfs partition
* fresh Ubuntu Desktop 24.04 LTS installed
* unlimited access to the Internet
* spare un-formatted disk for MicroCeph

    
## Terraform projects

### Deploy nginx app

Terraform project: [deploy nginx app](<./deploy-nginx/README.md>)

### Executing program

* Run the terraform project using the following commands:

```bash
# Init
make init
# Plan (without changes)
make plan
# Apply
make apply
```

## Authors

- [Hernâni Gil](mailto:hernanigil1987@gmail.com)


## License

This project is licensed under the [MIT] License - see the [LICENSE.md](./LICENSE) file for details