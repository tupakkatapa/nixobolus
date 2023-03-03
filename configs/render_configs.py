#!/usr/bin/env python3
# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

'''
This script loads a YAML or JSON file containing the hosts configuration and renders configuration files 
using Jinja2 templates. The rendered files are then saved to a specific directory for each host.
'''

import yaml, json
import os, shutil, sys
from glob import glob
from jinja2 import Environment, FileSystemLoader
from pathlib import Path
import traceback


def yaml_or_json(file_path):
    '''
    Detect if a file is YAML or JSON
    '''
    with open(file_path, 'r') as f:
        config = f.read()
    
    try:
        config_dict = json.loads(config)
        return 'json'
    except json.JSONDecodeError:
        pass
    
    try:
        config_dict = yaml.safe_load(config)
        return 'yaml'
    except yaml.YAMLError:
        pass

    raise ValueError('[-] py: Unable to detect the data format.')


def key_exists(data, key):
    '''
    Function to check existence of a key in data structure
    '''
    if isinstance(data, dict):
        if key in data:
            return True
        else:
            for k in data:
                if key_exists(data[k], key):
                    return True
    elif isinstance(data, list):
        for item in data:
            if key_exists(item, key):
                return True
    return False


def render_config_files(data, template_path, output_path):
    '''
    Function to render config files from Jinja2 templates
    '''
    # Create a Jinja2 environment and load the template
    env = Environment(loader=FileSystemLoader(os.path.dirname(template_path)))

    # Get template and render
    template = env.get_template(os.path.basename(template_path))
    rendered_config = template.render(data=data)

    # Save the rendered configuration to a file
    with open(output_path, "w") as f:
        f.write(rendered_config)


def merge_dicts(dict1, dict2, overwrite=False):
    '''
    Merge the content of two dictionaries.
    '''
    for key in dict2:
        if key in dict1 and isinstance(dict1[key], dict) and isinstance(dict2[key], dict):
            merge_dicts(dict1[key], dict2[key], overwrite)
        else:
            if key in dict1 and not overwrite:
                continue
            dict1[key] = dict2[key]
    return dict1


def main(input_file):
    # Define constants
    TEMPLATE_DIR = Path("templates_nix/")
    CONFIG_DIR = Path("configs/nix_configs/hosts/")

    # Project path
    project_path = Path(__file__).resolve().parent.parent

    # Load the hosts configuration from YAML or JSON file
    try:
        if input_file.endswith(('yaml', 'yml', 'json')):
            with open(input_file, "r") as f:
                data = yaml.safe_load(f) if input_file.endswith(('yaml', 'yml')) else json.load(f)
        else:
            detected_format = yaml_or_json(input_file)
            if detected_format == 'yaml':
                with open(input_file, "r") as f:
                    data = yaml.safe_load(f)
            elif detected_format == 'json':
                with open(input_file, "r") as f:
                    data = json.load(f)
            else:
                sys.exit("[-] py: Invalid data format. Only YAML and JSON are supported.")            
    except Exception as e:
        traceback.print_exc()
        sys.exit(f"[-] py: Failed to load data: {e}")

    # Get list of j2 files in template directory 
    template_dir = project_path / TEMPLATE_DIR
    template_files = list(template_dir.glob("**/*.j2"))

    # Render the template with the hosts configuration
    for host in data.get('hosts', []):

        # Merge values into the host data
        general = data.get('general', {})
        variables = data.get('variables', {})
        host = merge_dicts(host, general)
        host = merge_dicts(host, variables)

        # Extract hostname and create directory for host configurations
        hostname = host['name']
        host_config_dir = project_path / CONFIG_DIR / hostname
        host_config_dir.mkdir(parents=True, exist_ok=True)

        # List to hold the rendered files for this host
        rendered_configs = []

        # Iterate through the template files, excluding the default.nix file
        for template_path in template_files:

            # Extract the template name and config name
            template_name = template_path.name

            # Skip default template
            if template_path == template_dir / 'default.j2':
                continue

            # Extract the name prefix
            key = template_name.rsplit(".",1)[0]

            # Construct the config path
            config_path = template_path.as_posix().replace("templates_nix/", f"configs/nix_configs/hosts/{hostname}/").replace(".j2", ".nix")
            
            # Check if the host has the service
            if key_exists(host, key) or (key == "default" and key_exists(host, Path(config_path).parent.name)): 

                # Create output folder if does not exists
                os.makedirs(os.path.dirname(config_path), exist_ok=True)

                # Render the config file
                try:
                    render_config_files(host, template_path.as_posix(), config_path)
                except Exception as e:
                    traceback.print_exc()
                    sys.exit(f"[-] py: Failed to render {template_name}: {e}")

                # Append path to list of rendered files
                rendered_configs.append('.' + config_path.rsplit(hostname)[1])

        # Append rendered configs to data
        host["rendered_configs"] = rendered_configs

        # Render default.nix
        default_template_path = template_dir / "default.j2"
        default_config_path = host_config_dir / "default.nix"
        render_config_files(host, default_template_path.as_posix(), default_config_path.as_posix())

# Get the input file from the argument
input_file = sys.argv[1]

# Main
main(input_file)