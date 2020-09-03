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


## Command Crib Sheet

https://github.com/glennfawcett/roachcrib



## Activity #1 -- Explore Range distribution
Connect via SQL to answer the questions regarding the **RANGE** distribution of various objects.

SQL to show **range** distribution and showing only needed data: 
```sql
SELECT start_key, lease_holder, lease_holder_locality, replicas
  FROM [SHOW RANGES FROM TABLE rides]
    WHERE "start_key" IS NOT NULL
    AND "start_key" NOT LIKE '%Prefix%';
```

### Q1 
* How are the ranges distributed in the "rides" table?

### Q2
* How are indexes on the "rides" table distributed?

## Activity #2 -- Partition the rides table
Partition the "rides" table in your database by **city** to the approiate regions.

### Q3
* What is the DDL used to partition the "rides" table? 

### Q4
* How are ranges distributed after *partitioning*?

## Activity #3 -- Pin partitions to survive region failure
This activity will have you using `ALTER PARTITION` to pin partitions to regions to match the cities.  The `lease_preferences` will be set to the target region and the `constaints` will be set to require **one** replica in the same region as the lease holder.

### Q5
* What is the DDL used to Pin the partitions?

### Q6
* How are the ranges distributed in the `rides` table after *pinning*?

### Q7
* How are the ranges distributed in the `rides` table after 5 minutes?

## Activity #4 -- Run Queries across ALL regions
Experiment running the same queries in **ALL** regions and observe the behaviour.

Connect to with separate SQL connections to **us_west1**, **us_east4** and **europe_west2** regions.  Run the following queries in each:

```sql
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

### Q8
* How do the repsonse times compare?

### Q9
* How do you show the expected time differences due to Network Latency?



