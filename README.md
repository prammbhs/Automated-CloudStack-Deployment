# 🛠️ Automated CloudStack 4.20 Installer with KVM on Ubuntu 20.04

This project contains a **Bash automation script** that fully sets up an Apache CloudStack 4.20 environment with a KVM hypervisor on a single Ubuntu 20.04 machine. It configures the management server, MySQL, system VM templates, NFS storage, and agent setup—all in one go.

---

## 📦 Features

* 📡 Automatic detection and configuration of static IP and gateway
* 🔧 Full system setup with state tracking and idempotent execution
* ☁️ CloudStack management server + MySQL with secure defaults
* 🧠 Preloads official System VM templates
* 🛧️ Configures NFS primary & secondary storage
* 🧱 Sets up KVM agent with DNS and libvirt configuration
* 💻 Optional high-resolution display settings for GUI systems
* 🧺 Includes a built-in System VM troubleshooting tool
* ✨ Restart-safe: Run again after failure or `--reset` to start fresh
* 🔐 Generates a credentials file for safe reference post-setup

---

## 📁 Project Structure

| File                          | Description                                           |
| ----------------------------- | ----------------------------------------------------- |
| `cloudstack_setup.sh`         | Main installer script (rename from `scriptforvm.txt`) |
| `cloudstackagentconfigfix.sh` | Fixes agent's host IP in `agent.properties`           |
| `credentials.env`             | Auto-generated file storing credentials used          |

---

## ⚙️ Prerequisites

* Ubuntu 20.04 server (fresh or minimal install recommended)
* Static IP setup with working bridge interface
* At least 4 vCPUs and 8GB RAM (recommended)
* Root privileges (`sudo`)

---

## 🚀 Usage

1. Clone the repository:

   ```bash
   git clone https://github.com/yourusername/cloudstack-kvm-installer.git
   cd cloudstack-kvm-installer
   ```

2. Run the script:

   ```bash
   sudo bash cloudstack_setup.sh
   ```

3. To reset and rerun:

   ```bash
   sudo bash cloudstack_setup.sh --reset
   ```

4. After install:

   * CloudStack UI: `http://<your-ip>:8080/client`
   * Username: `admin`
   * Password: `password`

5. Credentials file generated at:

   ```
   ./credentials.env
   ```

---

## 🥪 Agent Configuration Fix (Optional)

If agent connection fails due to incorrect host IP:

```bash
sudo bash cloudstackagentconfigfix.sh
```

This will update `agent.properties` with the management server IP.

---

## 🧰 Troubleshooting

A diagnostic script is generated at `/root/systemvm_troubleshoot.sh`:

```bash
sudo bash /root/systemvm_troubleshoot.sh
```

It checks logs, libvirt VMs, system VM states, and common connectivity issues.

---

## 👤 Author

**Paramjit Patel**
🔗 [Portfolio](https://your-portfolio-link.com)
📧 Feel free to reach out via GitHub or LinkedIn.

---

## 📜 License

This project is licensed under the MIT License.
