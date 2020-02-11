#!/usr/bin/env bash

# ##################################################
#
version="0.0.1"              # Sets version variable
#
# HISTORY:
#
# * 20200211 - v0.0.1  - First Creation
#
# ##################################################

function mainScript() {
  # invoke verbose usage when set
  if ${verbose}; then v="-v" ; fi

  # Helper Functions
  # ###################
  function displayVariables() {
    # variable dump for testing. #FIXME
    notice "Doing an environment variable dump."
    env | sort
  }

  function preflights() {
    # Preflight checks that must be successful for the script to run further. Checks are:
    # FIXME
    true
  }
  function brewMaintenance () {
    # brewMaintenance
    # ------------------------------------------------------
    # Will run the recommended Homebrew maintenance scripts
    # ------------------------------------------------------
    seek_confirmation "Run Homebrew maintenance?"
    if is_confirmed; then
      brew doctor
      brew update
      brew upgrade
    fi
  }
  function brewCleanup () {
    # This function cleans up an initial Homebrew installation

    notice "Running Homebrew maintenance..."

    # This is where brew stores its binary symlinks
    binroot="$(brew --config | awk '/HOMEBREW_PREFIX/ {print $2}')"/bin

    if [[ "$(type -P ${binroot}/bash)" && "$(cat /etc/shells | grep -q "$binroot/bash")" ]]; then
      info "Adding ${binroot}/bash to the list of acceptable shells"
      echo "$binroot/bash" | sudo tee -a /etc/shells >/dev/null
    fi
    if [[ "$SHELL" != "${binroot}/bash" ]]; then
      info "Making ${binroot}/bash your default shell"
      sudo chsh -s "${binroot}/bash" "$USER" >/dev/null 2>&1
      success "Please exit and restart all your shells."
    fi

    brew cleanup

    # FIXME - whats this?
    # if brew cask > /dev/null; then
    #   brew cask cleanup
    # fi
  }
  function installCommandLineTools() {
    notice "Checking for Command Line Tools..."

    if [[ ! "$(type -P gcc)" || ! "$(type -P make)" ]]; then
      #local osx_vers=$(sw_vers -productVersion | awk -F "." '{print $2}')
      local cmdLineToolsTmp="${tmpDir}/.com.apple.dt.CommandLineTools.installondemand.in-progress"

      # Create the placeholder file which is checked by the software update tool
      # before allowing the installation of the Xcode command line tools.
      touch "${cmdLineToolsTmp}"

      # Find the last listed update in the Software Update feed with "Command Line Tools" in the name
      cmd_line_tools=$(softwareupdate -l | awk '/\*\ Command Line Tools/ { $1=$1;print }' | tail -1 | sed 's/^[[ \t]]*//;s/[[ \t]]*$//;s/*//' | cut -c 2-)

      softwareupdate -i "${cmd_line_tools}" -v

      # Remove the temp file
      if [[ -f "${cmdLineToolsTmp}" ]]; then
        rm ${v} "${cmdLineToolsTmp}"
      fi
    fi
    success "Command Line Tools installed"
  }
  function installHomebrew () {
    # Check for Homebrew
    notice "Checking for Homebrew..."
    if [[ ! "$(type -P brew)" ]]; then
      notice "No Homebrew. Gots to install it..."
      #   Ensure that we can actually, like, compile anything.
      if [[ ! $(type -P gcc) && "$OSTYPE" =~ ^darwin ]]; then
        notice "XCode or the Command Line Tools for XCode must be installed first."
        installCommandLineTools
      fi
      # Check for Git
      if [ ! "$(type -P git)" ]; then
        notice "XCode or the Command Line Tools for XCode must be installed first."
        installCommandLineTools
      fi
      # Install Homebrew
      ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
      #installHomebrewTaps
    fi
    success "Homebrew installed"
  }
  function checkTaps() {

    verbose "Confirming we have required Homebrew taps"
    if ! brew cask help &>/dev/null; then
      installHomebrewTaps
    fi
    if [ ! "$(type -P mas)" ]; then
      installHomebrewTaps
    fi
  }
  function installHomebrewTaps() {
    # FIXME - add our taps here
    #brew tap homebrew/dupes
    #brew tap homebrew/versions
    brew tap homebrew/cask-cask   
    #brew tap caskroom/fonts
    #brew tap caskroom/versions # Subversion client for MacOS
  }
  function installCaskApps() { # Install apps regardless of physical or virtual machine.
    unset LISTINSTALLED INSTALLCOMMAND RECIPES

    notice "Checking for casks to install..."

    checkTaps

    LISTINSTALLED="brew cask list"
    INSTALLCOMMAND="brew cask install --appdir=/Applications"

    for item in "${RECIPES[@]}"; do
      info "$item"
    done
    doInstall

    success "Done installing cask apps"
  }
  function installHomebrewPackages() {
  # FIXME - trim this list
    unset LISTINSTALLED INSTALLCOMMAND RECIPES

    notice "Checking for Homebrew packages to install..."

    #checkTaps

    LISTINSTALLED="brew list"
    INSTALLCOMMAND="brew install"

    RECIPES=(
      # FIXME - just a placeholder for now.
      wget
    )
    doInstall

    success "Done installing Homebrew packages"
  }
  function installSundry() {
    # FIXME - remove this function if not needed.
    notice "Function ${FUNCNAME[0]} was run."
  }
  function getPackerTemplatePath() {
    notice "Building path to templates."
    # Check we got the input params we needed. There should be two.
    if [[ $# -lt 2 ]]; then
        die "Could not build path to templates. Not enough params passed to function."
        exit 1
    fi
    local REPOSITORYROOT=$1 # comes from -ImageGenerationRepositoryRoot param.
    local IMAGETYPE=$2      # derive below in case
    local RELATIVEPATH=""   # set to empty to start

    case ${IMAGETYPE} in
        "Windows2016")
            RELATIVEPATH="/images/win/Windows2016-Azure.json"
            notice "Setting Packer template path to ${RELATIVEPATH}"
        ;;

        "Windows2019")
            RELATIVEPATH="/images/win/Windows2019-Azure.json"
            notice "Setting Packer template path to ${RELATIVEPATH}"
        ;;

        "Ubuntu1604")
            RELATIVEPATH="/images/linux/Ubuntu1604.json"
            notice "Setting Packer template path to ${RELATIVEPATH}"
        ;;

        "Ubuntu1804")
            RELATIVEPATH="/images/linux/Ubuntu1804.json"
            notice "Setting Packer template path to ${RELATIVEPATH}"
        ;;

        *)
            die "Function ${FUNCNAME[0]} was given an incorrect IMAGETYPE variable (it received: ${IMAGETYPE}"
            exit 1
        ;;
    esac

    #BUILDERSCRIPTPATH="$(REPOSITORYROOT)$(RELATIVEPATH)"
    BUILDERSCRIPTPATH="$REPOSITORYROOT$RELATIVEPATH"
    notice "Script path is $BUILDERSCRIPTPATH"
  }
  function packerBuild() {
    # this is a working string:
    # `/usr/local/bin/packer build -on-error=ask \
    # -var client_id="5f958c89-21bd-4d5b-b17a-4cd6345041ab" \
    # -var client_secret="N6ck.HjY/-w0[XDc1iHuEqTkTiO4t[X1" \
    # -var subscription_id="f38b31ab-444a-4234-80d0-34cd3b3ba58f" \
    # -var tenant_id="0fe05593-19ac-4f98-adbf-0375fce7f160" \
    # -var location="Australia East" \
    # -var resource_group="adoAgents-rg" \
    # -var storage_account="adoagentssa" \
    # -var install_password="wordpass09" \
    # -var github_feed_token="longstring" \
    # /Users/abest/github/virtual-environments/images/linux/Ubuntu1804.json`
    notice "Starting packerBuild."
    $(command -v packer) build -on-error=ask \
          -var client_id="$ARM_CLIENT_ID" \
          -var client_secret="$ARM_CLIENT_SECRET" \
          -var subscription_id="$ARM_SUBSCRIPTION_ID" \
          -var tenant_id="$ARM_TENANT_ID" \
          -var location="$REGION" \
          -var resource_group="$RGNAME" \
          -var storage_account="$ARM_STORAGE_ACCOUNT" \
          -var install_password="$InstallPassword" \
          -var github_feed_token="$GithubFeedToken" \
          "$BUILDERSCRIPTPATH"
  }

  # ###################
  # Run the script
  # ###################

