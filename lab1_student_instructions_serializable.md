# Lab Coding Serializable Transactions Workshop

In this lab we will explore how to best use Serializable transactions with CockroachDB.

## Lab configurations
This lab is meant to done by developers, architectects, and administrators on their own. 
The presentation had several DEMOs which covered various topics important to coding with Serializable transactions.
Labs were peformed on a local Laptop "2018 Macbook Pro" using Jmeter to drive the varios transaction types.

You can create a similar enviornment on your laptop or use clusters in the cloud. I have included the JMETER file as an 
example but you are welcome to use other benchmarking tools or your own code. 

I encourage you to code in your language of choice to drive the transactions.  This will help to better cement these
concepts and make them second nature as you code and tune.

## Example Configuration
The presentation was done with the following:
* MacBook Pro 15" 2018 with 6 cores and 32GB RAM
* 3 node CRDB cluster

To install cockroachdb locally using one of the following methods:
**Downloads:**
* [mac brew install](https://www.cockroachlabs.com/docs/v20.1/install-cockroachdb-mac)
* [linux download](https://www.cockroachlabs.com/docs/v20.1/install-cockroachdb-linux)
* [windows download](https://www.cockroachlabs.com/docs/v20.1/install-cockroachdb-windows)

**Start Local Cluster:**
* [local cluster](https://www.cockroachlabs.com/docs/v20.1/start-a-local-cluster)
* [single node cluster](https://www.cockroachlabs.com/docs/stable/cockroach-start-single-node.html#insecure)

## JMETER 
I used Jmeter with the version 5.2.1 but newer versions should be fine.

**Install Instructions:**
* [Mac](https://medium.com/@sdanerib/run-jmeter-with-plugins-in-macos-8a6654fc0b38)
* [Windows](https://medium.com/@taufiq_ibrahim/installing-apache-jmeter-on-windows-10-62b7f53841f)
* [Linux](https://linuxhint.com/install_apache_jmeter_ubuntu/)

Once you have jmeter installed, you will need to add the following plugins and download the jmx file: 
* [plug-ins](/serial/jmeter_plugins.png)
* [JMX](/serial/Serializable_Workshop_Demo.jmx)


## Database Configuration
Run the following to create the test database and populate the table for the tests:

```sql
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
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    INDEX alerts_i_idx_1 (cstatus ASC, customer_id ASC, id1 ASC, severity ASC),
    INDEX alerts_i_idx_2 (customer_id ASC, id1 ASC, id1_desc ASC, id2 ASC),
    INDEX alerts_i_idx_3 (id2 ASC, id2_desc ASC, cstatus ASC)
);

insert into alerts
select 
a,
round(random()*10000)::INT,
'ALERT_TYPE',
round(random()*10)::INT,
concat('STATUS-',round(random()*10)::STRING),
'ADESC',
round(random()*1000)::INT,
'ID1_DESCRIPTION',
round(random()*5000)::INT,
'ID2_DESCRIPTION',
now(),
now()
from generate_series(1,1000000) as a;
```

You should now be ready to run the various scenarios to show the various demos covered in the presentation.
Below, I will describe the setup, transactions, and number of threads used to simulate the various scenarios.
With this, you should be able to use the JMETER setup, generate the test code, or use another test tool 
to drive the cluster and experiment with serializable transactions.

## LAB TEST Scenarios
The following test scenarios are described below:
* Contention with Selects and Updates
* Bulk Updates disturbing Select performance
* Retries with Updates
* Implicit Transactions /w Select for Update (SFU)

### Demo #1 :: Contention with Selects and Updates
This test is to show the performance difference of various queries while running **updates** 
on the same set of rows... a tourture test.  If you are using Jmeter, it is marked as DEMO#1.

There are 5 total selects run with 4 of them quering the same rows that are being updated
and one that is querying a different set of rows as a baseline for no-contention.  The queries
as well as the update were all run in a thread group with 6 threads.  Feel free to experiment with 
the number of theads driving the workload based on your cluster configuration.

```sql
-- select_high
--
BEGIN;
  SET TRANSACTION PRIORITY HIGH;
  SELECT * FROM alerts WHERE customer_id=9743;
COMMIT;

-- select_low
--
BEGIN;
  SET TRANSACTION PRIORITY LOW;
  SELECT * FROM alerts WHERE customer_id=9743;
COMMIT;

-- select_normal
--
BEGIN;
  SELECT * FROM alerts WHERE customer_id=9743;
COMMIT;

-- select_follower_read (implicit)
--
SELECT * FROM alerts  as of system time experimental_follower_read_timestamp()
WHERE customer_id=9743;

-- select_normal_different_id
--
SELECT * FROM alerts 
WHERE customer_id=9800;
```

The following UPDATE was RUN along with the queries:

```sql
BEGIN;

SET TRANSACTION PRIORITY LOW;
-- SET TRANSACTION PRIORITY HIGH;

  UPDATE alerts SET cstatus=cstatus, updated_at=now() 
  WHERE customer_id=9743;

COMMIT;
```

**QUESTION:** What are your observations?


