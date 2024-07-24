#!/bin/bash


LOG_FILE="/var/log/devopsfetch/devopsfetch.log"

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

monitor() {
    while true; do
        log "INFO" "Running DevOpsFetch"

        log "INFO" "Ports"
        /usr/local/bin/devopsfetch -p 2>&1 | tee -a "$LOG_FILE"

        log "INFO" "Docker"
        /usr/local/bin/devopsfetch -d 2>&1 | tee -a "$LOG_FILE"

        log "INFO" "Nginx"
        /usr/local/bin/devopsfetch -n 2>&1 | tee -a "$LOG_FILE"

        log "INFO" "Users"
        /usr/local/bin/devopsfetch -u 2>&1 | tee -a "$LOG_FILE"

        log "INFO" "---"
        sleep 300  # Run every 5 minutes
    done
}


function display_table() {
    local headers=("${!1}")
    local rows=("${!2}")

    # Calculate column widths
    local col_widths=()
    for header in "${headers[@]}"; do
        col_widths+=(${#header})
    done

    for row in "${rows[@]}"; do
        local cols=()
        eval "cols=(${row})"  # This allows correct parsing of quoted fields
        for i in "${!cols[@]}"; do
            if [ ${#cols[i]} -gt ${col_widths[i]} ]; then
                col_widths[i]=${#cols[i]}
            fi
        done
    done

    # Print headers
    echo -n "+"
    for width in "${col_widths[@]}"; do
        printf '%-*s' "$((width+2))" '' | tr ' ' '-'
        echo -n "+"
    done
    echo

    echo -n "|"
    for i in "${!headers[@]}"; do
        printf " %-*s |" "${col_widths[i]}" "${headers[i]}"
    done
    echo

    echo -n "+"
    for width in "${col_widths[@]}"; do
        printf '%-*s' "$((width+2))" '' | tr ' ' '-'
        echo -n "+"
    done
    echo

    # Print rows
    for row in "${rows[@]}"; do
        echo -n "|"
        local cols=()
        eval "cols=(${row})"  # This allows correct parsing of quoted fields
        for i in "${!cols[@]}"; do
            printf " %-*s |" "${col_widths[i]}" "${cols[i]}"
        done
        echo
    done

    echo -n "+"
    for width in "${col_widths[@]}"; do
        printf '%-*s' "$((width+2))" '' | tr ' ' '-'
        echo -n "+"
    done
    echo
}


# Function to display active ports and services
function active_ports() {
    local headers=("Protocol" "User" "Port" "Service")
    local rows=()
    local found=0

    while IFS= read -r line; do
        protocol=$(echo "$line" | awk '{print $1}')
        port=$(echo "$line" | awk '{print $4}' | awk -F: '{print $2}')
        service=$(sudo lsof -i :"$port" 2>/dev/null | awk 'NR==2 {print $1}')
        user=$(sudo lsof -i :"$port" 2>/dev/null | awk 'NR==2 {print $3}')
        [ -z "$service" ] && service="No service found"
        [ -z "$user" ] && user="Unknown"

        # Filter out entries with "Unknown" values and tcp6/udp6 protocol
        if [ "$port" != "Unknown" ] && [[ "$protocol" != "tcp6" && "$protocol" != "udp6" ]]; then
            rows+=("$protocol $user $port $service")
            found=1
        fi
    done < <(sudo netstat -tuln | awk 'NR>2')

    echo "Listing all active ports and services:"
    if [ "$found" -eq 1 ]; then
        display_table headers[@] rows[@]
    else
        echo "No active ports found."
    fi
}

# Function to display detailed information about a specific port
function port_info() {
    local port_number=$1
    local headers=("Protocol" "User" "Local IP Address" "Port" "Service")
    local rows=()
    local found=0

    while IFS= read -r line; do
        protocol=$(echo "$line" | awk '{print $1}')
        local_address=$(echo "$line" | awk '{print $4}')
        ip_address=$(echo "$local_address" | awk -F: '{print $1}')
        port=$(echo "$local_address" | awk -F: '{print $2}')
        service=$(sudo lsof -i :"$port_number" 2>/dev/null | awk 'NR==2 {print $1}')
        user=$(sudo lsof -i :"$port_number" 2>/dev/null | awk 'NR==2 {print $3}')
        [ -z "$service" ] && service="No service found"
        [ -z "$user" ] && user="Unknown"

        # Filter out tcp6 protocol
        if [[ "$protocol" != "tcp6" && "$protocol" != "udp6" ]]; then
            if [ "$port" == "$port_number" ]; then
                rows+=("$protocol $user $ip_address $port $service")
                found=1
            fi
        fi
    done < <(sudo netstat -tulnp | grep ":$port_number")

    if [ "$found" -eq 1 ]; then
        display_table headers[@] rows[@]
    else
        echo "Error: No service found for the specified port $port_number."
    fi
}

# Function to display Docker images and containers
function docker_info() {
    local images=$(sudo docker images -q)
    local containers=$(sudo docker ps -a -q)

    echo "Docker Images:"
    if [ -n "$images" ]; then
        sudo docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}"
    else
        echo "No images found."
    fi

    echo ""
    echo "Docker Containers:"
    if [ -n "$containers" ]; then
        sudo docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}"
    else
        echo "No containers found."
    fi
}

# Function to display detailed information about a specific Docker container
function docker_container_info() {
    local container_name=$1

    # Get container ID from the name
    local container_id=$(sudo docker ps -a --filter "name=$container_name" --format "{{.ID}}")
    
    if [ -z "$container_id" ]; then
        echo "Error: No container found with the name $container_name."
        return 1
    fi

    local format='ID: {{.Id}}
Image: {{.Config.Image}}
Command: {{.Config.Cmd}}
Created: {{.Created}}
Status: {{.State.Status}}
Ports: {{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostIp}}:{{(index $conf 0).HostPort}} -> {{$p}} {{end}}'

    local output
    output=$(sudo docker inspect --format="$format" "$container_id" 2>&1)

    if [ $? -eq 0 ]; then
        # Extract the creation timestamp
        local created=$(echo "$output" | grep "Created:" | awk -F'Created: ' '{print $2}')

        # Convert timestamp to desired format
        local formatted_created=$(date -d "$created" +"%Y-%m-%d %H:%M:%S %z %Z")

        # Replace the original Created line with the formatted one
        output=$(echo "$output" | sed "s|Created: $created|Created: $formatted_created|")

        echo "$output"
    else
        echo "Error: No container found with the name $container_name."
    fi
}


# Function to display Nginx domains and their ports
function nginx_info() {
    local headers=("Server_Domain" "Proxy" "Configuration File")
    local rows=()
    local found=0

    # Assuming the default nginx configuration directory
    for conf in /etc/nginx/sites-enabled/*; do
        domain=$(basename "$conf")
        proxy=$(grep -oP 'proxy_pass \K[^\;]+' "$conf" | head -1)
        [ -z "$proxy" ] && proxy="N/A"
        rows+=("$domain $proxy $conf")
        found=1
    done

    echo "Listing all Nginx domains and their ports:"
    if [ "$found" -eq 1 ]; then
        display_table headers[@] rows[@]
    else
        echo "No Nginx domains found."
    fi
}


# Function to display detailed Nginx configuration for a specific domain
nginx_domain_info() {
    local domain="$1"
    local conf_file="/etc/nginx/sites-enabled/$domain"

    if [ -f "$conf_file" ]; then
        echo "Detailed Nginx configuration for domain $domain:"

        # Array of directive patterns and their descriptions
        declare -A directives=(
            ["server_name"]="Server Name"
            ["listen"]="Listen"
        )

        while IFS= read -r line; do
            for directive in "${!directives[@]}"; do
                if [[ "$line" == *"$directive"* ]]; then
                    value=$(echo "$line" | awk -F "$directive " '{print $2}')
                    [[ -z "$value" ]] && value="NONE"
                    echo "${directives[$directive]}: $value"
                fi
            done
        done < "$conf_file"
    else
        echo "Error: No configuration file found for the specified domain $domain."
    fi
}

function list_users() {
    local headers=("User" "Last Login")
    local rows=()

    while IFS=':' read -r username _ uid _ _ _ _ shell; do
        if [ "$uid" -ge 1000 ] 2>/dev/null && [ "$shell" != "/usr/sbin/nologin" ] && [ "$shell" != "/bin/false" ]; then
            lastlog_info=$(lastlog -u "$username" | awk 'NR==2 {$1=""; print $0}' | sed 's/^[ \t]*//')
            last_info=$(last -n 1 "$username" | awk 'NR==1 {print $4, $5, $6, $7}')
            
            if [ -z "$lastlog_info" ] || [ "$lastlog_info" = "**Never logged in**" ]; then
                last_login="Never logged in"
            elif [ -n "$last_info" ]; then
                # Format last login date and time
                last_login=$(date -d "$last_info" "+%b %d %Y %H:%M:%S UTC" 2>/dev/null)
            else
                last_login=$(date -d "$lastlog_info" "+%b %d %Y %H:%M:%S UTC" 2>/dev/null)
            fi

            if [ -z "$last_login" ]; then
                last_login="Never logged in"
            fi

            rows+=("$username \"$last_login\"")
        fi
    done < /etc/passwd 2>/dev/null

    echo "Listing all regular users and their last login:"
    display_table headers[@] rows[@]
}



function user_info() {
    local username=$1
    local user_exists=$(getent passwd "$username")

    if [ -n "$user_exists" ]; then
        local uid=$(id -u "$username" 2>/dev/null)
        if [ "$uid" -ge 1000 ] 2>/dev/null; then
            local headers=("Attribute" "Value")
            local rows=()

            local gid=$(id -g "$username" 2>/dev/null)
            local groups=$(groups "$username" 2>/dev/null | cut -d : -f 2-)
            local home=$(getent passwd "$username" | cut -d: -f6)
            local shell=$(getent passwd "$username" | cut -d: -f7)

            local lastlog_info=$(lastlog -u "$username" | awk 'NR==2 {$1=""; print $0}' | sed 's/^[ \t]*//')
            local last_info=$(last -n 1 "$username" 2>/dev/null | awk 'NR==1 {print $4, $5, $6, $7}')

            if [ -z "$lastlog_info" ] || [ "$lastlog_info" = "**Never logged in**" ]; then
                last_login="Never logged in"
            elif [ -n "$last_info" ]; then
                last_login=$(date -d "$last_info" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
            else
                last_login=$(date -d "$lastlog_info" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
            fi

            if [ -z "$last_login" ]; then
                last_login="Never logged in"
            fi

            local terminal=$(last -n 1 "$username" 2>/dev/null | awk 'NR==1 {print $2}')
            [ -z "$terminal" ] && terminal="N/A"

            rows+=("Username $username")
            rows+=("Terminal $terminal")
            rows+=("User_ID $uid")
            rows+=("Group_ID $gid")
            rows+=("Groups \"$groups\"")
            rows+=("Home_Directory $home")
            rows+=("Shell $shell")
            rows+=("Last_Login \"$last_login\"")

            echo "Detailed information for user $username:"
            display_table headers[@] rows[@]
        else
            echo "Error: $username is not a regular user." >&2
        fi
    else
        echo "Error: User $username not found." >&2
    fi
}

filter_logs() {
    local start_date="$1"
    local end_date="$2"

    # Function to validate date format (YYYY-MM-DD)
    validate_date() {
        if ! date -d "$1" "+%Y-%m-%d" >/dev/null 2>&1; then
            echo "Invalid date format. Please use YYYY-MM-DD."
            return 1
        fi
        return 0
    }

    # Check if start date is provided
    if [ -z "$start_date" ]; then
        echo "Please specify at least a start date (YYYY-MM-DD)"
        return 1
    fi

    # Validate the start date format
    if ! validate_date "$start_date"; then
        return 1
    fi

    # If end date is not provided, set it to start date
    if [ -z "$end_date" ]; then
        end_date="$start_date"
    fi

    # Validate the end date format
    if ! validate_date "$end_date"; then
        return 1
    fi
    
    # Convert dates to the format journalctl expects
    local start_time="${start_date} 00:00:00"
    local end_time="${end_date} 23:59:59"

    echo "Displaying system logs from $start_time to $end_time"

    # Use journalctl to display logs within the specified time range
    if ! journalctl --since "$start_time" --until "$end_time"; then
        echo "Error occurred while fetching logs."
        echo "Available log range:"
        journalctl --list-boots
    fi
}




# Function to display help message
function display_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -p, --port             Display all active ports and services in a table"
    echo "  -p <port_number>       Provide detailed information about a specific port"
    echo "  -d, --docker           List all Docker images and containers"
    echo "  -d <container_name>    Provide detailed information about a specific container"
    echo "  -n, --nginx            Display all Nginx domains and their ports"
    echo "  -n <domain>            Provide detailed configuration information for a specific domain"
    echo "  -h, --help             Show this help message and exit"
    echo "  -u, --users            List all regular users and their login information"
    echo "  -u <username>          Provide detailed information about a specific user"
    echo "  -t, --time             [START_DATE END_DATE] Display activities within a specified time range"
}

# Parse command-line arguments
if [ "$#" -eq 0 ]; then
    display_help
    exit 0
fi


while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--port)
            if [[ -n $2 && $2 != -* ]]; then
                port_info "$2"
                shift 2
            else
                active_ports
                shift
            fi
            ;;
        -d|--docker)
            if [[ -n $2 && $2 != -* ]]; then
                docker_container_info "$2"
                shift 2
            else
                docker_info
                shift
            fi
            ;;
        -n|--nginx)
            if [[ -n $2 && $2 != -* ]]; then
                nginx_domain_info "$2"
                shift 2
            else
                nginx_info
                shift
            fi
            ;;
        -u|--users)
            if [[ -n $2 && $2 != -* ]]; then
                user_info "$2"
                shift 2
            else
                list_users
                shift
            fi
            ;;
        -t|--time)
            if [ -z "$2" ]; then
                echo "Please specify at least a start date (YYYY-MM-DD)"
            else
                filter_logs "$2" "$3"
            fi
            ;;
        -h|--help)
            display_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            display_help
            exit 1
            ;;
    esac
done