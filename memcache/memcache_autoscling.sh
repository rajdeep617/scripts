date >> /tmp/scaling_log
exec &>> /tmp/scaling_log
region=$1
cluster_name=$2
eviction_count=$3
min_node=$4
max_node=$5
cool_down=$6
topic_arn=$7
n=0
##############get eviction count from cloud watch########################
get_eviction() {
        a=(`/usr/local/bin/aws cloudwatch get-metric-statistics --region=$region --namespace "AWS/ElastiCache" --metric-name Evictions --start-time $(date -u +%Y-%m-%dT%T --date 'now -5 mins') --end-time $(date -u +%Y-%m-%dT%T) --period 60 --statistics Average --query Datapoints[*].Average --out=json --dimensions Name=CacheClusterId,Value=$cluster_name| cut -d'.' -f1 | head -6 | tail -5`)
}

#################notification alert with aws sns##########################
notification() {
/usr/local/bin/aws sns publish --topic-arn $topic_arn --subject "memcache $1 scaling alert" --message "$2" --region=$region
}
autoscale_policy() {
for i in $a; do
        if [ $i -gt $eviction_count ];then
                let "n = $n + 1"
        else
                n=0
        fi
done
if [ $n -eq 5 ];then
        scale_up
else
        get_nodevalue
        if [ $NumCacheNodes -eq $min_node ];then
                echo "No Action Required, Eviction Count = ${a[4]} Node Count = $NumCacheNodes and Node Names = $node_id"
                exit 0
        else
        scale_down
        fi
fi
}


###############get cluster node count and name from elastic cache######################
get_nodevalue() {
        NumCacheNodes=`/usr/local/bin/aws elasticache describe-cache-clusters --region=$region --cache-cluster-id $cluster_name --query CacheClusters[*].NumCacheNodes[] --out text`
        node_id=`/usr/local/bin/aws elasticache describe-cache-clusters --region=$region --cache-cluster-id $cluster_name --show-cache-node-info --query CacheClusters[*].CacheNodes[*].CacheNodeId --out text`
}

###########check scaling action status################################################
validator(){
        get_nodevalue
        if [ $New_NumCacheNodes -eq $NumCacheNodes ];then
                notification $1 "scale $1 successfull current number of nodes= $NumCacheNodes and node_names= $node_id"
        else
                notification $1 "scale $1 failed current number of nodes= $NumCacheNodes and node_names= $node_id"
        fi
}


#############scale up action########################################
scale_up() {
        if [ $NumCacheNodes -eq $max_node ];then
                notification "up" "Nothing has to be done. Max node threashold reached, current number of nodes= $NumCacheNodes and node_names= $node_id"
                exit 0
        else
                let "New_NumCacheNodes = $NumCacheNodes+1"
                /usr/local/bin/aws elasticache modify-cache-cluster --cache-cluster-id $cluster_name --region=$region --num-cache-nodes $New_NumCacheNodes --apply-immediately
                sleep $cool_down
                validator "up"
        fi
}

############scale down action####################################
scale_down() {
         if [ $NumCacheNodes -le $min_node ];then
                notification "down" "Nothing has to be done. Min node threashold reached, the current number of nodes= $NumCacheNodes and node_names= $node_id"
echo $node_id
                exit 0
        else
                let "New_NumCacheNodes = $NumCacheNodes-1"
                d_node_id=`echo $node_id| awk '{print$NF}'`
                /usr/local/bin/aws elasticache modify-cache-cluster --cache-cluster-id $cluster_name --region=$region --num-cache-nodes $New_NumCacheNodes --cache-node-ids-to-remove $d_node_id --apply-immediately
                sleep $cool_down
                validator "down"
        fi
}

########main fuction to execute####################
get_eviction
get_nodevalue
autoscale_policy
