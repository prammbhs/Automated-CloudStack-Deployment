# 🛠️ Automated CloudStack 4.20 Installer with KVM on Ubuntu 20.04

This project provides a professional Bash automation script to set up Apache CloudStack 4.20 with KVM on a single Ubuntu 20.04 machine. It handles system setup, MySQL configuration, NFS storage, CloudStack installation, and agent connectivity — all in one go.

---

## 📦 Features

- 📡 Auto-detects static IP and gateway
- 🔧 Full system setup with state tracking
- ☁️ CloudStack management server + MySQL setup
- 🧠 Loads official System VM templates
- 🛧️ Configures NFS primary & secondary storage
- 🧱 Installs and configures KVM agent with libvirt
- 💻 Optional GUI display settings for high-res setups
- 🧺 Generates a troubleshooting tool for System VMs
- 🔁 Safe to rerun — idempotent with resume support
- 🔐 Prompts for and stores credentials in a safe `.env` file

---

## 📁 Project Structure

| File                         | Description                                      |
|------------------------------|--------------------------------------------------|
| `cloudstack_setup.sh`        | Main installer script                           |
| `cloudstackagentconfigfix.sh`| Fix for CloudStack agent IP setting             |
| `credentials.env`            | Auto-generated, stores sensitive credentials    |
| `.gitignore`                 | Git exclusion rules for safety and cleanliness  |

---

## ⚙️ Prerequisites

- Ubuntu 20.04 LTS (fresh install recommended)
- Static IP with bridge interface (e.g. ens33)
- At least 4 vCPUs and 8GB RAM
- Root or sudo privileges
- Internet access

---

## 🚀 Usage

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/cloudstack-kvm-installer.git
   cd cloudstack-kvm-installer
   ```

2. Run the setup script:
   ```bash
   sudo bash cloudstack_setup.sh
   ```

   - 📝 You will be prompted to enter:
     - MySQL root password (default: `Root@123`)
     - CloudStack DB user password (default: `cloud`)
   - These values will be saved securely in `credentials.env` for reuse.

3. To resume after a failure:
   ```bash
   sudo bash cloudstack_setup.sh
   ```

4. To reset and rerun everything:
   ```bash
   sudo bash cloudstack_setup.sh --reset
   ```

5. After installation:
   - Access CloudStack UI: `http://<your-ip>:8080/client`
   - Username: `admin`
   - Password: `password`

6. Credentials file:
   ```
   ./credentials.env
   ```

   ⚠️ This contains plaintext passwords. Do not commit this file.

---

## 🧩 Optional Fix

If the agent doesn’t connect to the management server:

```bash
sudo bash cloudstackagentconfigfix.sh
```

---

## 🧰 Troubleshooting

A diagnostic script is generated at:

```
/root/systemvm_troubleshoot.sh
```

To run it:

```bash
sudo bash /root/systemvm_troubleshoot.sh
```

---

## 👤 Author

**Paramjit Patel**  
🔗 [Portfolio](https://paramjitpatel.me)  
📧 Reach out via GitHub or LinkedIn

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).
