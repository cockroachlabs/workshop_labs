# Optimizing Serializable Transactions - Instructor Notes

## Build the environment

Use Ansible playbook to create an adequately provisioned cluster, and a Jumpbox/HAProxy server on AWS.

Make sure the CockroachDB binary is also installed on the Jumpbox server as you will need access to the SQL client.

For example, AWS region `us-east-1`, 3x M5.2xlarge across 3 different AZs, plus another M5.2xlarge for the jumpbox/haproxy server.

TODO: create admin user cockroach/cockroach or use insecure cluster

## Install pgworkload, Prometheus and Grafana on the Jumpbox server

```bash
# install pgworkload
sudo apt install -y python3-pip
pip install --upgrade pip
export PATH=/home/ubuntu/.local/bin:$PATH
echo 'export PATH=/home/ubuntu/.local/bin:$PATH' >> .bashrc
pip install pgworkload

# add Grafana and Prom repos and install components
sudo apt install -y apt-transport-https
sudo apt install -y software-properties-common wget
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install -y prometheus grafana
```

Edit file `/etc/prometheus/prometheus.yml` by adding the below `job_name` for pgworkload

```yaml
scrape_configs:
  - job_name: pgworkload
    static_configs:
    - targets:
      - 'localhost:26260'
```

Restart all services

```bash
sudo systemctl restart prometheus
sudo systemctl restart grafana-server
```

You can now open 2 tabs in your browser with the IP address of the jumpbox server at ports 9090 (Prometheus) and 3000 (Grafana).

## Create SQL user

Open sql terminal in one of the nodes

```bash
sudo cockroach sql --url='postgres://root@localhost:26257/postgres?sslcert=/var/lib/cockroach/certs/client.root.crt&sslkey=/var/lib/cockroach/certs/client.root.key&sslmode=verify-full&sslrootcert=/var/lib/cockroach/certs/ca.crt'
```

At the SQL prompt

```sql
CREATE USER cockroach WITH password cockroach;
GRANT admin TO cockroach;
```

## Capturing metrics using Prometheus + Grafana

Confirm Prometheus can successfully connect to the CockroachDB cluster and to the AlertManager service

![prom-targets](media/prom-targets.png)

Confirm Prometheus can scrape the metrics from the CockroachDB cluster by pulling any of the metrics

![prom](media/prom.png)

Configure Grafana to read from Prometheus:

1. Login into Grafana with admin/admin
2. Configuration > Data Sources > Prometheus
3. use <http://localhost:9090> as the server address
4. Save & Test

You should get a confirmation that the connection is successful.

Download the Grafana dashboard JSON files from our [repo](https://github.com/cockroachdb/cockroach/tree/master/monitoring/grafana-dashboards):

```bash

```

In Grafana, upload them all by clicking on '+' > Import, then confirm you can pull the metrics correctly.

## Clean up

```bash
roachprod destroy ${USER}-demo
roachprod destroy ${USER}-jump
```