# FIXME - remove or uncomment if needed.
#  # Ask for the administrator password upfront
#  echo "administrator authorisation required. Please enter your administrator password."
#  sudo -v
#
#  # Make sure we are signed into the app store
#  warning "You must be signed into the App Store for this script to work..."
#  warning "We will pause here while you go and do the sign in thing..."
#  read -n 1 -s -r -p "Press enter to continue"

#  checkTaps
#  brewCleanup
#  installHomebrewPackages
#  installCaskApps
#  #installDevApps
  installSundry
  displayVariables

  # Here we actually start doing stuff
  getPackerTemplatePath "${IMAGEROOT}" "${IMAGETYPE}"
  packerBuild $BUILDERSCRIPTPATH

}

## SET SCRIPTNAME VARIABLE ##
scriptName=$(basename "$0")

function trapCleanup() {
  # trapCleanup Function
  # -----------------------------------
  # Any actions that should be taken if the script is prematurely
  # exited.  Always call this function at the top of your script.
  # -----------------------------------
  echo ""
  # Delete temp files, if any
  if [[ -d "${tmpDir}" ]] ; then
    rm -r "${tmpDir}"
  fi
  die "Exit trapped."
}

function safeExit() {
  # safeExit
  # -----------------------------------
  # Non destructive exit for when script exits naturally.
  # Usage: Add this function at the end of every script.
  # -----------------------------------
  # Delete temp files, if any
  if [[ -d "${tmpDir}" ]] ; then
    rm -r "${tmpDir}"
  fi
  trap - INT TERM EXIT
  exit
}

