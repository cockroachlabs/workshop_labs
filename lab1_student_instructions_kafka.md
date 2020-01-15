# Lab1 Kafa Usage Workshop

In this lab we will experiment with Kafka CDC out of CockroachDB.


## Connecting to CRDB

* DBeaver
* ./cockroach sql --insecure
* psql

## Connect Info Sheet

*Student, Database, pgurl, adminurl*


## Cluster Configuration
The lab cluster is configured in Google Clould in a singe zone:

* us-east4-b


## Command Crib Sheet

https://github.com/glennfawcett/roachcrib



## Instructor Activity

The Instructor will create a Table and CDC feed.

*INSTRUCTOR WILL DO THIS!!*

```
CREATE TABLE students (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    name string,
    email string,
    pets string 
);

CREATE CHANGEFEED FOR TABLE students
  INTO 'kafka://10.142.0.55:9092'
  WITH updated, resolved;
```

Instructor will create runn a sink that will reall ALL messages from the Kafka stream and topic for the `students` table.  This will be monitored while the students input data.

## Student Activity

Please insert your record into the students table.  Put your chosen name, email, and the names of your pets.

```
INSERT INTO students (name, email, pets) VALUES ('your_name', 'your_email@corelogic.com', 'pet1_pet2');	
```

Feel free to insert other persons if you wish.  Feel free to UPDATE your pets as you get more critters.
```
UPDATE students set pets='digger_diego_maverick_max' where name='yourname';
```

