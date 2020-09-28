# Serializable Transactions - Student Labs

In this lab we will explore how to best use Serializable transactions with CockroachDB.

## Overview

CockroachDB only uses the `SERIALIZABLE` isolation level, the highest logical isolation level, required to guarantee ACID transactions.

For a light overview and understanding of isolation levels, here's a short and useful [tutorial](https://www.cockroachlabs.com/docs/v20.1/demo-serializable.html).

However, the most comprehensive information on Transaction in CockroachDB is [the Transactions doc](https://www.cockroachlabs.com/docs/v20.1/transactions.html).

For in-depth understanding, check also the [architecture pages for the transaction layer](https://www.cockroachlabs.com/docs/v20.1/architecture/transaction-layer.html).

## Labs Prerequisites

1. Build the dev cluster following [these instructions](/infrastructure/build-local-docker-cluster.md).

2. You also need:

    - a modern web browser,
    - a SQL client:
      - [Cockroach SQL client](https://www.cockroachlabs.com/docs/stable/install-cockroachdb-linux)
      - `psql`
      - [DBeaver Community edition](https://dbeaver.io/download/) (SQL tool with built-in CockroachDB plugin)

3. Install [Apache JMeter](https://jmeter.apache.org/):

    - Mac

        ```bash
        brew install jmeter
        open /usr/local/bin/jmeter
        ```

    - [Windows](https://medium.com/@taufiq_ibrahim/installing-apache-jmeter-on-windows-10-62b7f53841f)
    - [Linux](https://linuxhint.com/install_apache_jmeter_ubuntu/)

## Labs 0 - Setup JMeter and database

Once you have JMeter installed, you will need to:

1. Add the below plugins. In JMeter, go to `Options > Plugins Manager` and search in the `Available Plugins` tab

    ![plug-ins](media/jmeter-plugins.png)

2. Download the [JMeter test configuration file](https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/serializable-transactions/data/jmeter-crdb-serializable.jmx).

    ```bash
    wget https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/serializable-transactions/data/jmeter-crdb-serializable.jmx
    ```

3. Download the [Postgresql JDBC driver](https://jdbc.postgresql.org/) and place it in JMeter's `lib` directory, as documented [here](https://jmeter.apache.org/usermanual/get-started.html#classpath).

    As an example, the location in macOS when installing JMeter using Homebrew is: `/usr/local/Cellar/jmeter/5.3/libexec/lib`.

4. Load the configuration for the tests. In JMeter, `File > Open` and select the `.jmx` file you just downloaded. JMeter is now ready - check the JDBC URL at the bottom pointing to your cluster.

    ![jmeter-ready](media/jmeter-ready.png)

You are now ready to connect to the database

```bash
# use cockroach sql, defaults to localhost:26257
cockroach sql --insecure -d defaultdb

# or use the --url param for any another host:
cockroach sql --url "postgresql://localhost:26258/defaultdb?sslmode=disable"

# or use psql
psql -h localhost -p 26257 -U root defaultdb
```

Run the following to create the test database and populate the table for the tests.

```sql
CREATE DATABASE serial;

USE serial;

CREATE TABLE alerts (
    id INT NOT NULL DEFAULT unique_rowid(),
    customer_id INT,
    alert_type STRING,
    severity INT,
    cstatus STRING,
    adesc STRING,
    id1 INT,
    id1_desc STRING,
    id2 INT,
    id2_desc STRING,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id),
    INDEX alerts_i_idx_1 (cstatus ASC, customer_id ASC, id1 ASC, severity ASC),
    INDEX alerts_i_idx_2 (customer_id ASC, id1 ASC, id1_desc ASC, id2 ASC),
    INDEX alerts_i_idx_3 (id2 ASC, id2_desc ASC, cstatus ASC)
);

-- pin table to us-west2 region for quick r/w access
ALTER TABLE alerts
CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{"+region=us-west2"}',
  lease_preferences = '[[+region=us-west2]]';

INSERT INTO alerts
    SELECT
    a,
    round(random()*10000)::INT,
    'ALERT_TYPE',
    round(random()*10)::INT,
    concat('STATUS-',ROUND(random()*10)::STRING),
    'ADESC',
    round(random()*1000)::INT,
    'ID1_DESCRIPTION',
    round(random()*5000)::INT,
    'ID2_DESCRIPTION',
    NOW(),
    NOW()
FROM generate_series(1,100000) AS a;
```

Check what the table looks like

```sql
SELECT * FROM alerts LIMIT 10;
```

```text
  id | customer_id | alert_type | severity |  cstatus  | adesc | id1 |    id1_desc     | id2  |    id2_desc     |            created_at            |            updated_at
-----+-------------+------------+----------+-----------+-------+-----+-----------------+------+-----------------+----------------------------------+-----------------------------------
   1 |        2192 | ALERT_TYPE |        5 | STATUS-2  | ADESC | 473 | ID1_DESCRIPTION | 3110 | ID2_DESCRIPTION | 2020-09-25 12:52:35.516589+00:00 | 2020-09-25 12:52:35.516589+00:00
   2 |        1936 | ALERT_TYPE |       10 | STATUS-1  | ADESC | 598 | ID1_DESCRIPTION |  150 | ID2_DESCRIPTION | 2020-09-25 12:52:35.516589+00:00 | 2020-09-25 12:52:35.516589+00:00
   3 |        3107 | ALERT_TYPE |        2 | STATUS-8  | ADESC | 998 | ID1_DESCRIPTION |  241 | ID2_DESCRIPTION | 2020-09-25 12:52:35.516589+00:00 | 2020-09-25 12:52:35.516589+00:00
   4 |        5240 | ALERT_TYPE |        2 | STATUS-9  | ADESC | 992 | ID1_DESCRIPTION | 3315 | ID2_DESCRIPTION | 2020-09-25 12:52:35.516589+00:00 | 2020-09-25 12:52:35.516589+00:00
   5 |        7628 | ALERT_TYPE |        3 | STATUS-2  | ADESC | 560 | ID1_DESCRIPTION | 3475 | ID2_DESCRIPTION | 2020-09-25 12:52:35.516589+00:00 | 2020-09-25 12:52:35.516589+00:00
   6 |         806 | ALERT_TYPE |        6 | STATUS-10 | ADESC | 661 | ID1_DESCRIPTION | 2204 | ID2_DESCRIPTION | 2020-09-25 12:52:35.516589+00:00 | 2020-09-25 12:52:35.516589+00:00
   7 |        6276 | ALERT_TYPE |        2 | STATUS-8  | ADESC | 677 | ID1_DESCRIPTION | 2253 | ID2_DESCRIPTION | 2020-09-25 12:52:35.516589+00:00 | 2020-09-25 12:52:35.516589+00:00
   8 |        3927 | ALERT_TYPE |        4 | STATUS-0  | ADESC | 200 | ID1_DESCRIPTION | 4298 | ID2_DESCRIPTION | 2020-09-25 12:52:35.516589+00:00 | 2020-09-25 12:52:35.516589+00:00
   9 |        1360 | ALERT_TYPE |        3 | STATUS-7  | ADESC | 679 | ID1_DESCRIPTION | 2827 | ID2_DESCRIPTION | 2020-09-25 12:52:35.516589+00:00 | 2020-09-25 12:52:35.516589+00:00
  10 |        7346 | ALERT_TYPE |        3 | STATUS-2  | ADESC | 364 | ID1_DESCRIPTION | 3055 | ID2_DESCRIPTION | 2020-09-25 12:52:35.516589+00:00 | 2020-09-25 12:52:35.516589+00:00
(10 rows)
```

You should now be ready to run the various scenarios to run the demos covered by the presentation.
Below, I will describe the setup, transactions, and number of threads used to simulate the various scenarios.
With this, you should be able to use the JMeter setup, generate the test code, or use another test tool to drive the cluster and experiment with serializable transactions.

## Labs Scenarios

The following test scenarios are described below:

- Contention with `SELECT`s and `UPDATE`s
- Bulk `UPDATES`s disturbing `SELECT`s performance
- Retries with `UPDATE`s
- Implicit Transactions with `SELECT FOR UPDATE` (SFU)

For each one of these tests, it is helpful to configurate the `application_name` variable, so that we can filter the metrics in the Admin UI for each individual test.
This is configured in two ways:

- JDBC connection string. I am using this method with JMeter to configure the Pool connection string.

    ![string](media/JDBC_application_name.png)

- Session Level parameter: `SET application_name='DEMO_1'`

## Lab 1 - Contention with SELECTs and UPDATEs

This test is to show the performance difference of various queries while running UPDATEs on the same set of rows... A tourture test.

In JMeter, select the test suite called **Demo #1**.

![jmeter-demo1](media/jmeter-demo1.png)

There are 5 total SELECTs statements: 4 query the same rows that are being updated (`select_high|low|normal|follower_reads`) and 1 queries a different set of rows as a baseline for no-contention (`select_normal_different_id`). Inspect the SQL statement for each.

There are 2 types of UPDATEs included: run the test with just **one** of these enabled - you can right click and `Toggle` to enable/disable - along with the 5 SELECTs to understand how they perform; the 6 queries are run in a thread group with 6 threads for 60 seconds.

In JMeter, choose the `jp@gc - Response Times Over Time` graph, then start the demo by clicking on the green **Play** button.

Feel free to experiment with the number of theads driving the workload based on your cluster configuration. For reference, below are the queries run simultaneously

```sql
-- select_high
BEGIN;
  SET TRANSACTION PRIORITY HIGH;
  SELECT * FROM alerts WHERE customer_id=9743;
COMMIT;

-- select_low
BEGIN;
  SET TRANSACTION PRIORITY LOW;
  SELECT * FROM alerts WHERE customer_id=9743;
COMMIT;

-- select_normal
BEGIN;
  SELECT * FROM alerts WHERE customer_id=9743;
COMMIT;

-- select_follower_read (implicit)
SELECT * FROM alerts AS OF SYSTEM TIME experimental_follower_read_timestamp() WHERE customer_id=9743;

-- select_normal_different_id
SELECT * FROM alerts WHERE customer_id=9800;

-- update_low
BEGIN;
SET TRANSACTION PRIORITY LOW;
  UPDATE alerts SET cstatus=cstatus, updated_at=NOW()
  WHERE customer_id=9743;
COMMIT;
```

Below is the result of running **Demo1**:

![demo1-jmeter-results](media/demo1-jmeter-results.png)

- `select_normal_different_id` has low latency due to no contention on the key.
- `select_follower_read` has low latency due to reading the value from a replica - no contention on the leaseholder.
- `select_high|normal|low` and the `UPDATE` have higher latency due to the higher level of contention. We can see that setting the `TRANSACTION PRIORITY` helped process `select_high` sooner than the other ones.

Checking the **Statements** page in the CockroachDB Admin UI and filtering for **App: DEMO1**, we see that there were 199 retries out of 1000 for the  `UPDATE alerts` query.

![demo1-ui-results](media/demo1-ui-results.png)

The two `SELECT FROM alerts` statements at the bottom refer to those sent by `select_normal_different_id` and `select_follower_read`. The statement at the top (with 3,000 queries sent) refers to those sent by `select_high|normal|low` in aggregate.

## Lab 2 - Bulk UPDATEs disturbing SELECT performance

This scenario simply runs bulk UPDATEs with various batch sizes while obeserving performance.
Basically, run one thread pool with 6 threads with one SELECT query and one bulk update.
There are bulk updates with 100, 1000, 5000, and 10000 commits per transaction.
Run each UPDATE individually along with the SELECT to see how it effects performance.

In JMeter:

1. Ensure every thread is dead - click the **Shutdown** button if necessary.
2. Ensure the graph is cleared by clicking the **Clear All** button.
3. Update the Database URL by setting `ApplicationName=Demo2`.
4. Disable the **Demo1** test suite and enable **Demo2**.
5. Start the test by clicking the **Play** button.

Below the queries run for reference.

```sql
-- Implicit Select
SELECT * FROM alerts WHERE customer_id=9743;

-- Bulk updates 100 rows
BEGIN;
SET TRANSACTION PRIORITY HIGH;
UPDATE alerts SET cstatus=cstatus, updated_at=NOW()
WHERE severity=${__Random(0,10)} LIMIT 100;
COMMIT;

-- 1000 rows
BEGIN;
SET TRANSACTION PRIORITY HIGH;
UPDATE alerts SET cstatus=cstatus, updated_at=NOW()
WHERE severity=${__Random(0,10)} LIMIT 1000;
COMMIT;

-- 5000 rows
BEGIN;
SET TRANSACTION PRIORITY HIGH;
UPDATE alerts SET cstatus=cstatus, updated_at=NOW()
WHERE severity=${__Random(0,10)} LIMIT 5000;
COMMIT;

-- 10000 rows
BEGIN;
SET TRANSACTION PRIORITY HIGH;
UPDATE alerts SET cstatus=cstatus, updated_at=NOW()
WHERE severity=${__Random(0,10)} LIMIT 10000;
COMMIT;

-- 50000 rows
BEGIN;
SET TRANSACTION PRIORITY HIGH;
UPDATE alerts SET cstatus=cstatus, updated_at=NOW()
WHERE severity=${__Random(0,10)} LIMIT 50000;
COMMIT;
```

Below the result of the test **Demo2** with 100 UPDATEs and 5000 UPDATEs.

![demo2-jmeter-results1](media/demo2-jmeter-results1.png)
![demo2-jmeter-results2](media/demo2-jmeter-results2.png)

and below in the Admin UI

![demo2-ui-results1](media/demo2-ui-results1.png)
![demo2-ui-results2](media/demo2-ui-results2.png)

It should be clear by the result of the test that we get better latency and performance by limitimg the size of the batch update.

## Lab 3 - Retries with UPDATEs

In this scenario we do two runs and observes the retry errors while updating the **same** rows throught a CLI client.

In JMeter:

1. Ensure every thread is dead - click the **Shutdown** button if necessary.
2. Ensure the graph is cleared by clicking the **Clear All** button.
3. Update the Database URL by setting `ApplicationName=Demo3`.
4. Disable the **Demo2** test suite and enable **Demo3**.
5. Start the test by clicking the **Play** button.

Below the queries run for reference.

First, run the `update_high` query with 3 threads, below for reference.

```sql
-- update_high
BEGIN;
SET TRANSACTION PRIORITY HIGH;
UPDATE alerts SET cstatus=cstatus, updated_at=NOW()
WHERE customer_id=9743;
COMMIT;
```

While this is running, connect with the CockroachDB CLI to the `serial` database. Type `BEGIN;` and then press Enter to `OPEN` the transaction.
You will then get the `OPEN>` prompt and can proceed with the UPDATE and COMMIT.

```text
root@:26257/defaultdb> use serial;
SET

Time: 421µs

root@:26257/serial> BEGIN;
Now adding input for a multi-line SQL transaction client-side (smart_prompt enabled).
Press Enter two times to send the SQL text collected so far to the server, or Ctrl+C to cancel.
You can also use \show to display the statements entered so far.
                 ->
BEGIN

Time: 133µs

root@:26257/serial  OPEN> UPDATE alerts SET cstatus=cstatus, updated_at=NOW()
WHERE customer_id=9743;
UPDATE 98

Time: 64.395ms

root@:26257/serial  OPEN> COMMIT;
ERROR: restart transaction: TransactionRetryWithProtoRefreshError: TransactionAbortedError(ABORT_REASON_CLIENT_REJECT): "sql txn" meta={id=4bd52e44 key=/Table/95/3/9743 pri=0.04830100 epo=0 ts=1600839484.354878000,0 min=1600839462.660598000,0 seq=98} lock=true stat=PENDING rts=1600839484.354878000,0 wto=false max=1600839463.160598000,0
SQLSTATE: 40001
root@:26257/serial>

```

We got an [ABORT_REASON_CLIENT_REJECT](https://www.cockroachlabs.com/docs/v20.1/transaction-retry-error-reference.html#abort_reason_client_reject) due to a Write/Write conflict with a higher priority transaction.

Let's try with low priority transactions running. Run JMeter with the `update_low` query.

```sql
-- update_low
BEGIN;
SET TRANSACTION PRIORITY LOW;
UPDATE alerts SET cstatus=cstatus, updated_at=NOW()
WHERE customer_id=9743;
COMMIT;
```

While this is running, do the same as test as before in the CLI

```text
root@:26257/defaultdb> use serial;
SET

Time: 421µs

root@:26257/serial> BEGIN;
Now adding input for a multi-line SQL transaction client-side (smart_prompt enabled).
Press Enter two times to send the SQL text collected so far to the server, or Ctrl+C to cancel.
You can also use \show to display the statements entered so far.
                 ->
BEGIN

Time: 192µs

root@:26257/serial  OPEN> UPDATE alerts SET cstatus=cstatus, updated_at=NOW()
WHERE customer_id=9743;
ERROR: restart transaction: TransactionRetryWithProtoRefreshError: TransactionRetryError: retry txn (RETRY_WRITE_TOO_OLD - WriteTooOld flag converted to WriteTooOldError): "sql txn" meta={id=4009f04d key=/Table/95/3/9743 pri=0.00238321 epo=0 ts=1600839787.358442000,1 min=1600839785.348268000,0 seq=98} lock=true stat=PENDING rts=1600839787.358442000,1 wto=false max=1600839785.848268000,0
SQLSTATE: 40001
root@:26257/? ERROR> ROLLBACK;
ROLLBACK

Time: 2.133ms

```

In this case we got a [RETRY_WRITE_TOO_OLD](https://www.cockroachlabs.com/docs/v20.1/transaction-retry-error-reference.html#retry_write_too_old) as another transaction has already committed and thus our write is too old and need to restart.

## Lab 4 - Implicit Transactions with SELECT FOR UPDATE

This final test shows how IMPLICIT transactions perform with SELECT FOR UPDATE. This demo will run two tests and enable / disable SFU for implicit transactions.

In JMeter:

1. Ensure every thread is dead - click the **Shutdown** button if necessary.
2. Ensure the graph is cleared by clicking the **Clear All** button.
3. Update the Database URL by setting `ApplicationName=Demo4`.
4. Disable the **Demo3** test suite and enable **Demo4**.

Make sure the cluster has the SELECT FOR UPDATE setting enabled:

```sql
SET cluster setting sql.defaults.implicit_select_for_update.enabled=true;
```

Run the `update_sfu` transaction with 3 threads for a few minutes.

```sql
-- update_sfu
UPDATE alerts
SET cstatus=cstatus, updated_at=now()
WHERE customer_id=9743;
```

![demo4-jmeter-results-sfu-enabled](media/demo4-jmeter-results-sfu-enabled.png)

Let's try the same test with the SELECT FOR UPDATE setting disabled:

```sql
SET cluster setting sql.defaults.implicit_select_for_update.enabled=false;
```

Re-run the JMeter test, below the results.

![demo4-jmeter-results-sfu-disabled](media/demo4-jmeter-results-sfu-disabled.png)

We can see that with SFU disable, we have much higher latency.
