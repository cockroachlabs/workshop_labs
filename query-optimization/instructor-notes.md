# Instructor Notes

## Build the environment

Use Ansible playbook to create an adequately provisioned cluster, and a Jumpbox/HAProxy server on AWS with Instance Profile Role `workshop`.

The `workshop` role allows the CockroacDB VMs to access the S3 bucket without using AWS keys.

Make sure the CockroachDB binary is also installed on the Jumpbox server as you will need access to the SQL client.

## Example

AWS region `us-east-1`, 3x M5.2xlarge across 3 different AZs, plus another M5.2xlarge for the jumpbox/haproxy server.
