#!/bin/bash

# Elasticsearch Agent Build Script

set -e

# Configuration
IMAGE_REGISTRY=${IMAGE_REGISTRY:-"apecloud"}
IMAGE_NAME=${IMAGE_NAME:-"elasticsearch-agent"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
FULL_IMAGE_NAME="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        echo_error "Docker daemon is not running"
        exit 1
    fi
}

# Check Go modules
check_go_modules() {
    if [ ! -f "go.mod" ]; then
        echo_error "go.mod not found. Please run this script from the agent directory."
        exit 1
    fi
    
    if [ ! -f "main.go" ]; then
        echo_error "main.go not found. Please run this script from the agent directory."
        exit 1
    fi
}

# Build image
build_image() {
    echo_info "Building Docker image: ${FULL_IMAGE_NAME}"
    
    # Create temporary go.sum file if it doesn't exist
    if [ ! -f "go.sum" ]; then
        echo_warn "go.sum not found, creating empty file"
        touch go.sum
    fi
    
    docker build -t "${FULL_IMAGE_NAME}" .
    
    if [ $? -eq 0 ]; then
        echo_info "Successfully built image: ${FULL_IMAGE_NAME}"
    else
        echo_error "Failed to build image"
        exit 1
    fi
}

# Push image
push_image() {
    echo_info "Pushing Docker image: ${FULL_IMAGE_NAME}"
    
    docker push "${FULL_IMAGE_NAME}"
    
    if [ $? -eq 0 ]; then
        echo_info "Successfully pushed image: ${FULL_IMAGE_NAME}"
    else
        echo_error "Failed to push image"
        exit 1
    fi
}

# Show help information
show_help() {
    cat << EOF
Elasticsearch Agent Build Script

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    build       Build the Docker image (default)
    push        Build and push the Docker image
    help        Show this help message

Options:
    -r, --registry REGISTRY    Set image registry (default: apecloud)
    -n, --name NAME           Set image name (default: elasticsearch-agent)
    -t, --tag TAG             Set image tag (default: latest)

Environment Variables:
    IMAGE_REGISTRY            Image registry (default: apecloud)
    IMAGE_NAME               Image name (default: elasticsearch-agent)
    IMAGE_TAG                Image tag (default: latest)

Examples:
    $0                        # Build image with default settings
    $0 build                  # Same as above
    $0 push                   # Build and push image
    $0 -r myregistry -t v1.0.0 push  # Build and push with custom registry and tag

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--registry)
                IMAGE_REGISTRY="$2"
                FULL_IMAGE_NAME="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                shift 2
                ;;
            -n|--name)
                IMAGE_NAME="$2"
                FULL_IMAGE_NAME="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                shift 2
                ;;
            -t|--tag)
                IMAGE_TAG="$2"
                FULL_IMAGE_NAME="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                shift 2
                ;;
            build)
                COMMAND="build"
                shift
                ;;
            push)
                COMMAND="push"
                shift
                ;;
            help|--help|-h)
                show_help
                exit 0
                ;;
            *)
                echo_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    local COMMAND="build"
    
    parse_args "$@"
    
    echo_info "Starting Elasticsearch Agent build process"
    echo_info "Registry: ${IMAGE_REGISTRY}"
    echo_info "Image Name: ${IMAGE_NAME}"
    echo_info "Tag: ${IMAGE_TAG}"
    echo_info "Full Image Name: ${FULL_IMAGE_NAME}"
    echo_info "Command: ${COMMAND}"
    echo ""
    
    check_docker
    check_go_modules
    
    case $COMMAND in
        build)
            build_image
            ;;
        push)
            build_image
            push_image
            ;;
        *)
            echo_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
    
    echo_info "Build process completed successfully!"
}

# Run main function
main "$@"
