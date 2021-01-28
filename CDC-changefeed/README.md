# Change Data Capture - Student Labs

## Overview

## Labs Prerequisites

1. Build the single region dev cluster following [these instructions](/infrastructure/single-region-local-docker-cluster.md).

2. You also need:

    - a modern web browser,
    - a SQL client:
      - [Cockroach SQL client](https://www.cockroachlabs.com/docs/stable/install-cockroachdb-linux)
      - `psql`
      - [DBeaver Community edition](https://dbeaver.io/download/) (SQL tool with built-in CockroachDB plugin)

## Lab 0 - Create database and load data

Connect to the database

```bash
# use cockroach sql, defaults to localhost:26257
cockroach sql --insecure

# or use the --url param for any another host:
cockroach sql --url "postgresql://localhost:26257/defaultdb?sslmode=disable"

# or use psql
psql -h localhost -p 26257 -U root defaultdb
```




## Misc Useful Confluent Commands

```bash

# Start Consumer for Avro
./bin/kafka-avro-console-consumer --bootstrap-server localhost:9092 --topic student99_pets

# List Topics
./bin/kafka-topics --list --bootstrap-server localhost:9092

# Delete Topics
./bin/kafka-topics --bootstrap-server localhost:9092 --delete --topic student99_pets

```

## Activity #1 -- Create table, verify settings, create changefeed

```sql
-- Enable rangefeed on CDC cluster
--
SHOW cluster setting kv.rangefeed.enabled;
SET CLUSTER SETTING kv.rangefeed.enabled='true';

-- Connect to your Database
--
use student0;

CREATE TABLE pets (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    person_name string,
    email string,
    pet_name string 
);
```

### Q1
* How do you verify the CHANGEFEED is running?

**Create the changefeed but make sure to change topic_prefix to your database name:**
```sql
-- Connect to your Database
--
use student99;

-- Create CHANGEFEED... set topic_prefix to your database name!!
--
CREATE CHANGEFEED FOR TABLE pets
  INTO 'kafka://10.142.0.109:9092?topic_prefix=student99_'
  WITH updated, resolved='20s',
     confluent_schema_registry = 'http://10.142.0.109:8081',
     format = 'experimental_avro',
     diff,
     schema_change_policy=backfill;
```


## Activity #2 -- Start consumer/sink and insert values

**Connect to Confluent/Kafka machine and run the consumer:**
```bash
## Start a Avro consumer in a SHELL on the kafka cluster
##
ssh -i ./bench-ssh-key bench@35.243.252.96
cd confluent-5.5.0
./bin/kafka-avro-console-consumer --bootstrap-server localhost:9092 --topic student99_pets
```

**From another window, connect to the database and insert some values into the table you created:**
```sql
-- Insert some values to students table
--
INSERT INTO pets (person_name, email, pet_name) VALUES ('Christopher', 'crobin@100acrewoods.com', 'Pooh');	
INSERT INTO pets (person_name, email, pet_name) VALUES ('Christopher', 'crobin@100acrewoods.com', 'Tigger');	
INSERT INTO pets (person_name, email, pet_name) VALUES ('Christopher', 'crobin@100acrewoods.com', 'Piglet');	

INSERT INTO pets (person_name, email, pet_name) VALUES ('Walt', 'walt@disney.com', 'Mickey');	
INSERT INTO pets (person_name, email, pet_name) VALUES ('Walt', 'walt@disney.com', 'Minnie');	

```

### Q2
* What does `{"before": null,` mean?

### Q3
* What columns are sent to the changefeed?

### Q4
* What does the `{"resolved":` timestamp mean?

## Activity #3 -- Add Column for City

```sql
-- Alter table to add City
--
ALTER TABLE pets ADD COLUMN city STRING;

```

### Q5
* What values are submitted to the CHANGEFEED?


## Activity #4 -- Update City values and Observe behavior

```sql

UPDATE pets SET city='Hundred Acre Woods' where person_name='Christopher';
UPDATE pets SET city='Anaheim' where person_name='Walt';

```

### Q6
* What values for **EACH** row are sent to the CHANGEFEED?

### Q7
* What is the `"updated":` value?

### Q8
* How do you create the CHANGEFEED so the **before** value isn't sent?


## Activity #5 -- Cancel and Restart Changefeed with...

This activity will have you cancel the changefeed and restart without the **before** values. 

### Q9
* How do you cancel the running CHANGEFEED?

### Q10
* Show the `CREATE CHANGEFEED` statement such that the **before** values are not included.


## Activity #6 -- Cancel and Restart Changefeed with such that...

This activity will have you cancel the changefeed and restart without the **before** values.  Additionally, the changefeed will be restarted such that changes made before the current timestamp are NOT included.

### Q11
* Show the `CREATE CHANGEFEED` statement such that changes before the current timestamp are NOT included and **before** values are not included.  Test the `CHANGEFEED` by updating and inserting rows to the table.


