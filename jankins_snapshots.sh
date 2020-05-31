#!/bin/bash

JENKINS_POD_NAME="$(kubectl get pods -n tools | grep jenkins-deploy | awk '{print $1}')"
# echo $JENKINS_POD_NAME


if [ "$1" = "--sync" ]; then
  kubectl cp tools/$JENKINS_POD_NAME:/var/jenkins_home/secrets ~/secrets
  kubectl cp tools/$JENKINS_POD_NAME:/var/jenkins_home/secret.key ~/secret.key
  kubectl cp tools/$JENKINS_POD_NAME:/var/jenkins_home/jobs  ~/jobs
  kubectl cp tools/$JENKINS_POD_NAME:/var/jenkins_home/credentials.xml ~/credentials.xml
fi


if [ "$1" = "--restore" ]; then
  kubectl cp ~/secrets tools/$JENKINS_POD_NAME:/var/jenkins_home
  kubectl cp ~/secret.key tools/$JENKINS_POD_NAME:/var/jenkins_home
  kubectl cp ~/jobs tools/$JENKINS_POD_NAME:/var/jenkins_home
  kubectl cp ~/credentials.xml tools/$JENKINS_POD_NAME:/var/jenkins_home
fi