function seek_confirmation() {
  # Asks questions of a user and then does something with the answer.
  # y/n are the only possible answers.
  #
  # USAGE:
  # seek_confirmation "Ask a question"
  # if is_confirmed; then
  #   some action
  # else
  #   some other action
  # fi
  #
  # Credt: https://github.com/kevva/dotfiles
  # ------------------------------------------------------

  input "$@"
  if ${force}; then
    notice "Forcing confirmation with '--force' flag set"
  else
    read -p " (y/n) " -n 1
    echo ""
  fi
}

function is_confirmed() {
  if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
    return 0
  fi
  return 1
}

function is_not_confirmed() {
  if [[ "${REPLY}" =~ ^[Nn]$ ]]; then
    return 0
  fi
  return 1
}

# Set Flags
# -----------------------------------
# Flags which can be overridden by user input.
# Default values are below
# -----------------------------------
quiet=false
printLog=false
verbose=false
force=false
strict=false
debug=false
args=()

# Set Temp Directory
# -----------------------------------
# Create temp directory with three random numbers and the process ID
# in the name.  This directory is removed automatically at exit.
# -----------------------------------
tmpDir="/tmp/${scriptName}.$RANDOM.$RANDOM.$RANDOM.$$"
(umask 077 && mkdir "${tmpDir}") || {
  die "Could not create temporary directory! Exiting."
}

# Logging
# -----------------------------------
# Log is only used when the '-l' flag is set.
#
# To never save a logfile change variable to '/dev/null'
# Save to Desktop use: $HOME/Desktop/${scriptName}.log
# Save to standard user log location use: $HOME/Library/Logs/${scriptName}.log
# -----------------------------------
logFile="${HOME}/Desktop/${scriptName}.log"


# Options and Usage
# -----------------------------------
# Print usage
usage() {
  echo -n "${scriptName} [OPTION]...

This is a bash script to generate resources and the image.
Based on https://github.com/actions/virtual-environments/blob/master/helpers/GenerateResourcesAndImage.ps1

 ${bold}Options:${reset}

 Required Variables:

  -b | --SubscriptionId                 Azure Subscription ID to use.
  -g | --ResourceGroupName              Resource Group name to use.
  -p | --ImageGenerationRepositoryRoot  Local path to store images in. (FIXME - add in example path)
  -i | --ImageType                      Which image to create. (FIXME - List of supported images here)
  -r | --AzureLocation                  Azure Region to use in long hand notation. eg \"Australia East\"

 Optional Variables:

  --force           Skip all user interaction.  Implied 'Yes' to all actions.
  -q, --quiet       Quiet (no output)
  -l, --log         Print log to file
  -s, --strict      Exit script with null variables.  i.e 'set -o nounset'
  -v, --verbose     Output more information. (Items echoed to 'verbose')
  -d, --debug       Runs script in BASH debug mode (set -x)
  -h, --help        Display this help and exit
      --version     Output version information and exit
  "
}

