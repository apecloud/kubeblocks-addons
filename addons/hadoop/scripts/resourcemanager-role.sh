content=$(curl -s http://localhost:8088/isActive)
if [[ "$content" == *"I am Active!"* ]]; then
    echo "active" | tr -d '\n'
elif [[ "$content" == *"405 I am not Active"* ]]; then
    echo "standby" | tr -d '\n'
fi