
clusterName=$1
commands=()
commands+=("cp /data/nodes.conf /data/nodes.conf.bak")
for pod in `kubectl get pods -l app.kubernetes.io/instance=$clusterName -o jsonpath='{.items[*].metadata.name}'`
do
  myself=`kubectl exec -it $pod -c kbagent -- bash -c "cat /data/nodes.conf | grep myself"`
  node_id=`echo $myself | awk '{print $1}'`
  node_ip_info=`echo $myself | awk '{print $2}'`
  node_ip_port=`echo $node_ip_info | awk  -F ',' '{print $1}'`
  commands+=("sed -i 's/\(^.* \)[^,]\+\(,$pod\.\)/\1$node_ip_port\2/' /data/nodes.conf")
done

echo "Command to execute:"
printf '%s\n' "${commands[@]}"

cmd=`printf '%s\n' "${commands[@]}"`
for pod in `kubectl get pods -l app.kubernetes.io/instance=$clusterName -o jsonpath='{.items[*].metadata.name}'`
do
  echo "Processing pod: $pod"
  kubectl exec -it $pod -c kbagent -- bash -c "$cmd"
  echo "Processing done"
done