# Backup and Restorre - Student Labs

In these labs we will familiarize with the Backup & Restore functionality in CockroachDB. We also include a lab to practice Repaving.

## Overview

CockroachDB is by design fault tolerant and resilient, so Backup is only required for DR. Still, it is good practice to backup your entire database on at least a weekly basis with hourly/daily incremental backups.

You can read this excellent [blog post](https://www.cockroachlabs.com/blog/distributed-database-performance/) about how to architecture CockroachDB and the importance of Backups, but also how CockroachDB naturally brings RPO to zero.

## Labs Prerequisites

1. Build the dev cluster following [these instructions](/infrastructure/multi-region-local-docker-cluster.md).

2. You also need:

    - a modern web browser,
    - a SQL client:
      - [Cockroach SQL client](https://www.cockroachlabs.com/docs/stable/install-cockroachdb-linux)
      - `psql`
      - [DBeaver Community edition](https://dbeaver.io/download/) (SQL tool with built-in CockroachDB plugin)

## Lab 0 - Create S3 Compatible service and sample database

We will use a S3 compatible service to store our backup files. For this workshop, we will use [Adobe S3Mock](https://github.com/adobe/S3Mock).

Start a container and attach it to the 3 regional networks so that every cluster node can reach it.

```bash
# start s3mock. A bucket called 'backup' is automatically created
docker run --name s3mock -p 9090:9090 -p 9191:9191 -t --hostname s3mock -d -e initialBuckets=backup adobe/s3mock

# attach networks
docker network connect us-west2-net s3mock
docker network connect us-east4-net s3mock
docker network connect eu-west2-net s3mock
```

Now that the infrastructure is in place, let's create a database and load some data. Connect to cluster node `roach-newyork-1`

```bash
docker exec -it roach-newyork-1 bash
```

In the container, generate a sample database with data. Please note, this will take few minutes to complete. While it works, you can read about the `workload` function and the `movr` database in [here](https://www.cockroachlabs.com/docs/stable/cockroach-workload.html).

```bash
cockroach workload init movr
```

Once done, connect to the database

```bash
cockroach sql --insecure
```

Check the data was created correctly

```sql
SELECT * FROM movr.rides LIMIT 5;
```

```text
                   id                  |   city    | vehicle_city |               rider_id               |              vehicle_id              |         start_address          |           end_address           |        start_time         |         end_time          | revenue
---------------------------------------+-----------+--------------+--------------------------------------+--------------------------------------+--------------------------------+---------------------------------+---------------------------+---------------------------+----------
  ab020c49-ba5e-4800-8000-00000000014e | amsterdam | amsterdam    | c28f5c28-f5c2-4000-8000-000000000026 | aaaaaaaa-aaaa-4800-8000-00000000000a | 1905 Christopher Locks Apt. 77 | 66037 Belinda Plaza Apt. 93     | 2018-12-13 03:04:05+00:00 | 2018-12-14 08:04:05+00:00 |   77.00
  ab851eb8-51eb-4800-8000-00000000014f | amsterdam | amsterdam    | b851eb85-1eb8-4000-8000-000000000024 | aaaaaaaa-aaaa-4800-8000-00000000000a | 70458 Mary Crest               | 33862 Charles Junctions Apt. 49 | 2018-12-26 03:04:05+00:00 | 2018-12-28 10:04:05+00:00 |   81.00
  ac083126-e978-4800-8000-000000000150 | amsterdam | amsterdam    | c28f5c28-f5c2-4000-8000-000000000026 | aaaaaaaa-aaaa-4800-8000-00000000000a | 50217 Victoria Fields Apt. 44  | 56217 Wilson Spring             | 2018-12-07 03:04:05+00:00 | 2018-12-07 10:04:05+00:00 |    9.00
  ac8b4395-8106-4800-8000-000000000151 | amsterdam | amsterdam    | ae147ae1-47ae-4800-8000-000000000022 | bbbbbbbb-bbbb-4800-8000-00000000000b | 34704 Stewart Ports Suite 56   | 53889 Frank Lake Apt. 49        | 2018-12-22 03:04:05+00:00 | 2018-12-22 16:04:05+00:00 |   27.00
  ad0e5604-1893-4800-8000-000000000152 | amsterdam | amsterdam    | ae147ae1-47ae-4800-8000-000000000022 | aaaaaaaa-aaaa-4800-8000-00000000000a | 10806 Kevin Spur               | 15744 Valerie Squares           | 2018-12-08 03:04:
```

You can also check the **Databases** page in the AdminUI at <http://localhost:8080> for an overview of your databases and their size.

![adminui-databases](media/adminui-databases.png)

Good job, we are now ready to perform our first backup job.

## Lab 1 - Full Cluster Backup

Backup the entire cluster to S3. Please note: we must include the "KEYS" parameter even though none are required for S3Mock.

```sql
BACKUP TO 's3://backup/2020-01?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key'
  AS OF SYSTEM TIME '-10s';
```

Check the Job progress in the Admin UI

![adminui-jobs](media/adminui-jobs.png)

Alternatively, you can also list the JOBS using SQL

```sql
-- create handy view
CREATE VIEW jobsview AS
SELECT
    job_id,
    job_type,
    substring(description, 0, 60) AS short_description,
    status,
    created,
    finished - started AS duration,
    fraction_completed AS pct_done,
    error
FROM [SHOW JOBS]
WHERE job_type != 'SCHEMA CHANGE GC';

-- query last 5 jobs
SELECT * FROM jobsview ORDER BY created DESC LIMIT 5;
```

```text
        job_id       |   job_type    |                      short_description                      |  status   |             created              |    duration     | pct_done | error
---------------------+---------------+-------------------------------------------------------------+-----------+----------------------------------+-----------------+----------+--------
  597906048349470721 | BACKUP        | BACKUP TO 's3://backup/2020-01?AWS_ACCESS_KEY_ID=id&AWS_END | succeeded | 2020-10-12 21:07:25.419137+00:00 | 00:00:31.57873  |        1 |
  597905751889248257 | SCHEMA CHANGE | ALTER TABLE movr.public.user_promo_codes ADD FOREIGN KEY (c | succeeded | 2020-10-12 21:05:53.16299+00:00  | 00:00:18.564897 |        1 |
  597905748751515649 | SCHEMA CHANGE | ALTER TABLE movr.public.user_promo_codes ADD FOREIGN KEY (c | succeeded | 2020-10-12 21:05:53.16299+00:00  | 00:00:03.050331 |        1 |
  597905649737793537 | SCHEMA CHANGE | ALTER TABLE movr.public.vehicle_location_histories ADD FORE | succeeded | 2020-10-12 21:05:22.95018+00:00  | 00:00:03.039549 |        1 |
  597905652866678785 | SCHEMA CHANGE | ALTER TABLE movr.public.vehicle_location_histories ADD FORE | succeeded | 2020-10-12 21:05:22.95018+00:00  | 00:00:18.768623 |        1 |
```

Verify what was backed up remotely

```sql
SHOW BACKUP 's3://backup/2020-01?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key';
```

```text
  database_name | parent_schema_name |        object_name         | object_type | start_time |             end_time             | size_bytes | rows | is_full_cluster
----------------+--------------------+----------------------------+-------------+------------+----------------------------------+------------+------+------------------
  NULL          | NULL               | system                     | database    | NULL       | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  system        | public             | users                      | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |         99 |    2 |      true
  system        | public             | zones                      | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |        201 |    7 |      true
  system        | public             | settings                   | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |        371 |    5 |      true
  system        | public             | ui                         | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |        155 |    1 |      true
  system        | public             | jobs                       | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |      14002 |   18 |      true
  system        | public             | locations                  | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |        360 |    7 |      true
  system        | public             | role_members               | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |         94 |    1 |      true
  system        | public             | comments                   | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  system        | public             | role_options               | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  system        | public             | scheduled_jobs             | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  NULL          | NULL               | defaultdb                  | database    | NULL       | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  NULL          | NULL               | postgres                   | database    | NULL       | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  NULL          | NULL               | movr                       | database    | NULL       | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  movr          | public             | users                      | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |       4911 |   50 |      true
  movr          | public             | vehicles                   | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |       3182 |   15 |      true
  movr          | public             | rides                      | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |     156387 |  500 |      true
  movr          | public             | vehicle_location_histories | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |      73918 | 1000 |      true
  movr          | public             | promo_codes                | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |     219973 | 1000 |      true
  movr          | public             | user_promo_codes           | table       | NULL       | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
(20 rows)
```

Very good! The output shows both the `system` and `movr` databases backups are safely stored in S3!

Check how the backup files are actually stored. In a new terminal window, connect to container `s3mock`

```bash
docker exec -it s3mock /bin/sh
```

Then drill into the `backup` bucket directory inside `/tmp` to see the `sst` files and the `MANIFEST`s.

```bash
/ # ls -ltr /tmp/s3mockFileStore*/backup/2020-01/
total 188
drwxr-xr-x    2 root     root          4096 Oct 12 21:07 BACKUP-CHECKPOINT-CHECKSUM
drwxr-xr-x    2 root     root          4096 Oct 12 21:07 597906131332562949%002Esst
drwxr-xr-x    2 root     root          4096 Oct 12 21:07 597906130090360841%002Esst
[...]
drwxr-xr-x    2 root     root          4096 Oct 12 21:07 BACKUP_MANIFEST-CHECKSUM
drwxr-xr-x    2 root     root          4096 Oct 12 21:07 BACKUP_MANIFEST
drwxr-xr-x    2 root     root          4096 Oct 12 21:07 BACKUP-STATISTICS
```

These are the files for our **Full Cluster** backup. In the next lab we will run an **incremental** backup and see how the files will be nicely organized.

You can learn a lot more about Cockroach Backup strategies [in the docs](https://www.cockroachlabs.com/docs/v20.2/take-full-and-incremental-backups.html), too!

## Lab 2 - Incremental Backup

We are so content with CockroachDB features and performance that we decided to deploy another app using CockroachDB as our backend!

Let us load another database

```bash
cockroach workload init bank
```

Confirm the database was created and data was loaded

```sql
SELECT * FROM bank.bank LIMIT 5;
```

```text
  id | balance |                                               payload
-----+---------+-------------------------------------------------------------------------------------------------------
   0 |       0 | initial-dTqnRurXztAPkykhZWvsCmeJkMwRNcJAvTlNbgUEYfagEQJaHmfPsquKZUBOGwpAjPtATpGXFJkrtQCEJODSlmQctvyh
   1 |       0 | initial-PCLGABqTvrtRNyhAyOhQdyLfVtCmRykQJSsdwqUFABkPOMQayVEhiAwzZKHpJUiNmVaWYZnReMKfONZvRKbTETaIDccE
   2 |       0 | initial-VNfyUJHfCmMeAUoTgoSVvnByDyvpHNPHDfVoNWdXBFQpwMOBgNVtNijyTjmecvFqyeLHlDbIBRrbCzSeiHWSLmWbhIvh
   3 |       0 | initial-llflzsVuQYUlfwlyoaqjdwKUNgNFVgvlnINeOUUVyfxyvmOiAelxqkTBfpBBziYVHgQLLEuCazSXmURnXBlCCfsOqeji
   4 |       0 | initial-rmGzVVucMqbYnBaccWilErbWvcatqBsWSXvrbxYUUEhmOnccXzvqcsGuMVJNBjmzKErJzEzzfCzNTmLQqhkrDUxdgqDD
```

With the new data added, let's take another backup.
As in the specified location `s3://backup/2020-01` there is already a Full Backup, Cockroach will create a separate directory and put the incremental backup files in there.

```sql
BACKUP TO 's3://backup/2020-01?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key'
  AS OF SYSTEM TIME '-10s';
```

Check the JOBS table to confirm the backup is complete

```sql
SELECT * FROM jobsview ORDER BY created DESC LIMIT 5;
```

```text
        job_id       |   job_type    |                      short_description                      |  status   |             created              |    duration     | pct_done | error
---------------------+---------------+-------------------------------------------------------------+-----------+----------------------------------+-----------------+----------+--------
  597908447545393153 | BACKUP        | BACKUP TO 's3://backup/2020-01?AWS_ACCESS_KEY_ID=id&AWS_END | succeeded | 2020-10-12 21:19:37.595622+00:00 | 00:00:31.972327 |        1 |
  597906048349470721 | BACKUP        | BACKUP TO 's3://backup/2020-01?AWS_ACCESS_KEY_ID=id&AWS_END | succeeded | 2020-10-12 21:07:25.419137+00:00 | 00:00:31.57873  |        1 |
  597905751889248257 | SCHEMA CHANGE | ALTER TABLE movr.public.user_promo_codes ADD FOREIGN KEY (c | succeeded | 2020-10-12 21:05:53.16299+00:00  | 00:00:18.564897 |        1 |
  597905748751515649 | SCHEMA CHANGE | ALTER TABLE movr.public.user_promo_codes ADD FOREIGN KEY (c | succeeded | 2020-10-12 21:05:53.16299+00:00  | 00:00:03.050331 |        1 |
  597905652866678785 | SCHEMA CHANGE | ALTER TABLE movr.public.vehicle_location_histories ADD FORE | succeeded | 2020-10-12 21:05:22.95018+00:00  | 00:00:18.768623 |        1 |
````

Check in S3Mock how the files are organized. You can see that there is a new folder `20201012` (today's date).

```bash
/ # ls -ltr /tmp/s3mockFileStore*/backup/2020-01/
total 192
drwxr-xr-x    2 root     root          4096 Oct 12 21:07 BACKUP-CHECKPOINT-CHECKSUM
[...]
drwxr-xr-x    2 root     root          4096 Oct 12 21:07 BACKUP_MANIFEST-CHECKSUM
drwxr-xr-x    2 root     root          4096 Oct 12 21:07 BACKUP_MANIFEST
drwxr-xr-x    2 root     root          4096 Oct 12 21:07 BACKUP-STATISTICS
drwxr-xr-x    3 root     root          4096 Oct 12 21:19 20201012
```

And in that folder another folder with the timestamp and the backup files

```bash
/ # ls -ltr /tmp/s3mockFileStore1602536464462/backup/2020-01/20201012/211927\%002E05/
total 68
drwxr-xr-x    2 root     root          4096 Oct 12 21:19 BACKUP-CHECKPOINT-CHECKSUM
drwxr-xr-x    2 root     root          4096 Oct 12 21:20 597908528448012289%002Esst
[...]]
drwxr-xr-x    2 root     root          4096 Oct 12 21:20 BACKUP_MANIFEST-CHECKSUM
drwxr-xr-x    2 root     root          4096 Oct 12 21:20 BACKUP_MANIFEST
drwxr-xr-x    2 root     root          4096 Oct 12 21:20 BACKUP-STATISTICS
```

Now let's see the available backups at the new location

```sql
SHOW BACKUP 's3://backup/2020-01?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key';
```

```text
  database_name | parent_schema_name |        object_name         | object_type |            start_time            |             end_time             | size_bytes | rows | is_full_cluster
----------------+--------------------+----------------------------+-------------+----------------------------------+----------------------------------+------------+------+------------------
  NULL          | NULL               | system                     | database    | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  system        | public             | users                      | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |         99 |    2 |      true
  system        | public             | zones                      | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |        201 |    7 |      true
  system        | public             | settings                   | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |        371 |    5 |      true
  system        | public             | ui                         | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |        155 |    1 |      true
  system        | public             | jobs                       | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |      14002 |   18 |      true
  system        | public             | locations                  | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |        360 |    7 |      true
  system        | public             | role_members               | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |         94 |    1 |      true
  system        | public             | comments                   | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  system        | public             | role_options               | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  system        | public             | scheduled_jobs             | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  NULL          | NULL               | defaultdb                  | database    | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  NULL          | NULL               | postgres                   | database    | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  NULL          | NULL               | movr                       | database    | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  movr          | public             | users                      | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       4911 |   50 |      true
  movr          | public             | vehicles                   | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       3182 |   15 |      true
  movr          | public             | rides                      | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |     156387 |  500 |      true
  movr          | public             | vehicle_location_histories | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |      73918 | 1000 |      true
  movr          | public             | promo_codes                | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |     219973 | 1000 |      true
  movr          | public             | user_promo_codes           | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  NULL          | NULL               | system                     | database    | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |       NULL | NULL |      true
  system        | public             | users                      | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | zones                      | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | settings                   | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | ui                         | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | jobs                       | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |      18801 |    7 |      true
  system        | public             | locations                  | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | role_members               | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | comments                   | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | role_options               | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | scheduled_jobs             | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  NULL          | NULL               | defaultdb                  | database    | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |       NULL | NULL |      true
  NULL          | NULL               | postgres                   | database    | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |       NULL | NULL |      true
  NULL          | NULL               | movr                       | database    | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |       NULL | NULL |      true
  movr          | public             | users                      | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  movr          | public             | vehicles                   | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  movr          | public             | rides                      | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  movr          | public             | vehicle_location_histories | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  movr          | public             | promo_codes                | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  movr          | public             | user_promo_codes           | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  defaultdb     | public             | jobsview                   | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  NULL          | NULL               | bank                       | database    | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |       NULL | NULL |      true
  bank          | public             | bank                       | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |     114634 | 1000 |      true
(43 rows)
```

Very good! We have not updated the `movr` database, so `size_bytes` shows zeros, but we can see that a row for `bank` has been added. Also, we can see that the start and end time define when the incremental backups have been taken.

Another "day" has passed. Let's take another incremental backup

```sql
-- ??? Who did this, what's going on?!?
UPDATE movr.users SET NAME = 'malicious user'
WHERE id IN ('ae147ae1-47ae-4800-8000-000000000022',
            'b3333333-3333-4000-8000-000000000023',
            'b851eb85-1eb8-4000-8000-000000000024');

-- wait 10 seconds else the above changes won't be captured!
BACKUP TO 's3://backup/2020-01?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key'
  AS OF SYSTEM TIME '-10s';
```

in S3Mock, another folder has been added for the new timestamp

```bash
/ # ls -ltr /tmp/s3mockFileStore1602536464462/backup/2020-01/20201012/
total 8
drwxr-xr-x   19 root     root          4096 Oct 12 21:20 211927%002E05
drwxr-xr-x   11 root     root          4096 Oct 12 21:29 212824%002E80
```

Confirm the backup looks good

```sql
SHOW BACKUP 's3://backup/2020-01?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key';
```

```text
  database_name | parent_schema_name |        object_name         | object_type |            start_time            |             end_time             | size_bytes | rows | is_full_cluster
----------------+--------------------+----------------------------+-------------+----------------------------------+----------------------------------+------------+------+------------------
  NULL          | NULL               | system                     | database    | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  system        | public             | users                      | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |         99 |    2 |      true
  system        | public             | zones                      | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |        201 |    7 |      true
  system        | public             | settings                   | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |        371 |    5 |      true
  system        | public             | ui                         | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |        155 |    1 |      true
  system        | public             | jobs                       | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |      14002 |   18 |      true
  system        | public             | locations                  | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |        360 |    7 |      true
  system        | public             | role_members               | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |         94 |    1 |      true
  system        | public             | comments                   | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  system        | public             | role_options               | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  system        | public             | scheduled_jobs             | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  NULL          | NULL               | defaultdb                  | database    | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  NULL          | NULL               | postgres                   | database    | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  NULL          | NULL               | movr                       | database    | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       NULL | NULL |      true
  movr          | public             | users                      | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       4911 |   50 |      true
  movr          | public             | vehicles                   | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |       3182 |   15 |      true
  movr          | public             | rides                      | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |     156387 |  500 |      true
  movr          | public             | vehicle_location_histories | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |      73918 | 1000 |      true
  movr          | public             | promo_codes                | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |     219973 | 1000 |      true
  movr          | public             | user_promo_codes           | table       | NULL                             | 2020-10-12 21:07:14.570127+00:00 |          0 |    0 |      true
  NULL          | NULL               | system                     | database    | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |       NULL | NULL |      true
  system        | public             | users                      | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | zones                      | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | settings                   | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | ui                         | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | jobs                       | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |      18801 |    7 |      true
  system        | public             | locations                  | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | role_members               | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | comments                   | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | role_options               | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  system        | public             | scheduled_jobs             | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  NULL          | NULL               | defaultdb                  | database    | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |       NULL | NULL |      true
  NULL          | NULL               | postgres                   | database    | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |       NULL | NULL |      true
  NULL          | NULL               | movr                       | database    | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |       NULL | NULL |      true
  movr          | public             | users                      | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  movr          | public             | vehicles                   | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  movr          | public             | rides                      | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  movr          | public             | vehicle_location_histories | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  movr          | public             | promo_codes                | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  movr          | public             | user_promo_codes           | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  defaultdb     | public             | jobsview                   | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |          0 |    0 |      true
  NULL          | NULL               | bank                       | database    | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |       NULL | NULL |      true
  bank          | public             | bank                       | table       | 2020-10-12 21:07:14.570127+00:00 | 2020-10-12 21:19:27.053348+00:00 |     114634 | 1000 |      true
  NULL          | NULL               | system                     | database    | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |       NULL | NULL |      true
  system        | public             | users                      | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  system        | public             | zones                      | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  system        | public             | settings                   | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  system        | public             | ui                         | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  system        | public             | jobs                       | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |      13702 |    2 |      true
  system        | public             | locations                  | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  system        | public             | role_members               | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  system        | public             | comments                   | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  system        | public             | role_options               | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  system        | public             | scheduled_jobs             | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  NULL          | NULL               | defaultdb                  | database    | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |       NULL | NULL |      true
  NULL          | NULL               | postgres                   | database    | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |       NULL | NULL |      true
  NULL          | NULL               | movr                       | database    | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |       NULL | NULL |      true
  movr          | public             | users                      | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |        309 |    3 |      true
  movr          | public             | vehicles                   | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  movr          | public             | rides                      | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  movr          | public             | vehicle_location_histories | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  movr          | public             | promo_codes                | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  movr          | public             | user_promo_codes           | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  defaultdb     | public             | jobsview                   | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
  NULL          | NULL               | bank                       | database    | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |       NULL | NULL |      true
  bank          | public             | bank                       | table       | 2020-10-12 21:19:27.053348+00:00 | 2020-10-12 21:28:24.809179+00:00 |          0 |    0 |      true
(66 rows)
```

The backup process looks good, but you got hacked! A malicious user has corrupted some of your data!!

```sql
SELECT * FROM movr.users WHERE name = 'malicious user';
```

```text
                   id                  |   city    |      name      |            address            | credit_card
---------------------------------------+-----------+----------------+-------------------------------+--------------
  ae147ae1-47ae-4800-8000-000000000022 | amsterdam | malicious user | 88194 Angela Gardens Suite 94 | 4443538758
  b3333333-3333-4000-8000-000000000023 | amsterdam | malicious user | 29590 Butler Plain Apt. 25    | 3750897994
  b851eb85-1eb8-4000-8000-000000000024 | amsterdam | malicious user | 32768 Eric Divide Suite 88    | 8107478823
(3 rows)
```

## Lab 3 - Restore a database

After careful consideration, you decide that it's best to drop the database and restore from the last valid backup - the 2nd incremental backup - with `enddate` = `2020-10-12 21:19:27.053348+00:00`.

```sql
-- this can take 2-3 minutes
DROP DATABASE movr CASCADE;

-- check note below re timestamp precision - notice I added a trailing 5 to the microseconds...
RESTORE DATABASE movr
FROM 's3://backup/2020-01?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key'
  AS OF SYSTEM TIME '2020-10-12 21:19:27.0533485+00:00';
```

```text
DROP DATABASE

Time: 513.329ms

        job_id       |  status   | fraction_completed | rows | index_entries | bytes
---------------------+-----------+--------------------+------+---------------+---------
  596743986481856513 | succeeded |                  1 | 2565 |          1015 | 458371
(1 row)
```

**Please note:** you might get an error like below when you try to restore

```text
ERROR: invalid RESTORE timestamp: restoring to arbitrary time requires that BACKUP for requested time be created with 'revision_history' option. nearest BACKUP times are 2020-10-12 21:07:14.5701275 +0000 UTC or 2020-10-12 21:19:27.0533485 +0000 UTC
```

That's because the timestamp you entered is not exactly the `enddate` timestamp. Check the timestamp suggested in the error message. In this example, I have updated the enddate by adding a '5' to my microseconds.

```sql
--- verify the malicious user is gone
SELECT * FROM movr.users WHERE name = 'malicious user';
```

```text
  id | city | name | address | credit_card
-----+------+------+---------+--------------
(0 rows)

Time: 9.259ms
```

Good, you're back in business!

There are many ways in which you can manage your backups. Read the docs to find out more about:

- [Backups with revision history and restore from point in time](https://www.cockroachlabs.com/docs/v20.2/take-backups-with-revision-history-and-restore-from-a-point-in-time.html)
- [Encrypted Backup and Restore](https://www.cockroachlabs.com/docs/v20.2/take-and-restore-encrypted-backups.html)
- [Locality-aware Backups](https://www.cockroachlabs.com/docs/v20.2/take-and-restore-locality-aware-backups.html)
- [Scheduling Backups](https://www.cockroachlabs.com/docs/v20.2/manage-a-backup-schedule.html)

## Lab 4 - Automate backup jobs

You are happy with the way your backups are taken and you want to automate this process with the following schedule:

- Weekly on Sunday: Full Cluster backup
- Daily: incremental backup

You can run this schedule from CockroachDB directly, without using tolls like `cron` or `anacron`. Run below statement

```sql
CREATE SCHEDULE weekly
  FOR BACKUP INTO 's3://backup/weekly?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key'
    RECURRING '@daily'
    FULL BACKUP '@weekly'
    WITH SCHEDULE OPTIONS first_run = 'now';
```

```text
     schedule_id     | label  |                     status                     |            first_run             | schedule |                                                               backup_stmt
---------------------+--------+------------------------------------------------+----------------------------------+----------+------------------------------------------------------------------------------------------------------------------------------------------
  598169895033896961 | weekly | PAUSED: Waiting for initial backup to complete | NULL                             | @daily   | BACKUP INTO LATEST IN 's3://backup/weekly?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key' WITH detached
  598169897925541889 | weekly | ACTIVE                                         | 2020-10-13 19:29:10.756144+00:00 | @weekly  | BACKUP INTO 's3://backup/weekly?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key' WITH detached
(2 rows)
```

Confirm the schedule looks good, check the `next_run` column

```sql
SHOW SCHEDULES;
```

```text
          id         |         label          | schedule_status |         next_run          | state | recurrence | jobsrunning | owner |             created              |                                                                                            command
---------------------+------------------------+-----------------+---------------------------+-------+------------+-------------+-------+----------------------------------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  598169895033896961 | weekly                 | ACTIVE          | 2020-10-14 00:00:00+00:00 |       | @daily     |           0 | root  | 2020-10-13 19:29:16.627381+00:00 | {"backup_statement": "BACKUP INTO LATEST IN 's3://backup/weekly?AWS_ACCESS_KEY_ID=id&AWS_ENDPOINT=http%3A%2F%2Fs3mock%3A9090&AWS_SECRET_ACCESS_KEY=redacted' WITH detached", "backup_type": 1}
  598169897925541889 | weekly                 | ACTIVE          | 2020-10-18 00:00:00+00:00 |       | @weekly    |           0 | root  | 2020-10-13 19:29:20.901034+00:00 | {"backup_statement": "BACKUP INTO 's3://backup/weekly?AWS_ACCESS_KEY_ID=id&AWS_ENDPOINT=http%3A%2F%2Fs3mock%3A9090&AWS_SECRET_ACCESS_KEY=redacted' WITH detached"}
(2 rows)
```

As we set the `first_run` to `now`, the first backup job was started, and most likely it just finished, confirm in the Admin UI > Jobs page. Being the first backup, this is necessarely a Full Backup regardless of the schedule.

Let's verify we can see the first backup

```sql
SHOW BACKUP 's3://backup/weekly?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key';
```

```text
ERROR: s3 object does not exist: NoSuchKey: The specified key does not exist.
        status code: 404, request id: , host id:: external_storage: file doesn't exist
```

We got an error: this is because the scheduler creates a directory structure for the backups, and the structure is `your-location/yyyy/mm/dd-hhmmss.00`.
You can see this structure in S3Mock

```bash
/tmp/s3mockFileStore1602613493412/backup/weekly/2020/10/13-192910%002E75 # ls -l
total 236
drwxr-xr-x    2 root     root          4096 Oct 13 19:29 598169993547481095%002Esst
[...]
drwxr-xr-x    2 root     root          4096 Oct 13 19:29 BACKUP-CHECKPOINT-CHECKSUM
drwxr-xr-x    2 root     root          4096 Oct 13 19:30 BACKUP-STATISTICS
drwxr-xr-x    2 root     root          4096 Oct 13 19:30 BACKUP_MANIFEST
drwxr-xr-x    2 root     root          4096 Oct 13 19:30 BACKUP_MANIFEST-CHECKSUM
```

So what we can use instead is below statement which gives us a list of all backup paths for any given location.

```sql
SHOW BACKUPS IN 's3://backup/weekly?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key';
```

```text
          path
------------------------
  2020/10/13-192910.75
```

Now we can use this information to view the backup

```sql
SHOW BACKUP 's3://backup/weekly/2020/10/13-192910.75?AWS_ENDPOINT=http://s3mock:9090&AWS_ACCESS_KEY_ID=id&AWS_SECRET_ACCESS_KEY=key';
```

```text
  database_name | parent_schema_name |        object_name         | object_type | start_time |             end_time             | size_bytes | rows | is_full_cluster
----------------+--------------------+----------------------------+-------------+------------+----------------------------------+------------+------+------------------
  NULL          | NULL               | system                     | database    | NULL       | 2020-10-13 19:29:10.756144+00:00 |       NULL | NULL |      true
  system        | public             | users                      | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |         99 |    2 |      true
  system        | public             | zones                      | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |        201 |    7 |      true
  system        | public             | settings                   | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |        374 |    5 |      true
  system        | public             | ui                         | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |        155 |    1 |      true
  system        | public             | jobs                       | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |      94732 |   41 |      true
  system        | public             | locations                  | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |        360 |    7 |      true
  system        | public             | role_members               | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |         94 |    1 |      true
  system        | public             | comments                   | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |          0 |    0 |      true
  system        | public             | role_options               | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |          0 |    0 |      true
  system        | public             | scheduled_jobs             | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |       1425 |    4 |      true
  NULL          | NULL               | defaultdb                  | database    | NULL       | 2020-10-13 19:29:10.756144+00:00 |       NULL | NULL |      true
  NULL          | NULL               | postgres                   | database    | NULL       | 2020-10-13 19:29:10.756144+00:00 |       NULL | NULL |      true
  defaultdb     | public             | jobsview                   | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |          0 |    0 |      true
  NULL          | NULL               | bank                       | database    | NULL       | 2020-10-13 19:29:10.756144+00:00 |       NULL | NULL |      true
  bank          | public             | bank                       | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |     114634 | 1000 |      true
  NULL          | NULL               | movr                       | database    | NULL       | 2020-10-13 19:29:10.756144+00:00 |       NULL | NULL |      true
  movr          | public             | users                      | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |       4911 |   50 |      true
  movr          | public             | vehicles                   | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |       3182 |   15 |      true
  movr          | public             | rides                      | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |     156387 |  500 |      true
  movr          | public             | vehicle_location_histories | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |      73918 | 1000 |      true
  movr          | public             | promo_codes                | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |     219973 | 1000 |      true
  movr          | public             | user_promo_codes           | table       | NULL       | 2020-10-13 19:29:10.756144+00:00 |          0 |    0 |      true
(23 rows)
```

Perfect! Let it run for a few days, ideally until next week so you can see the scheduler run Sunday's full backup cluster job.

You can learn more about [Backup Schedule](https://www.cockroachlabs.com/docs/v20.2/manage-a-backup-schedule.html) and the SQL command [CREATE SCHEDULE FOR BACKUP](https://www.cockroachlabs.com/docs/v20.2/create-schedule-for-backup) in our docs.

## Lab 5 - Repaving

In this lab, we practice the technique of **Repaving**, the process of rebuilding the environment from a known clean state, useful as a cybersecurity measure.

In the context of repaving the CockroachDB platform, you have 2 options:

1. Decommission
2. Data Swap (Detach/Attach)

### Decommission

The **Decommission** process consist of the following:

1. Add a new node, in the same region, dc, az, rack with the same locality settings as the node being repaved.
2. Wait for that new node to connected and starts receiving data
3. Decommission the node to cycle out.
4. Once the decommission is finished, the vm/container can be removed.

Pros:

- Can do this to more than one node at a time
- More resilient during the transition as an extra node has been added
- The added node adds CPU that can be used for queries as soon as the replicas make it to it

Cons:

- All replicas must be moved off of the node being decommissioned
- Significantly slower (might be hours)
- Higher network bandwidth usage

You can read more about the Decommission process in our [docs](https://www.cockroachlabs.com/docs/v20.2/remove-nodes.html).

Let's spin up a new node and add it to the cluster. In this example, we want to repave node `roach-seattle-3` for node `roach-seattle-4`

```bash
docker run -d --name=roach-seattle-4 --hostname=roach-seattle-4 --ip=172.27.0.14 --cap-add NET_ADMIN --net=us-west2-net --add-host=roach-seattle-1:172.27.0.11 --add-host=roach-seattle-2:172.27.0.12 --add-host=roach-seattle-3:172.27.0.13 -v "roach-seattle-4-data:/cockroach/cockroach-data" cockroachdb/cockroach:latest start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-west2,zone=c

# attach container to networks
docker network connect uswest-useast-net roach-seattle-4
docker network connect uswest-euwest-net roach-seattle-4
```

In the AdminUI, you should see you have now 10 nodes and 2 nodes are in the `us-west2` region, zone `c`.

![adminui-decommission](media/adminui-decommission.png)

In the Overview > Node List, click on the node10 to see that this node is already up and operational

![adminui-node10](media/adminui-node10.png)

You can also see from the CLI

```bash
root@roach-newyork-1:/cockroach# cockroach node status --insecure
  id |        address        |      sql_address      |  build  |            started_at            |            updated_at            |        locality        | is_available | is_live
-----+-----------------------+-----------------------+---------+----------------------------------+----------------------------------+------------------------+--------------+----------
   1 | roach-newyork-1:26257 | roach-newyork-1:26257 | v20.2.x | 2020-10-08 15:43:06.102417+00:00 | 2020-10-08 19:48:42.057632+00:00 | region=us-east4,zone=a | true         | true
   2 | roach-newyork-2:26257 | roach-newyork-2:26257 | v20.2.x | 2020-10-08 15:43:06.43971+00:00  | 2020-10-08 19:48:42.38807+00:00  | region=us-east4,zone=b | true         | true
   3 | roach-newyork-3:26257 | roach-newyork-3:26257 | v20.2.x | 2020-10-08 15:43:06.894065+00:00 | 2020-10-08 19:48:42.842474+00:00 | region=us-east4,zone=c | true         | true
   4 | roach-seattle-1:26257 | roach-seattle-1:26257 | v20.2.x | 2020-10-08 15:43:17.319058+00:00 | 2020-10-08 19:48:44.300456+00:00 | region=us-west2,zone=a | true         | true
   5 | roach-seattle-2:26257 | roach-seattle-2:26257 | v20.2.x | 2020-10-08 15:43:18.046842+00:00 | 2020-10-08 19:48:40.567553+00:00 | region=us-west2,zone=b | true         | true
   6 | roach-seattle-3:26257 | roach-seattle-3:26257 | v20.2.x | 2020-10-08 15:43:18.704429+00:00 | 2020-10-08 19:48:41.219253+00:00 | region=us-west2,zone=c | true         | true
   7 | roach-london-2:26257  | roach-london-2:26257  | v20.2.x | 2020-10-08 15:43:21.746067+00:00 | 2020-10-08 19:48:44.378163+00:00 | region=eu-west2,zone=b | true         | true
   8 | roach-london-1:26257  | roach-london-1:26257  | v20.2.x | 2020-10-08 15:43:22.22653+00:00  | 2020-10-08 19:48:40.398695+00:00 | region=eu-west2,zone=a | true         | true
   9 | roach-london-3:26257  | roach-london-3:26257  | v20.2.x | 2020-10-08 15:43:22.250806+00:00 | 2020-10-08 19:48:40.438241+00:00 | region=eu-west2,zone=c | true         | true
  10 | roach-seattle-4:26257 | roach-seattle-4:26257 | v20.2.x | 2020-10-08 19:37:35.190801+00:00 | 2020-10-08 19:48:40.624029+00:00 | region=us-west2,zone=c | true         | true
(10 rows)
```

At this point, you can decommission node `roach-seattle-3`, which from above table is node with id = 6.

```bash
root@roach-newyork-1:/cockroach# cockroach node decommission 6 --insecure

  id | is_live | replicas | is_decommissioning | is_draining
-----+---------+----------+--------------------+--------------
   6 |  true   |       21 |        true        |    false
(1 row)
.....
  id | is_live | replicas | is_decommissioning | is_draining
-----+---------+----------+--------------------+--------------
   6 |  true   |       19 |        true        |    false
(1 row)

[...]

  id | is_live | replicas | is_decommissioning | is_draining
-----+---------+----------+--------------------+--------------
   6 |  true   |        0 |        true        |    false
(1 row)

No more data reported on target nodes. Please verify cluster health before removing the nodes.
```

Verify the node is empty using the AdminUI

![adminui-node6](media/adminui-node6.png)

And finally you can just stop and remove the container. Please note: it will take a few minutes for the AdminUI to update with the correct status of the cluster

```bash
docker stop roach-seattle-3
docker rm roach-seattle-3
```

Verify the status on the CLI

```bash
root@roach-newyork-1:/cockroach# cockroach node status --insecure
  id |        address        |      sql_address      |  build  |            started_at            |            updated_at            |        locality        | is_available | is_live
-----+-----------------------+-----------------------+---------+----------------------------------+----------------------------------+------------------------+--------------+----------
   1 | roach-newyork-1:26257 | roach-newyork-1:26257 | v20.2.x | 2020-10-08 15:43:06.102417+00:00 | 2020-10-08 20:00:45.702579+00:00 | region=us-east4,zone=a | true         | true
   2 | roach-newyork-2:26257 | roach-newyork-2:26257 | v20.2.x | 2020-10-08 15:43:06.43971+00:00  | 2020-10-08 20:00:46.032631+00:00 | region=us-east4,zone=b | true         | true
   3 | roach-newyork-3:26257 | roach-newyork-3:26257 | v20.2.x | 2020-10-08 15:43:06.894065+00:00 | 2020-10-08 20:00:42.021404+00:00 | region=us-east4,zone=c | true         | true
   4 | roach-seattle-1:26257 | roach-seattle-1:26257 | v20.2.x | 2020-10-08 15:43:17.319058+00:00 | 2020-10-08 20:00:43.479506+00:00 | region=us-west2,zone=a | true         | true
   5 | roach-seattle-2:26257 | roach-seattle-2:26257 | v20.2.x | 2020-10-08 15:43:18.046842+00:00 | 2020-10-08 20:00:44.211455+00:00 | region=us-west2,zone=b | true         | true
   7 | roach-london-2:26257  | roach-london-2:26257  | v20.2.x | 2020-10-08 15:43:21.746067+00:00 | 2020-10-08 20:00:43.557008+00:00 | region=eu-west2,zone=b | true         | true
   8 | roach-london-1:26257  | roach-london-1:26257  | v20.2.x | 2020-10-08 15:43:22.22653+00:00  | 2020-10-08 20:00:44.041947+00:00 | region=eu-west2,zone=a | true         | true
   9 | roach-london-3:26257  | roach-london-3:26257  | v20.2.x | 2020-10-08 15:43:22.250806+00:00 | 2020-10-08 20:00:44.081871+00:00 | region=eu-west2,zone=c | true         | true
  10 | roach-seattle-4:26257 | roach-seattle-4:26257 | v20.2.x | 2020-10-08 19:37:35.190801+00:00 | 2020-10-08 20:00:44.268408+00:00 | region=us-west2,zone=c | true         | true
(9 rows)
```

Good job, you've successfully and safely repaved one node using decommission!

### Data Swap

The process of **data Swap** consists of:

1. Spin up a new cockroach node (without starting cockroach)
2. Stop the cockroach node being cycled out (sigterm)
3. Detach the data storage from the old node
4. Attach the data storage to the new node
5. Start cockroach in the new node

Pros:

- Super fast
- Less than a minute if done well
- No network usage

Cons:

- Less resilient during this swap, one node is down, so it should only be done one node at a time
- If this takes longer than 5 mins, the system will declare the node dead and it will start the repair process.

The key to this is: automation. We will not use any DevOps tools however as in this lab we focus on the process. Also, as our cluster runs on docker containes and not on VMs, the process varies slightly.

The CockroachDB data storage is mounted as a Docker Volume. Check the docker volume in your cluster

```bash
$ docker volume ls
DRIVER              VOLUME NAME
local               roach-london-1-data
local               roach-london-2-data
local               roach-london-3-data
local               roach-newyork-1-data
local               roach-newyork-2-data
local               roach-newyork-3-data
local               roach-seattle-1-data
local               roach-seattle-2-data
local               roach-seattle-3-data
local               roach-seattle-4-data
```

You remember that in the previous exercise we have stopped and removed `roach-seattle-3` and yet its Volume persisted. We will take advantage of this feature for this repaving technique.

Let's repave node `roach-london-1` for `roach-london-4`

```bash
# drain roach-london-1
docker exec -it roach-london-1 cockroach node drain --insecure

# stop and remove the node immediately
docker stop roach-london-1
docker rm roach-london-1

# start the new container using the same volume roach-london-1-data
docker run -d --name=roach-london-4 --hostname=roach-london-4 --ip=172.29.0.14 --cap-add NET_ADMIN --net=eu-west2-net --add-host=roach-london-1:172.29.0.11 --add-host=roach-london-2:172.29.0.12 --add-host=roach-london-3:172.29.0.13 -v "roach-london-1-data:/cockroach/cockroach-data" cockroachdb/cockroach:latest start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=eu-west2,zone=a

# connect to networks
docker network connect useast-euwest-net roach-london-4
docker network connect uswest-euwest-net roach-london-4
```

Check the AdminUI. Immediately you will see the node added to the cluster, with no need to repair!

![adminui-node8](media/adminui-node8.png)

You can verify from the CLI, too

```bash
root@roach-newyork-1:/cockroach# cockroach node status --insecure
  id |        address        |      sql_address      |  build  |            started_at            |            updated_at            |        locality        | is_available | is_live
-----+-----------------------+-----------------------+---------+----------------------------------+----------------------------------+------------------------+--------------+----------
   1 | roach-newyork-1:26257 | roach-newyork-1:26257 | v20.2.x | 2020-10-08 15:43:06.102417+00:00 | 2020-10-08 20:23:09.69264+00:00  | region=us-east4,zone=a | true         | true
   2 | roach-newyork-2:26257 | roach-newyork-2:26257 | v20.2.x | 2020-10-08 15:43:06.43971+00:00  | 2020-10-08 20:23:10.023896+00:00 | region=us-east4,zone=b | true         | true
   3 | roach-newyork-3:26257 | roach-newyork-3:26257 | v20.2.x | 2020-10-08 15:43:06.894065+00:00 | 2020-10-08 20:23:05.977296+00:00 | region=us-east4,zone=c | true         | true
   4 | roach-seattle-1:26257 | roach-seattle-1:26257 | v20.2.x | 2020-10-08 15:43:17.319058+00:00 | 2020-10-08 20:23:07.468981+00:00 | region=us-west2,zone=a | true         | true
   5 | roach-seattle-2:26257 | roach-seattle-2:26257 | v20.2.x | 2020-10-08 15:43:18.046842+00:00 | 2020-10-08 20:23:08.202968+00:00 | region=us-west2,zone=b | true         | true
   7 | roach-london-2:26257  | roach-london-2:26257  | v20.2.x | 2020-10-08 15:43:21.746067+00:00 | 2020-10-08 20:23:07.547155+00:00 | region=eu-west2,zone=b | true         | true
   8 | roach-london-4:26257  | roach-london-4:26257  | v20.2.x | 2020-10-08 20:21:36.196613+00:00 | 2020-10-08 20:23:09.491299+00:00 | region=eu-west2,zone=a | true         | true
   9 | roach-london-3:26257  | roach-london-3:26257  | v20.2.x | 2020-10-08 15:43:22.250806+00:00 | 2020-10-08 20:23:08.072601+00:00 | region=eu-west2,zone=c | true         | true
  10 | roach-seattle-4:26257 | roach-seattle-4:26257 | v20.2.x | 2020-10-08 19:37:35.190801+00:00 | 2020-10-08 20:23:08.258708+00:00 | region=us-west2,zone=c | true         | true
(9 rows)
```

Our new node `roach-london-4` is up and running, we repaved in a matter of seconds!

## Summary

In this labs we have learned how to backup and restore your data, how to create a schedule and where to look into the Documentation for further features and options.
We also practice the technique of Repaving and, while we worked on Docker, the same principles can be applied to VMs or to Kubernetes Pods.
