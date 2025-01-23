#!/bin/bash

# Init
top_cpu=0
top_mem=0
top_mem_unit=""
top_mem_percent=0
total_cpu=0
total_mem=0
total_mem_percent=0
checkpoint_size="null"
container_size="null"
iteration=0
container_name="vite-app" #"looper" #"vite-app"
target_server="192.168.50.12"
host_server="26.211.193.71" #"26.91.161.197" #"192.168.50.11"
container_image="vite-app-img" #"busybox" #"vite-app-img"
dockerfile=~/app/.
iperf_port=12345

# Delete old containers
if podman images | grep "$container_image"; then
    echo "deleting old containers and cached images..."
    podman stop $container_name
    podman system prune -a
    sudo rm -fr target_stats.txt $container_name-checkpoint.tar.gz
    echo ""
fi

# Step 0: Build the image:
echo "Building image..."
echo ""
img_build_start=$(date)
# Convert the timestamp to seconds since the Unix epoch
img_build_start_seconds=$(date -d "$img_build_start" +%s)
podman build -t $container_image $dockerfile
#podman pull docker.io/velocide/$container_image
img_build_end=$(date)
img_build_end_seconds=$(date -d "$img_build_end" +%s)
img_build_time=$((img_build_end_seconds - img_build_start_seconds))
echo "Image build time: ${img_build_time}s" > target_stats.txt
echo ""

# Step 1: start iperf server on target server
echo "Starting iperf server on target..."
sleep 1
iperf -s -i 1 -B "$target_server" --port "$iperf_port" | while read -r line; do
    echo "$line"
    if echo "$line" | grep -q "local $target_server port $iperf_port connected with $host_server"; then
        pkill iperf
        break
    fi
done

# Step 2: restart container from checkpoint
podman container restore -i $container_name-checkpoint.tar.gz --log-level debug
# Wait for the container to start"
while true; do
    if podman ps | grep "$container_name" | grep "Up"; then
        timestamp=$(date)
        # Convert the timestamp to ms since the Unix epoch
        timestamp_ms=$(date -d "$timestamp" +%s%3N)
        break
    fi
done

# Save container and checkpoint size
container_size=$(sudo ls -lh $(podman inspect $container_name --format '{{.GraphDriver.Data.UpperDir}}' | sed 's/\/diff$//') | awk {'print $2'} | head -n 1)

checkpoint_size=$(ls -lh | grep $container_name-checkpoint.tar.gz | awk {'print $5'})


echo "Migration end: $timestamp"
echo ""
echo "Started container $container_name"
podman ps | grep "$container_name"
echo ""
sleep 2
echo "Container logs:"
podman logs $container_name
echo ""

# Step 3: Let the container run for 30 seconds
sleep 10 &

# Step 4: Monitor and capture the highest CPU and memory usage
echo "Capturing CPU and memory usage for $container_name container..."
echo""

while kill -0 $! 2>/dev/null; do
    
    # Capture target_stats for the container
    target_stats=$(podman stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" $container_name)
    
    if [[ -z "$target_stats" ]]; then
        continue  # Skip iteration if target_stats are empty
    fi
    
    # Extract CPU and memory values
    cpu=$(echo "$target_stats" | awk -F',' '{print $1}' | tr -d '%')
    echo "CPU usage: $cpu%"
    mem=$(echo "$target_stats" | awk -F',' '{print $2}' | awk '{print $1}')
    mem_percent=$(echo "$target_stats" | awk -F',' '{print $3}' | tr -d '%')
    echo "Mem usage: $mem ($mem_percent%)"
    
    mem_value=$(echo "$mem" | sed 's/[a-zA-Z]//g' | awk '{print $1}')
    mem_unit=$(echo "$mem" | sed 's/[0-9]//g')  # Extracts the unit (e.g., KiB, MiB)
    
    # Check if current CPU is higher than top_cpu
    if (( $(echo "$cpu > $top_cpu" | bc -l) )); then
        top_cpu=$cpu
    fi
    
    # Check if current memory is higher than top_mem
    if (( $(echo "$mem_value > $top_mem" | bc -l) )); then
        top_mem=$mem_value
        top_mem_unit=$mem_unit
    fi
    
    # Check if current Mem% is higher than top_mem_percent
    if (( $(echo "$mem_percent > $top_mem_percent" | bc -l) )); then
        top_mem_percent=$mem_percent
    fi
    
    # Accumulate values for averages
    total_cpu=$(echo "$total_cpu + $cpu" | bc -l)
    total_mem=$(echo "$total_mem + $mem_value" | bc -l)
    total_mem_percent=$(echo "$total_mem_percent + $mem_percent" | bc -l)
    iteration=$((iteration + 1))
    echo "Iteration: $iteration"
    echo ""
    sleep 1
done

# Step 5: calculate the metrics:
# Calculate the average CPU and memory usage
if [ $iteration -gt 0 ]; then
    avg_cpu=$(echo "scale=2; $total_cpu / $iteration" | bc -l)
    avg_mem=$(echo "scale=2; $total_mem / $iteration" | bc -l)
    avg_mem_percent=$(echo "scale=2; $total_mem_percent / $iteration" | bc -l)
else
    avg_cpu=0
    avg_mem=0
    avg_mem_percent=0
fi

# Ensure that averages less than 1% display as 0.XX
avg_cpu=$(printf "%.2f" "$avg_cpu")
avg_mem=$(printf "%.2f" "$avg_mem")
avg_mem_percent=$(printf "%.2f" "$avg_mem_percent")

# Save CPU and memory usage values to a target_stats file
echo "Highest CPU usage: $top_cpu%" >> target_stats.txt
echo "Highest Memory usage: $top_mem$top_mem_unit ($top_mem_percent%)" >> target_stats.txt
echo "Average CPU usage: $avg_cpu%" >> target_stats.txt
echo "Average Memory usage: $avg_mem$top_mem_unit ($avg_mem_percent%)" >> target_stats.txt

# Save container and checkpoint size in target_stats
echo "Container Size: $container_size" >> target_stats.txt
echo "Checkpoint Size: $checkpoint_size" >> target_stats.txt

# Save the migration end time
echo "Migration end: $timestamp (${timestamp_ms}ms)" >> target_stats.txt

# Step 6: output the calculated metrics
echo "Calculated metrics:"
cat target_stats.txt
sleep 1
echo ""

# Done
echo "All tasks completed successfully!"
