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
host_server=192.168.50.11 #192.168.50.12 #192.168.50.11
target_server=26.211.193.71 #192.168.50.12 #26.211.193.71
container_image="vite-app-img" #"busybox" #"vite-app-img"
dockerfile=~/app/.
iperf_port=12345
app_port=8080
container_port=80

# Delete old containers
if docker images | grep "$container_image"; then
    echo "deleting old containers and cached images..."
    docker stop $container_name
    docker system prune -a
    sudo rm -fr host_stats.txt  $container_name-checkpoint  $container_name-checkpoint.zip
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
echo "Image build time: ${img_build_time}s" > host_stats.txt
echo ""

# Step 1: Run the Docker container
echo "Starting container..."
#busybox:
#docker run -d --rm --name $container_name $container_image /bin/sh -c 'i=0; while true; do echo $i; i=$(expr $i + 1); sleep 3; done'
#frontend-app:
docker run -p $app_port:$container_port -d --name $container_name $container_image
docker ps | grep "$container_name"
echo ""
echo "Container logs:"
docker logs $container_name
echo ""

# Step 2: Let the container run for 50 seconds
sleep 50 &

# Step 3: Monitor and capture the highest CPU and memory usage
echo "Capturing CPU and memory usage for $container_name container..."
echo""

while kill -0 $! 2>/dev/null; do
    
    # Capture host_stats for the container
    host_stats=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" $container_name)
    
    if [[ -z "$host_stats" ]]; then
        continue  # Skip iteration if host_stats are empty
    fi
    
    # Extract CPU and memory values
    cpu=$(echo "$host_stats" | awk -F',' '{print $1}' | tr -d '%')
    echo "CPU usage: $cpu%"
    mem=$(echo "$host_stats" | awk -F',' '{print $2}' | awk '{print $1}')
    mem_percent=$(echo "$host_stats" | awk -F',' '{print $3}' | tr -d '%')
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

# Step 4: Start the migration
echo "Press [Enter] to start the migration:"
# Wait for the user to press Enter
read

echo "Starting the migration..."
sleep 2

#Store the migration start time in a variable
timestamp=$(date)
# Convert the timestamp to ms since the Unix epoch
timestamp_ms=$(date -d "$timestamp" +%s%3N)
echo "Migration start: $timestamp"
echo ""

# Step 5: Create a Docker checkpoint
docker checkpoint create --checkpoint-dir $HOME/ $container_name $container_name-checkpoint

# Step 6: Zip the checkpoint directory
cd $HOME/
sudo zip -9 -r $container_name-checkpoint.zip $container_name-checkpoint
echo ""

# Step 7: notify target server (with iperf messages)
echo "Notifying the target server..."
iperf -i 1 -B $host_server -c $target_server -t 3 --port $iperf_port -b 10M
echo ""

# Step 8: calculate the metrics:
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

# Save CPU and memory usage values to a host_stats file
echo "Highest CPU usage: $top_cpu%" >> host_stats.txt
echo "Highest Memory usage: $top_mem$top_mem_unit ($top_mem_percent%)" >> host_stats.txt
echo "Average CPU usage: $avg_cpu%" >> host_stats.txt
echo "Average Memory usage: $avg_mem$top_mem_unit ($avg_mem_percent%)" >> host_stats.txt

# Save checkpoint and container size to same host_stats file
container_size=$(sudo ls -lh /var/lib/docker/containers/$(docker ps -aq --no-trunc --filter name=$container_name)/ | awk 'NR==1 {print $2}')
echo "Container Folder Size: $container_size" >> host_stats.txt

checkpoint_size=$(sudo ls -lh $HOME/$container_name-checkpoint | awk 'NR==1 {print $2}')
echo "Checkpoint Folder Size: $checkpoint_size" >> host_stats.txt

# Save the migration start
echo "Migration start: $timestamp (${timestamp_ms}ms)" >> host_stats.txt

# Remove stopped container
docker stop $container_name && docker rm $container_name >> /dev/null

# Step 9: Output the calculated metrics
echo "Calculated metrics:"
cat host_stats.txt
sleep 1
echo ""

# Done
echo "All tasks completed successfully!"