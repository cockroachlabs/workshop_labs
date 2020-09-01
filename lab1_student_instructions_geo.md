# Lab1 Geo Partitioning

In this lab we will experiment with Geo Partitioning to best 
understand how to observe and partition and pin the data.


## Connecting to CRDB

* DBeaver
* ./cockroach sql --insecure
* psql 

## Connect Info Sheet

*Student, Database, pgurl, adminurl*


## Cluster Configuration
The lab cluster is configured in Google Clould using the following regions:

* us-west1
* us-east4
* europe-west2

## Admin URL

* See the sheet providied for connectivity information


## Command Crib Sheet

https://github.com/glennfawcett/roachcrib



## Activities & Questions

--  Q1 
--
How are the ranges distributed in the "rides" table?

-- Q2
--
What Cities are part of the "movr" application?  
What are the count of the RIDES from each city in the rides table?

-- Q3a
--
Partition the "rides" table in your database

* What is the DDL? 
* How are ranges distributed after *partitioning*?

-- Q3b
--
Pin the partitions such that the database can survive a region failure.

* What is the DDL?
* How are the ranges distributed after *pinning*?

-- Q3c  
-- 
How are the ranges distributed in the `rides` table after 5 minutes?

-- Q4
--
Experiment running the same queries in **ALL** regions

-- Q4a
--
Connect to **us_west1** region and run the following queries:

```
SELECT locality, rides.* 
FROM rides, [show locality] 
WHERE id = '60b65237-0479-4c00-8000-00000002e1db' 
AND city = 'seattle';

SELECT locality, rides.* 
FROM rides, [show locality] 
WHERE id = '2ce831ad-2135-4a00-8000-00000001569d' 
AND city = 'boston';

SELECT locality, rides.* 
FROM rides, [show locality] 
WHERE id = 'c71d6063-1726-4000-8000-00000005ef20' 
AND city = 'paris';
```

What is the repsonse time of the above queries?

-- Q4b
--
Connect to **us_east4** and **europe_west2** localities and run the queries from Q4a again.

* How do the response times compare?



