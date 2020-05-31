#!/bin/bash
echo 'Running terraform imports'
terraform import "kubernetes_namespace.create_namespaces[0]" "dev-students"
terraform import "kubernetes_namespace.create_namespaces[1]" "qa-students"
terraform import "kubernetes_namespace.create_namespaces[2]" "prod-students"
terraform import "kubernetes_namespace.create_namespaces[3]" "dev"
terraform import "kubernetes_namespace.create_namespaces[4]" "qa"
terraform import "kubernetes_namespace.create_namespaces[5]" "prod"
terraform import "kubernetes_namespace.create_namespaces[6]" "test"

echo 'Deleting the resources from terraform state'
terraform state rm kubernetes_namespace.dev_namespace
terraform state rm kubernetes_namespace.qa_namespace
terraform state rm kubernetes_namespace.prod_namespace
terraform state rm kubernetes_namespace.qa
terraform state rm kubernetes_namespace.prod
terraform state rm kubernetes_namespace.test
terraform state rm kubernetes_namespace.dev