# Iterate over options breaking -ab into -a -b when needed and --foo=bar into
# --foo bar
optstring=h
unset options
while (($#)); do
  case $1 in
      # If option is of type -ab
    -[!-]?*)
      # Loop over each character starting with the second
      for ((i=1; i < ${#1}; i++)); do
        c=${1:i:1}

        # Add current char to options
        options+=("-$c")

        # If option takes a required argument, and it's not the last char make
        # the rest of the string its argument
        if [[ $optstring = *"$c:"* && ${1:i+1} ]]; then
          options+=("${1:i+1}")
          break
        fi
      done
      ;;

      # If option is of type --foo=bar
    --?*=*) options+=("${1%%=*}" "${1#*=}") ;;
      # add --endopts for --
    --) options+=(--endopts) ;;
      # Otherwise, nothing special
    *) options+=("$1") ;;
  esac
  shift
done
set -- "${options[@]}"
unset options

# Print help if no arguments were passed.
# Uncomment to force arguments when invoking the script
# -------------------------------------
[[ $# -eq 0 ]] && set -- "--help"

# Read the options and set stuff
while [[ $1 = -?* ]]; do
  case $1 in
    -h|--help) usage >&2; safeExit ;;
    --version) echo "$(basename $0) ${version}"; safeExit ;;
#    -u|--username) shift; username=${1} ;;
#    -p|--password) shift; echo "Enter Pass: "; stty -echo; read PASS; stty echo;
#      echo ;;
    -b|--subscriptionid) shift; YOURSUBSCRIPTIONID="{$1}" ;;
    -g|--resourcegroupname) shift; RGNAME="${1}" ;;
    -p|--ImageGenerationRepositoryRoot) shift; IMAGEROOT="${1}" ;;
    -i|--ImageType) shift; IMAGETYPE="${1}" ;;
    -r|--AzureLocation) shift; REGION="${1}" ;;
    -v|--verbose) verbose=true ;;
    -l|--log) printLog=true ;;
    -q|--quiet) quiet=true ;;
    -s|--strict) strict=true ;;
    -d|--debug) debug=true ;;
    --force) force=true ;;
    --endopts) shift; break ;;
    *)
        die "invalid option: '$1'." ;;
  esac
  shift
done

# Store the remaining part as arguments.
args+=("$@")


# Logging and Colors
# -----------------------------------------------------
# Here we set the colors for our script feedback.
# Example usage: success "sometext"
#------------------------------------------------------

# Set Colors
bold=$(tput bold)
reset=$(tput sgr0)
purple=$(tput setaf 171)
red=$(tput setaf 1)
green=$(tput setaf 76)
tan=$(tput setaf 3)
blue=$(tput setaf 38)
underline=$(tput sgr 0 1)

function _alert() {
  if [[ "${1}" = "emergency" ]]; then local color="${bold}${red}"; fi
  if [[ "${1}" = "error" ]]; then local color="${bold}${red}"; fi
  if [[ "${1}" = "warning" ]]; then local color="${red}"; fi
  if [[ "${1}" = "success" ]]; then local color="${green}"; fi
  if [[ "${1}" = "header" ]]; then local color="${bold}""${tan}"; fi
  if [[ "${1}" = "input" ]]; then local color="${bold}"; printLog="false"; fi
  if [[ "${1}" = "info" ]] || [[ "${1}" = "notice" ]]; then local color=""; fi
  # Don't use colors on pipes or non-recognized terminals
  if [[ "${TERM}" != "xterm"* ]] || [[ -t 1 ]]; then color=""; reset=""; fi

  # Print to $logFile
  if ${printLog}; then
    echo -e "$(date +"%m-%d-%Y %r") $(printf "[%9s]" "${1}") ${_message}" >> "${logFile}";
  fi

  # Print to console when script is not 'quiet'
  if ${quiet}; then
    return
  else
    echo -e "$(date +"%r") ${color}$(printf "[%9s]" "${1}") ${_message}${reset}";
  fi
}
function die ()       { local _message="${*} Exiting."; echo "$(_alert emergency)"; safeExit;}
function error ()     { local _message="${*}"; echo "$(_alert error)"; }
function warning ()   { local _message="${*}"; echo "$(_alert warning)"; }
function notice ()    { local _message="${*}"; echo "$(_alert notice)"; }
function info ()      { local _message="${*}"; echo "$(_alert info)"; }
function debug ()     { local _message="${*}"; echo "$(_alert debug)"; }
function success ()   { local _message="${*}"; echo "$(_alert success)"; }
function input()      { local _message="${*}"; echo -n "$(_alert input)"; }
function header()     { local _message="${*}"; echo "$(_alert header)"; }

# Log messages when verbose is set to "true"
verbose() { if ${verbose}; then debug "$@"; fi }

# Trap bad exits with your cleanup function
trap trapCleanup EXIT INT TERM

# Set IFS to preferred implementation
IFS=$' \n\t'

# Exit on error. Append '||true' when you run the script if you expect an error.
set -o errexit

# Run in debug mode, if set
if ${debug}; then set -x ; fi

# Exit on empty variable
if ${strict}; then set -o nounset ; fi

# Bash will remember & return the highest exitcode in a chain of pipes.
# This way you can catch the error in case mysqldump fails in `mysqldump |gzip`, for example.
set -o pipefail

# Run your script
mainScript

# Exit cleanly
safeExit
