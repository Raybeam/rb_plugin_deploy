# rb_plugin_deploy
A repository for deploying Raybeam's Airflow Plugin.  
  
The repository contains a deploy.sh file that allows you to:  
- Select the plugin(s) you'd like to deploy  
- Select the environment you'd like to deploy to (Composer, Astronomer, Local, etc..)  
- Select whether or not to include the plugin's sample data/dags  
  
## Running Deploy Script
To run the deploy script:
- open your terminal to an empty directory  
- `$git clone https://github.com/Raybeam/rb_test_airflow/ sample_workspace`  
- `$cd sample_workspace`  
- `$git clone https://github.com/Raybeam/rb_plugin_deploy plugins/rb_plugin_deploy`  
- `$./plugins/rb_plugin_deploy/deploy.sh`  

## Plugins
A list of available plugins can be found [here](https://github.com/Raybeam/rb_plugin_deploy/blob/master/VERSIONS.md).
