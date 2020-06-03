#!/bin/bash


log_level_for()
{
  case "${1}" in
    "error")
      echo 1
      ;;

    "warn")
      echo 2
      ;;

    "debug")
      echo 3
      ;;

    "info")
      echo 4
      ;;
    *)
      echo -1
      ;;
  esac
}

current_log_level()
{
  log_level_for "${LOG_LEVEL}"
}

error()
{
  [ $(log_level_for "error") -le $(current_log_level) ] &&  echo "${1}" >&2
}

warn()
{
  [ $(log_level_for "warn") -le $(current_log_level) ] &&  echo "${1}" >&2
}

debug()
{
  [ $(log_level_for "debug") -le $(current_log_level) ] &&  echo "${1}" >&2
}

info()
{
  [ $(log_level_for "info") -le $(current_log_level) ] &&  echo "${1}" >&2
}

check_required_environment() {
  local required_env="${1}"

  for reqvar in $required_env
  do
    if [ -z "${!reqvar}" ]
    then
      error "missing ENVIRONMENT ${reqvar}!"
      return 1
    fi
  done
}

check_default_environment() {
  local required_env="${1}"

  for varpair in $required_env
  do
    local manual_environment=$(echo "${varpair}" | cut -d':' -f1)
    local default_if_not_set=$(echo "${varpair}" | cut -d':' -f2)
    if [ -z "${!manual_environment}" ] && [ -z "${!default_if_not_set}" ]
    then
      error "missing default ENVIRONMENT, set ${manual_environment} or ${default_if_not_set}!"
      return 1
    fi
  done
}

dry_run() {
  [ ${DRY_RUN} ] && info "skipping for dry run" && return
  return 1
}

init_tiller() {
  info "initializing local tiller"
  dry_run && return

  export TILLER_NAMESPACE=$PROJECT_NAMESPACE
  export HELM_HOST=localhost:44134
  # https://rimusz.net/tillerless-helm/
  # run tiller locally instead of in the cluster
  tiller --storage=secret &
  export TILLER_PID=$!
  sleep 1
  kill -0 ${TILLER_PID}
  if [ $? -gt 0 ]
  then
    error "tiller not running!"
    return 1
  fi
}

init_helm() {
  info "initializing helm"
  dry_run && return

  helm init --client-only
  if [ $? -gt 0 ]
  then
    error "could not initialize helm"
    return 1
  fi
}

init_helm_with_tiller() {
  init_tiller || return 1
  init_helm || return 1
  info "updating helm client repository information"
  dry_run && return
  helm repo update
  if [ $? -gt 0 ]
  then
    error "could not update helm repository information"
    return 1
  fi
}

decommission_tiller() {
  if [ -n "${TILLER_PID}" ]
  then
    kill ${TILLER_PID}
    if [ $? -gt 0 ]
    then
     return
    fi
  fi
}

check_required_deploy_arg_environment() {
  [ -z "${PROJECT_SPECIFIC_DEPLOY_ARGS}" ] && return
  for reqvar in ${PROJECT_SPECIFIC_DEPLOY_ARGS}
  do
    if [ -z ${!reqvar} ]
    then
      error "missing Deployment ENVIRONMENT ${reqvar} required!"
      return 1
    fi
  done
}

project_specific_deploy_args() {
  [ -z "${PROJECT_SPECIFIC_DEPLOY_ARGS}" ] && echo "" && return

  extraArgs=''
  for deploy_arg_key in ${PROJECT_SPECIFIC_DEPLOY_ARGS}
  do
    extraArgs="${extraArgs} --set $(echo "${deploy_arg_key}" | sed 's/__/\./g' | tr '[:upper:]' '[:lower:]')=${!deploy_arg_key}"
  done

  echo "${extraArgs}"
}

check_required_cluster_login_environment() {
  check_required_environment "HELM_TOKEN HELM_USER PROJECT_NAMESPACE CLUSTER_SERVER" || return 1
}

cluster_login() {
  info "authenticating ${HELM_USER} in ${PROJECT_NAMESPACE}"
  dry_run && return

  kubectl config set-cluster ci_kube --server="${CLUSTER_SERVER}" || return 1
  kubectl config set-credentials "${HELM_USER}" --token="${HELM_TOKEN}" || return 1
  kubectl config set-context ${PROJECT_NAMESPACE}-deploy  --cluster=ci_kube --namespace=${PROJECT_NAMESPACE} --user=${HELM_USER} || return 1
  kubectl config use-context ${PROJECT_NAMESPACE}-deploy || return 1
}

lint_template() {
  info "linting template"
  dry_run && return

  helm lint ${CI_PROJECT_DIR}/helm-chart/${CI_PROJECT_NAME}
}

