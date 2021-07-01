#!/bin/sh
# Stop docker containers for CockroachDB topology workshop
echo "removing docker resources..."
<<<<<<< HEAD
for i in newyork
=======
spin
for i in seattle newyork london
>>>>>>> ca6ca061470ddf0172abb6e6d06aba894bed6856
do
    for j in 1 2 3
    do
        docker stop roach-$i-$j
        docker rm roach-$i-$j
        docker volume rm roach-$i-$j-data
    done
done
<<<<<<< HEAD
=======
docker stop haproxy-london
docker rm haproxy-london
docker stop haproxy-seattle
docker rm haproxy-seattle
>>>>>>> ca6ca061470ddf0172abb6e6d06aba894bed6856
docker stop haproxy-newyork
docker rm haproxy-newyork
docker network rm us-east-1-net us-west-2-net eu-west-1-net uswest-useast-net useast-euwest-net uswest-euwest-net