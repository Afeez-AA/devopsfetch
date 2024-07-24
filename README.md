# DevOpsFetch

DevOpsFetch is a tool designed for server information retrieval and monitoring. 

It provides detailed information about active users, open ports, Nginx configurations, Docker images, and container statuses, and logs activities continuously.

## Features

- Display detailed user information
- List active ports
- Show Nginx configurations
- Display Docker images and container statuses
- Continuous monitoring and logging

## Prerequisites

- Bash
- Docker (optional for Docker features)
- Nginx (optional for Nginx features)

## Installation

### Clone the Repository

To get started, clone the repository to your local machine:

```bash
git clone https://github.com/Afeez-AA/devopsfetch.git
cd devopsfetch
```

### Make Scripts Executable
Make the main script and installation script executable:
```bash
    chmod +x devopsfetch.sh
    chmod +x install.sh
```

### Run the Installation Script
```bash
    sudo ./install.sh
```

### Verify Installation
After running the installation script, verify the installation and functionality of the tool.
```bash
    devopsfecth -p
    devopsfecth -d
    devopsfecth -u
    devopsfecth -t
```

### Logging
Logs are stored in /var/log/devopsfetch/. 

The logs include detailed information about user activities, open ports, Nginx configurations, Docker statuses, and other relevant server information.

For detailed documentation, please click here
