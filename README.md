# linux-shell-portfolio
Showcase of my Linux and shell scripting skills
# 🐧 Linux Commands & Shell Scripting Portfolio

![Shell](https://img.shields.io/badge/Shell-Bash-green?logo=gnu-bash)
![Linux](https://img.shields.io/badge/OS-Linux-yellow?logo=linux)
![License](https://img.shields.io/badge/License-MIT-blue)
![CI](https://github.com/yourusername/linux-shell-portfolio/actions/workflows/ci.yml/badge.svg)
![Scripts](https://img.shields.io/badge/Scripts-10%2B-orange)

> A production-ready showcase of Linux administration, shell scripting,
> automation, and DevOps skills built with Bash best practices.

## 📋 Table of Contents
- [Overview](#overview)
- [Skills Demonstrated](#skills-demonstrated)
- [Scripts](#scripts)
- [Quick Start](#quick-start)
- [Usage Examples](#usage-examples)
- [Testing](#testing)
- [Contributing](#contributing)

## 🎯 Overview

This repository demonstrates proficiency in:
- **Linux System Administration**
- **Shell Scripting (Bash)**
- **Process & Resource Management**
- **Network Monitoring & Analysis**
- **Automation & Task Scheduling**
- **Log Analysis & Parsing**
- **File System Operations**

## 🛠️ Skills Demonstrated

| Category | Tools & Commands |
|---|---|
| System Admin | `top`, `htop`, `ps`, `df`, `du`, `free`, `uptime` |
| File Operations | `find`, `grep`, `awk`, `sed`, `sort`, `uniq`, `cut` |
| Networking | `netstat`, `ss`, `ping`, `curl`, `wget`, `nmap` |
| Process Mgmt | `kill`, `pkill`, `jobs`, `nohup`, `systemctl` |
| Text Processing | `awk`, `sed`, `grep`, `tr`, `wc`, `head`, `tail` |
| Automation | `cron`, `at`, `bash`, `functions`, `arrays` |

## 📁 Scripts

### System Administration
| Script | Description |
|---|---|
| `system_health_check.sh` | Full system health report with CPU, RAM, disk |
| `user_management.sh` | Create, delete, audit users with logging |
| `disk_monitor.sh` | Monitor disk usage with configurable thresholds |

### Automation
| Script | Description |
|---|---|
| `backup_manager.sh` | Automated backup with compression & rotation |
| `log_analyzer.sh` | Parse and analyze log files with reporting |
| `deployment_helper.sh` | Zero-downtime deployment automation |

### Networking
| Script | Description |
|---|---|
| `network_scanner.sh` | Scan network hosts and open ports |
| `port_monitor.sh` | Monitor critical ports with alerting |

### Utilities
| Script | Description |
|---|---|
| `file_organizer.sh` | Auto-organize files by type/date |
| `text_processor.sh` | Advanced text manipulation toolkit |

## 🚀 Quick Start

\`\`\`bash
# Clone the repository
git clone https://github.com/yourusername/linux-shell-portfolio.git
cd linux-shell-portfolio

# Make all scripts executable
make setup

# Run system health check
./scripts/system-admin/system_health_check.sh

# Run all tests
make test
\`\`\`

## 📖 Usage Examples

\`\`\`bash
# System health check with email report
./scripts/system-admin/system_health_check.sh --report --email admin@example.com

# Backup with custom retention
./scripts/automation/backup_manager.sh --source /var/www --dest /backup --retain 7

# Analyze Apache logs for top IPs
./scripts/automation/log_analyzer.sh --file /var/log/apache2/access.log --top 10

# Scan local network
./scripts/networking/network_scanner.sh --range 192.168.1.0/24

# Organize files by type
./scripts/utilities/file_organizer.sh --source ~/Downloads --dest ~/Organized
\`\`\`

## 🧪 Testing

\`\`\`bash
make test          # Run all tests
make lint          # Run shellcheck linting
make validate      # Validate script syntax
\`\`\`

## 📄 License
MIT License — see [LICENSE](LICENSE) for details.
