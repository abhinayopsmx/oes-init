#!/bin/bash -x

if [ $# -gt 1 ]
then
   echo "Invalid input, only one argument expected"
   exit
fi

COMPONENT=$1

check_for_loadBalancer()
{
    ## Wait for $EXTERNAL_IP_CHECK_DELAY till K8s assins a load Balancer IP to oes-gate
    iter=0
    lapsedTime=0
    while [ $iter -lt 36 ]
    do
      ENDPOINT_IP=$(kubectl get svc $1 -o jsonpath="{.status.loadBalancer.ingress[].ip}")
      if [ ! -z "$ENDPOINT_IP" ];
      then
        echo "Found LoadBalancer IP for" $1
        break
      fi
      sleep 5
      lapsedTime=`expr $lapsedTime + 5`
      if [ $lapsedTime -eq $EXTERNAL_IP_CHECK_DELAY ];
      then
	echo "Time Lapsed" $lapsedTime
        echo "Timeout! Fetching nodeport IP alternatively"
        break
      fi
      echo "Time Lapsed" $lapsedTime
      iter=`expr $iter + 1`
    done
}

check_for_spinnakerGate_loadBalancer()
{
    ## Wait for $EXTERNAL_IP_CHECK_DELAY till K8s assins a load Balancer IP to oes-gate
    iter=0
    lapsedTime=0
    while [ $iter -lt 36 ]
    do
      # Check if loadBalancer is directly assinged to spin-deck or spin-deck-ui service
      ENDPOINT_IP=$(kubectl get svc spin-deck -o jsonpath="{.status.loadBalancer.ingress[].ip}")

      if [ -z "$ENDPOINT_IP" ];
      then
        ENDPOINT_IP=$(kubectl get svc spin-deck-ui -o jsonpath="{.status.loadBalancer.ingress[].ip}")
      fi

      if [ ! -z "$ENDPOINT_IP" ];
      then
        echo "Found LoadBalancer IP for" $1
        break
      fi
      sleep 5
      lapsedTime=`expr $lapsedTime + 5`
      if [ $lapsedTime -eq $2 ];
      then
        echo "Time Lapsed" $lapsedTime
        echo "Timeout! Fetching nodeport IP alternatively"
        break
      fi
      echo "Time Lapsed" $lapsedTime
      iter=`expr $iter + 1`
    done
}

case "$COMPONENT" in

  oes-ui)
    cp /config/* /var/www/html/assets/config/

    ENDPOINT_IP=""

    ## Wait for $EXTERNAL_IP_CHECK_DELAY till K8s assins a load Balancer IP to oes-gate
    check_for_loadBalancer oes-gate

    ## If external IP is not available
    if [ -z "$ENDPOINT_IP" ]; then
      ## Fetch the IP of the host & nodeport and replace in app-config.js
      ENDPOINT_IP=$(kubectl get ep kubernetes -n default -o jsonpath="{.subsets[].addresses[].ip}")
      PORT=$(kubectl get svc oes-gate-svc -o jsonpath="{.spec.ports[].nodePort}")
      sed -i "s/OES_GATE_IP/$ENDPOINT_IP/g" /var/www/html/assets/config/app-config.json
      sed -i "s/8084/$PORT/g" /var/www/html/assets/config/app-config.json
    else
      ## Substitute oes-gate external IP in app-config.js
      sed -i "s/OES_GATE_IP/$ENDPOINT_IP/g" /var/www/html/assets/config/app-config.json
    fi
    ;;
  oes-gate)
    cp /config/* /opt/spinnaker/config/

    ENDPOINT_IP=""

    ## Wait for $EXTERNAL_IP_CHECK_DELAY till K8s assins a load Balancer IP to oes-gate
    check_for_loadBalancer oes-ui

    ## If external IP is not available
    if [ -z "$ENDPOINT_IP" ]; then
      ## Fetch the IP of the host and replace in gate.yml
      ENDPOINT_IP=$(kubectl get ep kubernetes -n default -o jsonpath="{.subsets[].addresses[].ip}")
      sed -i "s/OES_UI_LOADBALANCER_IP/$ENDPOINT_IP/g" /opt/spinnaker/config/gate.yml
    else
      ## Substitute oes-ui external IP in gate.yml
      sed -i "s/OES_UI_LOADBALANCER_IP/$ENDPOINT_IP/g" /opt/spinnaker/config/gate.yml
    fi
    ;;
  sapor)
    cp /config/* /opt/opsmx/

    ENDPOINT_IP=""

    ## Wait for $EXTERNAL_IP_CHECK_DELAY till K8s assins a load Balancer IP to oes-gate
    check_for_spinnakerGate_loadBalancer spin-deck $SPINNAKER_SETUP_DELAY
    PORT=9000

    ## If external IP is not available
    if [ -z "$ENDPOINT_IP" ]; then
      ## Fetch the IP of the host and replace in spinnaker.yaml
      ENDPOINT_IP=$(kubectl get ep kubernetes -n default -o jsonpath="{.subsets[].addresses[].ip}")
      PORT=$(kubectl get svc spin-gate -o jsonpath="{.spec.ports[].nodePort}")
      sed -i "s/SPIN_GATE_LOADBALANCER_IP_PORT/$ENDPOINT_IP:$PORT/g" /opt/opsmx/spinnaker.yaml
      #sed -i "s/spin-gate:8084/$ENDPOINT_IP:$PORT/g" /opt/opsmx/spinnaker.yaml
    else
      ## Substitute oes-ui external IP in spinnaker.yaml
      sed -i "s/SPIN_GATE_LOADBALANCER_IP_PORT/$ENDPOINT_IP:$PORT/g" /opt/opsmx/spinnaker.yaml
    fi
    ;;
  *)
    echo "Invalid input"
    ;;

esac
