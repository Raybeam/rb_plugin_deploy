#!/bin/bash

################################################################################
# help                                                                         #
################################################################################
help()
{
   # Display help
   echo "This script will deploy a Rabyeam Airflow Plugin to an environment, using the instructions listed in the README.md file."
   echo
   echo
   echo "Required parameters:"
   echo "environment               The environment you'd like to deploy to."
   echo "                          (local, astronomer_local, astronomer_remote, google_cloud_composer)"
   echo
   echo
   echo
   echo "Example:"
   echo -e "\t./plugins/$selected_plugin/deploy.sh --environment=local"
   echo
}

################################################################################
# Prompt for whether to include samples                                        #
################################################################################
prompt_add_sample_dags()
{
  if [ $selected_plugin == "rb_status_plugin" ]; then 
    while true; do
      echo -e "\n\nPlease select which type of deployment you would like:"
      
      deploy_options=("basic plugin install" "plugin install and sample dags" "plugin install and all samples")
      for i in "${!deploy_options[@]}"; do 
        printf "[%s]\t%s\n" "$i" "${deploy_options[$i]}"
      done
      read user_input_environment 
      echo
      case $user_input_environment in
        "0"|"basic plugin install")
          echo -e "\nInstalling plugin...\n"
          plugins/$selected_plugin/bin/rb_status init
          import_sample_dags="n"
          break
          ;;
        "1"|"plugin install and sample dags")
          echo -e "\nInstalling plugin with sample dags...\n"
          plugins/$selected_plugin/bin/rb_status init
          plugins/$selected_plugin/bin/rb_status add_samples --dag_only
          import_sample_dags="Y"
          break
          ;;
        "2"|"plugin install and all samples")
          echo -e "\nInstalling plugin with all samples...\n"
          plugins/$selected_plugin/bin/rb_status init
          plugins/$selected_plugin/bin/rb_status add_samples
          import_sample_dags="Y"
          break
          ;;
        *)
          echo -e "\nInvalid choice...\n"
      esac
    done

  elif [ $selected_plugin == "rb_quality_plugin" ]; then 
    while true; do
        echo -e "\n\nWould you like to import rb_quality_plugin's sample dags? (Y/n)"
        read import_sample_dags
        echo
        case $import_sample_dags in
          [yY])
            echo -e "\n\nImporting sample dags..."
            mkdir dags/rb_quality_plugin_example_dags
            cp -r plugins/rb_quality_plugin/example_dags/* dags/rb_quality_plugin_example_dags
            break
            ;;
          [nN])
            echo -e "\n\nImporting sample dags skipped..."
            break
            ;;
          *)
            echo -e "\n\nInvalid choice..."
        esac
    done
  fi
}

################################################################################
# Deploy Locally                                                               #
################################################################################
deploy_local()
{
  declare -a dependencies=("python3" "pip3" "git")
  for val in $dependencies; do
      if ! [ -x "$(command -v $val)" ]; then
        printf "Unable to complete deploy, please install %s\n" "$val."
        exit 1
      fi
  done
  echo "Deploying airflow locally..."
  echo -e "\n\n\nCreating virtual environment..."
  python3 -m venv .
  source "bin/activate"
  echo "export AIRFLOW_HOME=$PWD" >> bin/activate

  echo -e "\n\n\nInstalling required python packages..."
  echo >> requirements.txt
  cat plugins/$selected_plugin/requirements.txt >> requirements.txt
  sort -u requirements.txt  > requirements2.txt
  mv requirements2.txt requirements.txt 
  pip3 install -r requirements.txt

  echo -e "\n\n\nInstalling and configuring airflow in virtual environment..."
  pip3 install apache-airflow
  pip3 install psycopg2
  airflow initdb
  airflow create_user -r Admin -u admin -e admin@example.com -f admin -l user -p admin

  echo -e "\n\nInstalling $selected_plugin..."
  prompt_add_sample_dags
}

################################################################################
# List choices and parse answer for prompt                                     #
################################################################################
format_prompt() {
  config_param="$1"
  shift
  local list_choices=("$@")

  for i in "${!list_choices[@]}"; do 
    printf "%s\t%s\n" "[$i]" "${list_choices[$i]}"
  done
  read choice_selected

  if [[ " ${list_choices[@]} " =~ " $choice_selected " ]]; then
    echo -e "$config_param set to $choice_selected"
    prompt_in_progress=false
  else
    case $choice_selected in
    ''|*[!0-9]*)
      echo -e "$choice_selected is an invalid choice."
      ;;
    *)
      if [ $(($choice_selected < ${#list_choices[@]})) ]; then
        choice_selected="${list_choices[$choice_selected]}"
        echo -e "$config_param set to $choice_selected"
        prompt_in_progress=false
      else
        echo -e "$choice_selected is an invalid choice."
      fi
      ;;
    esac
  fi
}

################################################################################
# Deploy to Google Cloud Composer                                              #
################################################################################
deploy_gcc()
{
  if ! [ -x "$(command -v gcloud)" ]; then
    echo "Unable to complete deploy, please install gcloud."
    exit 1
  fi


  prompt_in_progress=true
  while $prompt_in_progress; do
    echo -e "\n\n\n"
    region_list=( $(gcloud compute regions list --format="value(name)") )
    echo "Please select one of the following regions to deploy to:"
    format_prompt "region" "${region_list[@]}"
  done
  LOCATION=$choice_selected


  prompt_in_progress=true
  while $prompt_in_progress; do
    echo -e "\n\n\n"
    project_list=( $(gcloud projects list --format="value(name)") )
    echo "Please select one of the following projects:"
    format_prompt "project" "${project_list[@]}"
  done
  PROJECT_NAME=$choice_selected

  prompt_in_progress=true
  while $prompt_in_progress; do
    echo -e "\n\n\n"
    environment_list=( $(gcloud composer environments list --locations $LOCATION  --format="value(name)") )
    echo "Please select one of the following environments:"
    format_prompt "environment" "${environment_list[@]}"
  done
  ENVIRONMENT_NAME=$choice_selected


  gcloud config set project $PROJECT_NAME
  echo "updating requirements..."
  cat $(pwd)/plugins/$selected_plugin/requirements.txt | while read requirement 
  do
    echo -e "installing python package: $requirement.."
    gcloud beta composer environments update $ENVIRONMENT_NAME --location $LOCATION --update-pypi-package=$requirement
  done
  echo -e "\n\nsetting airflow configurations..."
  gcloud composer environments update $ENVIRONMENT_NAME --location $LOCATION --update-airflow-configs webserver-rbac=False,core-store_serialized_dags=False,webserver-async_dagbag_loader=True,webserver-collect_dags_interval=10,webserver-dagbag_sync_interval=10,webserver-worker_refresh_interval=3600
  echo -e "\n\ninstalling $selected_plugin..."
  if [ $selected_plugin == "rb_status_plugin" ]; then
    if [ "$import_sample_dags" == "y" ] || [ "$import_sample_dags" == "Y" ]; then
      gcloud composer environments storage dags import --environment=$ENVIRONMENT_NAME --location $LOCATION --source $(pwd)/plugins/$selected_plugin/setup/rb_status.py
    fi
  fi
  if [ $selected_plugin == "rb_quality_plugin" ]; then
    if [ "$import_sample_dags" == "y" ] || [ "$import_sample_dags" == "Y" ]; then
      gcloud composer environments storage dags import --environment=$ENVIRONMENT_NAME --location $LOCATION --source $(pwd)/plugins/rb_quality_plugin/example_dags
    fi
  fi
  gcloud composer environments storage plugins import --environment=$ENVIRONMENT_NAME --location $LOCATION --source $(pwd)/plugins/$selected_plugin/
}

################################################################################
# Deploy to Astronomer Locally                                                 #
################################################################################
deploy_astronomer_local()
{
  if ! [ -x "$(command -v astro)" ]; then
    echo "Unable to complete deploy, please install astro."
    exit 1
  fi
  
  deploy_local

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
   echo -e "To start astro-airflow instance, please run:\n\tsudo astro dev init\n\tsudo astro dev start"
  else
    echo -e "To start astro-airflow instance, please run:\n\tastro dev init\n\tastro dev start"
  fi
}
################################################################################
# Deploy to Astronomer Remotely                                                #
################################################################################
deploy_astronomer_remote()
{
  if ! [ -x "$(command -v astro)" ]; then
    echo "Unable to complete deploy, please install astro."
    exit 1
  fi

  deploy_local

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo astro dev init
    sudo astro dev deploy
  else
    astro dev init
    astro dev deploy
  fi
}

################################################################################
# Deploy plugin (based on environment chosen)                                  #
################################################################################
deploy_plugin()
{
  if [ "$environment" == "local" ]; then
    deploy_local
    start_airflow
  elif [ "$environment" == "astronomer_local" ]; then
    deploy_astronomer_local
  elif [ "$environment" == "astronomer_remote" ]; then
    deploy_astronomer_remote
  elif [ "$environment" == "google_cloud_composer" ]; then
    deploy_gcc
  else
    echo "Error: Environment not specified."
    help
  fi
}

################################################################################
# Start Webserver and Scheduler                                                #
################################################################################
start_airflow()
{
    echo -e "\n\nTo start airflow webserver, please open a new tab and run:\n\tcd '$(pwd)'; source \"bin/activate\"; airflow webserver"
    echo -e "\n\nTo start airflow scheduler, please open a new tab and run:\n\tcd '$(pwd)'; source \"bin/activate\"; airflow scheduler"
}

################################################################################
#  Prompt user asking where they wish to deploy.                               #
################################################################################
prompt_deploy()
{
  while true; do
    echo -e "\n\nEnvironment not specified. Please select one of the following choices:"
    environment_options=(local astronomer_local astronomer_remote google_cloud_composer)
    for i in "${!environment_options[@]}"; do 
      printf "[%s]\t%s\n" "$i" "${environment_options[$i]}"
    done
    read user_input_environment 
    echo
    case $user_input_environment in
      "0"|"local")
        echo -e "\nEnvironment set to: local\n"
        environment="local"
        break
        ;;
      "1"|"astronomer_local")
        echo -e "\nEnvironment set to: astronomer_local\n"
        environment="astronomer_local"
        break
        ;;
      "2"|"astronomer_remote")
        echo -e "\nEnvironment set to: astronomer_remote\n"
        environment="astronomer_remote"
        break
        ;;
      "3"|"google_cloud_composer")
        echo -e "\nEnvironment set to: google_cloud_composer\n"
        environment="google_cloud_composer"
        break
        ;;
      *)
        echo -e "\nInvalid choice...\n"
    esac
  done
}
################################################################################
#  Prompt user asking what plugin they wish to deploy.                         #
################################################################################
prompt_plugin_selection()
{
  while true; do
    echo -e "\n\nPlease select one of the following plugins to deploy:"
    for i in "${!plugin_options[@]}"; do 
      printf "[%s]\t%s\n" "$i" "${plugin_options[$i]}"
    done
    read user_input_environment 
    echo
    case $user_input_environment in
      "0"|"rb_status_plugin")
        selected_plugin="rb_status_plugin"
        break
        ;;
      "1"|"rb_quality_plugin")
        selected_plugin="rb_quality_plugin"
        break
        ;;
      *)
        echo -e "\nInvalid choice...\n"
    esac
  done
  echo -e "\n$selected_plugin selected.\n"
}

################################################################################
#  Prompt user asking what version of the plugin they wish to deploy.          #
################################################################################
prompt_release_selection()
{

  if ! [ -x "$(command -v jq)" ]; then
    echo "Unable to complete deploy, please install jq."
    exit 1
  fi

  release_names_list=()
  release_tags_list=()
  echo -e "Fetching list of releases..."
  releases_json=$(curl -s https://api.github.com/repos/Raybeam/$selected_plugin/releases)
  for release_name in $(jq -r '.[] | .name' <<< "$releases_json"); do
    release_names_list+=($release_name)
  done
  for release_tag in $(jq -r '.[] | .tag_name' <<< "$releases_json"); do
    release_tags_list+=($release_tag)
  done


 if [ ! -z "$release_names_list" ]; then
    while true; do
      echo -e "\n\nPlease select one of the following versions:"
      for i in "${!release_names_list[@]}"; do 
        printf "[%s]\t%s\n" "$i" "${release_names_list[$i]}"
      done
      read selected_plugin_version 
      echo

      case $selected_plugin_version in
        # if the user entered a string, check if it matches a realease name and download that release
        ''|*[!0-9]*)
          if [[ " ${release_names_list[@]} " =~ " ${selected_plugin_version} " ]]; then
            for i in "${!release_names_list[@]}"; do
               if [[ "${release_names_list[$i]}" = "${selected_plugin_version}" ]]; then
                   plugin_index=$i
                   break
               fi
            done
            selected_plugin_version_tag=${release_tags_list[$plugin_index]}

            echo -e "\nDownloading \"$selected_plugin_version\" into \"$(pwd)/plugins/$selected_plugin\".\n"
            git clone https://github.com/Raybeam/$selected_plugin --branch $selected_plugin_version_tag $(pwd)/plugins/$selected_plugin
            break
          else
            continue
          fi
          ;;

        # if the user entered a number, download the associated release
        *)
          if [ $selected_plugin_version -lt "${#release_names_list[@]}" ]; then
            plugin_index=$selected_plugin_version
            selected_plugin_version_tag="${release_tags_list[$plugin_index]}"
            selected_plugin_version="${release_names_list[$plugin_index]}"

            echo -e "\nDownloading \"$selected_plugin_version\" into \"$(pwd)/plugins/$selected_plugin\".\n"
            git clone https://github.com/Raybeam/$selected_plugin --branch $selected_plugin_version_tag $(pwd)/plugins/$selected_plugin
            break
          else
            continue
          fi
          ;;
      esac
    done

  else
    while true; do
      echo -e "No releases available yet. Would you like to deploy from the master branch?(Y/n)"
      read deploy_from_master
      case $deploy_from_master in
        [yY])
          echo -e "\nDownloading $selected_plugin's master branch into \"$(pwd)/plugins/$selected_plugin\".\n"
          git clone https://github.com/Raybeam/$selected_plugin $(pwd)/plugins/$selected_plugin
          break
          ;;
        [nN])
          echo -e "\n\nExiting deploy script..."
          exit 1
          ;;
        *)
          echo -e "\n\nInvalid choice..."
          ;;
      esac
    done
  fi
}

################################################################################
#  Main Code.                                                                  #
################################################################################
while [ $# -gt 0 ]; do
  case "$1" in
    --help)
      help
      exit 1;;
    --environment=*)
      environment="${1#*=}"
      ;;
    *)
      printf "**********************************************************************************\n"
      printf "Error: Invalid argument. \""
      printf $1
      printf "\" is not defined.\n"
      printf "**********************************************************************************\n\n\n"
      help
      exit 1
  esac
  shift
done

plugin_options=(rb_status_plugin rb_quality_plugin)
prompt_plugin_selection
prompt_release_selection

if [ -z ${environment+x} ]; then
  prompt_deploy
fi

if [ "$(ls -A $(pwd))" ]; then
  echo -e "Directory '$(pwd)' is not empty. Running this script may overwrite files in the directory.\nAre you sure you want to do this?(Y/n)"
  read boolean_run_script
  echo
  case $boolean_run_script in
    [yY])
      echo -e "\n\nStarting deploy script..."
      deploy_plugin
      ;;
    *)
      echo -e "\n\nExiting deploy script..."
      exit 1
  esac
else
  echo -e "\n\nStarting deploy script..."
  exit 1
  deploy_plugin
fi