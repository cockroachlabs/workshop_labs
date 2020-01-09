# Lab1 Geo Partitioning

In this lab we will experiment with Geo Partitioning to best 
undstand how to observe and partition and pin the data.


## Connecting to CRDB

* DBeaver
* ./cockroach sql --insecure
* psql 

## Connect Info Sheet

*Student, Database, pgurl, adminurl*


## Cluster Configuration
The lab cluster is configured in Google Clould using the following zones:

* us-west1-b
* us-east4-b
* europe-west2-a 


## Command Crib Sheet

https://github.com/glennfawcett/roachcrib



## Questions

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
How do you force re-distribution?

-- Q3d
-- 
How are the ranges distributed in the `rides` table after 10 minutes?

-- Q4
--
Query within all regions

-- Q4a
--
What is the repsonse time of the following queries?

```
select locality, rides.* from rides, [show locality] where id = '2ce831ad-2135-4a00-8000-00000001569d' and city = 'boston';

select locality, rides.* from rides, [show locality] where id = '60b65237-0479-4c00-8000-00000002e1db' and city = 'seattle';

select locality, rides.* from rides, [show locality] where id = 'c71d6063-1726-4000-8000-00000005ef20' and city = 'paris';
```

-- Q4b
--
Connect to multiple localities and run the SAME query from each region.

* How do the response times compare?



