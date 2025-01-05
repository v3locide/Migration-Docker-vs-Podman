#!/bin/sh

# Example CPU-intensive task: endless loop doing calculations to increase CPU usage.

echo "Starting nginx server in the background..."
nginx -g 'daemon off;' &
sleep 1

count=0
while true; do
    echo "Performing CPU-intensive task: $count"
    for i in $(seq 1 100000); do
        : $((i * i))
    done
    count=$((count + 1))
    sleep 1
done