check_required_image_pull_environment() {
  if [ "${CI_PROJECT_VISIBILITY}" == "public" ]
  then
    check_required_environment "CI_REGISTRY CI_DEPLOY_USER CI_DEPLOY_PASSWORD" || return 1
  fi
}

image_pull_settings() {
  if [ "${CI_PROJECT_VISIBILITY}" == "public" ]
  then
    echo ""
  else
    echo "--set registry.root=${CI_REGISTRY} --set registry.secret.username=${CI_DEPLOY_USER} --set registry.secret.password=${CI_DEPLOY_PASSWORD}"
  fi
}

deployment_name() {
  if [ -n "${DEPLOYMENT_NAME}" ]
  then
    echo "${DEPLOYMENT_NAME}"
  else
    echo "${CI_ENVIRONMENT_SLUG}-${CI_PROJECT_NAME}"
  fi
}

deploy_template() {
  info "deploying $(deployment_name) from template"
  if dry_run
  then
    info "helm upgrade --force --recreate-pods --debug --set image.repository=${CI_REGISTRY_IMAGE}/${CI_PROJECT_NAME} --set image.tag=${CI_COMMIT_SHORT_SHA} --set environment=${CI_ENVIRONMENT_NAME} --set-string git_commit=${CI_COMMIT_SHORT_SHA} --set git_ref=${CI_COMMIT_REF_SLUG} --set ci_job_id=${CI_JOB_ID} $(environment_url_settings) $(image_pull_settings) $(project_specific_deploy_args) --wait --install $(deployment_name) ${CI_PROJECT_DIR}/helm-chart/${CI_PROJECT_NAME}"
  else
    helm upgrade --force --recreate-pods --debug \
    --set image.repository="${CI_REGISTRY_IMAGE}/${CI_PROJECT_NAME}" \
    --set image.tag="${CI_COMMIT_SHORT_SHA}" \
    --set environment="${CI_ENVIRONMENT_NAME}" \
    --set-string git_commit="${CI_COMMIT_SHORT_SHA}" \
    --set git_ref="${CI_COMMIT_REF_SLUG}" \
    --set ci_job_id="${CI_JOB_ID}" \
    $(image_pull_settings) \
    $(project_specific_deploy_args) \
    --wait \
    --install $(deployment_name) ${CI_PROJECT_DIR}/helm-chart/${CI_PROJECT_NAME}
  fi
}

get_pods() {
  kubectl get pods -l ci_job_id="${CI_JOB_ID}"
}

watch_deployment() {
  local watch_deployment=$(deployment_name)
  if [ -n "${WATCH_DEPLOYMENT}" ]
  then
    watch_deployment="${WATCH_DEPLOYMENT}"
  fi
  info "waiting until deployment ${watch_deployment} is ready"
  dry_run && return

  kubectl rollout status deployment/${watch_deployment} -w || return 1
  sleep 5
  get_pods || return 1
  # see what has been deployed
  kubectl describe deployment -l app=${CI_PROJECT_NAME},environment=${CI_ENVIRONMENT_NAME},git_commit=${CI_COMMIT_SHORT_SHA} || return 1
  if [ -n "${CI_ENVIRONMENT_URL}" ]
  then
    kubectl describe service -l app=${CI_PROJECT_NAME},environment=${CI_ENVIRONMENT_NAME} || return 1
    kubectl describe route -l app=${CI_PROJECT_NAME},environment=${CI_ENVIRONMENT_NAME} || return 1
  fi
}

run_main() {
  check_required_environment "CI_PROJECT_NAME CI_PROJECT_DIR CI_COMMIT_REF_SLUG CI_REGISTRY_IMAGE CI_ENVIRONMENT_NAME CI_JOB_ID CI_COMMIT_SHORT_SHA" || return 1
  check_default_environment "WATCH_DEPLOYMENT:CI_ENVIRONMENT_SLUG" || return 1
  check_required_deploy_arg_environment || return 1
  check_required_cluster_login_environment || return 1
  check_required_image_pull_environment || return 1
  cluster_login
  if [ $? -gt 0 ]
  then
    error "could not login kubectl"
    return 1
  fi

  init_helm_with_tiller
  if [ $? -gt 0 ]
  then
    error "could not initialize helm"
    return 1
  fi

  lint_template
  if [ $? -gt 0 ]
  then
    error "linting failed"
    return 1
  fi

  deploy_template
  if [ $? -gt 0 ]
  then
    error "could not deploy template"
    return 1
  fi

  watch_deployment
  if [ $? -gt 0 ]
  then
    error "could not watch deployment"
    return 1
  fi

  decommission_tiller
  info "ALL Complete!"
  return
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  run_main
  if [ $? -gt 0 ]
  then
    exit 1
  fi
fi
 









