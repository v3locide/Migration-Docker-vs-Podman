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
host_user="host"
target_user="target" #"target"
host_port=2222 #22 #2222
iperf_port=12345
app_port=8081
container_port=80

# Delete old containers
if docker images | grep "$container_image"; then
    echo "deleting old containers and cached images..."
    docker stop $container_name
    docker system prune -a
    sudo rm -fr target_stats.txt $container_name-checkpoint.zip  tmp
    echo ""
fi

# Step 0: Build the image:
echo "Building image..."
echo ""
img_build_start=$(date)
# Convert the timestamp to seconds since the Unix epoch
img_build_start_seconds=$(date -d "$img_build_start" +%s)
docker build -t $container_image $dockerfile
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
        scp -P $host_port $host_user@$host_server:/home/$host_user/$container_name-checkpoint.zip /home/$target_user/
        pkill iperf
        break
    fi
done

# Step 2: unzip checkpoint and create the new container from the checkpoint
sudo unzip $container_name-checkpoint.zip -d tmp/
docker create -p $app_port:$container_port --name $container_name $container_image
sudo mv tmp/$container_name-checkpoint /var/lib/docker/containers/$(docker ps -aq --no-trunc --filter name=$container_name)/checkpoints/
docker start --checkpoint $container_name-checkpoint $container_name
# Wait for the container to start"
while true; do
    if docker ps | grep "$container_name" | grep "Up"; then
        timestamp=$(date)
        # Convert the timestamp to ms since the Unix epoch
        timestamp_ms=$(date -d "$timestamp" +%s%3N)
        break
    fi
done

# Save container and checkpoint size
container_size=$(sudo ls -lh /var/lib/docker/containers/$(docker ps -aq --no-trunc --filter name=$container_name)/ | awk 'NR==1 {print $2}')

checkpoint_size=$(sudo ls -lh /var/lib/docker/containers/$(docker ps -aq --no-trunc --filter name=$container_name)/checkpoints/$container_name-checkpoint | awk 'NR==1 {print $2}')


echo "Migration end: $timestamp"
echo ""
echo "Started container $container_name"
docker ps | grep "$container_name"
echo ""
sleep 2
echo "Container logs:"
docker logs $container_name
echo ""

# Step 3: Let the container run for 30 seconds
sleep 50 &

# Step 4: Monitor and capture the highest CPU and memory usage
echo "Capturing CPU and memory usage for $container_name container..."
echo""

while kill -0 $! 2>/dev/null; do
    
    # Capture target_stats for the container
    target_stats=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" $container_name)
    
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
echo "Container Folder Size: $container_size" >> target_stats.txt
echo "Checkpoint Folder Size: $checkpoint_size" >> target_stats.txt

# Save the migration end time
echo "Migration end: $timestamp (${timestamp_ms}ms)" >> target_stats.txt

# Step 6: output the calculated metrics
echo "Calculated metrics:"
cat target_stats.txt
sleep 1
echo ""

# Done
echo "All tasks completed successfully!"


# Note: the container size difference between the host and target
# is due to the container log file being smaller at the start of
# the container in the target server.
