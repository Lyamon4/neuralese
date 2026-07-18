# Systemd deployment

This is the Linux server install path for a school IT room machine.

## Install

```bash
sudo useradd --system --home /opt/neuralese-onprem --shell /usr/sbin/nologin neuralese
sudo mkdir -p /opt/neuralese-onprem /etc/neuralese /var/lib/neuralese-onprem/jobs /var/lib/neuralese-onprem/datasets
sudo cp -R code-snapshot/* /opt/neuralese-onprem/
sudo cp onprem_runtime/deployment/systemd/neuralese-onprem.env.example /etc/neuralese/onprem.env
sudo cp onprem_runtime/deployment/systemd/neuralese-onprem.service /etc/systemd/system/neuralese-onprem.service
sudo chown -R neuralese:neuralese /opt/neuralese-onprem /var/lib/neuralese-onprem
```

Edit `/etc/neuralese/onprem.env` and set `NEURALESE_AUTH_TOKEN` before exposing the service on a school network.

```bash
cd /opt/neuralese-onprem
sudo -u neuralese python3.11 -m venv .venv
sudo -u neuralese .venv/bin/python -m pip install --upgrade pip
sudo -u neuralese .venv/bin/pip install -r onprem_runtime/requirements-runtime.txt
sudo systemctl daemon-reload
sudo systemctl enable --now neuralese-onprem
```

## Operate

```bash
systemctl status neuralese-onprem
journalctl -u neuralese-onprem -f
sudo systemctl restart neuralese-onprem
```

The runtime dashboard is available on `http://SERVER_IP:8010/`.
