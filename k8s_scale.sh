#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display usage information
usage() {
    echo "Usage:"
    echo "  $0 scale-down [namespace] [output_file]"
    echo "  $0 restore [input_file]"
    echo ""
    echo "Arguments:"
    echo "  scale-down : Scale down Deployments and StatefulSets to 0 replicas."
    echo "  restore    : Restore Deployments and StatefulSets from the saved file."
    echo "  namespace  : (Optional) Kubernetes namespace. Default is 'default'."
    echo "  output_file: (Required for scale-down) File to save the current state."
    echo "  input_file : (Required for restore) File containing the saved state."
    exit 1
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null
then
    echo "kubectl could not be found. Please install it to use this script."
    exit 1
fi

# Ensure at least one argument is provided
if [ $# -lt 1 ]; then
    usage
fi

ACTION=$1

case "$ACTION" in
    scale-down)
        # Default namespace
        NAMESPACE="default"
        OUTPUT_FILE="scaled_resources.txt"

        # Parse arguments
        if [ $# -ge 2 ]; then
            NAMESPACE=$2
        fi
        if [ $# -ge 3 ]; then
            OUTPUT_FILE=$3
        fi

        echo "Scaling down Deployments and StatefulSets in namespace '$NAMESPACE'..."
        echo "Saving current replica counts to '$OUTPUT_FILE'..."

        # Initialize or empty the output file
        > "$OUTPUT_FILE"

        # Function to scale resources
        scale_resources() {
            local kind=$1
            # Get all resources of the specified kind in the namespace
            kubectl get "$kind" -n "$NAMESPACE" -o json | jq -c '.items[]' | while read -r item; do
                name=$(echo "$item" | jq -r '.metadata.name')
                replicas=$(echo "$item" | jq -r '.spec.replicas // 1') # Default to 1 if replicas not set
                echo "$kind|$name|$NAMESPACE|$replicas" >> "$OUTPUT_FILE"
                echo "Scaling down $kind '$name' from $replicas replicas to 0."
                kubectl scale "$kind" "$name" --replicas=0 -n "$NAMESPACE"
            done
        }

        # Check if jq is installed
        if ! command -v jq &> /dev/null
        then
            echo "jq could not be found. Please install it to use this script."
            exit 1
        fi

        # Scale Deployments
        scale_resources "deployments"

        # Scale StatefulSets
        scale_resources "statefulsets"

        echo "Scale-down completed. Original replica counts saved to '$OUTPUT_FILE'."

        ;;

    restore)
        # Check if input file is provided
        if [ $# -lt 2 ]; then
            echo "Error: Missing input_file for restore."
            usage
        fi

        INPUT_FILE=$2

        if [ ! -f "$INPUT_FILE" ]; then
            echo "Error: File '$INPUT_FILE' does not exist."
            exit 1
        fi

        echo "Restoring Deployments and StatefulSets from '$INPUT_FILE'..."

        while IFS='|' read -r kind name namespace replicas; do
            echo "Restoring $kind '$name' in namespace '$namespace' to $replicas replicas."
            kubectl scale "$kind" "$name" --replicas="$replicas" -n "$namespace"
        done < "$INPUT_FILE"

        echo "Restore completed."

        ;;

    *)
        echo "Error: Unknown action '$ACTION'."
        usage
        ;;
esac
