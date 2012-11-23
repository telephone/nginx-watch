#!/bin/bash
###############################################################
#                         Nginx Watch                         #
#            The closest thing to Nginx .htaccess             #
#                                                             #
# author      Nick Adams <nick89@zoho.com>                    #
# copyright   2012 Nick Adams.                                #
# link        http://iamtelephone.com                         #
# license     http://opensource.org/licenses/MIT  MIT License #
# version     1.0.0                                           #
###############################################################

##
# Alert this user if an error occurs while reloading Nginx
# - Leave blank to disable
##
ALERT_USER="root"

##
# Name/pattern to match config files (in web root)
# - Matches all files that end with '.nginx.conf'
##
CONFIG_PATTERN=".nginx.conf"

##
# When enabled, output actions
# - Leave blank to disable
##
DEBUG_MODE="y"

##
# Nginx config file
# - Absolute path to your Nginx config file
##
NGINX_CONFIG="/etc/nginx/nginx.conf"

##
# Regex pattern/s to ignore files/folders
# - Sets ignore for inotify and config files
##
REGEX_EXCLUDE="(/\.git/(.*)|sample.nginx.conf)$"

##
# Watched directory
# - Absolute path to your web root/www directory
##
WWW_DIR="/var/www/"

###########################################
####### DO NOT EDIT BELOW THIS LINE #######
###########################################

##
# Continuous loop to watch configured directory
##
while true; do
  # Ensure WWW directory exists
  if [ ! -d "$WWW_DIR" ]; then
    echo -e "Directory: '${WWW_DIR}' does not exist\nExiting..."
    exit 1
  fi

  # Debug message
  [ -n "$DEBUG_MODE" ] && echo -e "Watching directory: '${WWW_DIR}'\n"

  # Watch WWW directory for Nginx config files
  while FILE=$(inotifywait -q -r -e create,delete,modify,move \
    --excludei "$REGEX_EXCLUDE" "$WWW_DIR" --format "%f:%e"); do

    # Split result into array (Compensate for whitespace)
    IFS=: read -a PARAM <<< "$FILE"

    # Find matching config files (*.nginx.conf)
    if [[ "${PARAM[0]}" =~ "$CONFIG_PATTERN"$ ]]; then
      # Debug message
      [ -n "$DEBUG_MODE" ] && echo -e "Action: ${PARAM[1]}\nFile: ${PARAM[0]}"

      # Only rebuild (find) on create, delete, move
      if [ "${PARAM[1]}" != 'MODIFY' ]; then
        # Change regex to accommodate new line ending
        REGEX=$(echo "$REGEX_EXCLUDE" | sed -e "s/\$$/';$/")

        # Find all .nginx.conf in web directory & exclude those that match regex
        LIST=$(find "$WWW_DIR" -type f -name *.nginx.conf -print0 \
          | xargs -0 -I {} echo "\tinclude '{}';" | grep -E -v "$REGEX")
        [ -n "$LIST" ] && LIST="\n${LIST}\n" || LIST="${LIST}\n"

        # Check for existing 'Nginx Watch' block
        LINE=$(grep 'Nginx Watch Start' "$NGINX_CONFIG")
        if [ $? == 0 ]; then
          # Rebuild include/s
          TMP=$(awk -v "list=$(echo -e "$LIST")" '/Nginx Watch Start/ \
            {print; print list; skip = 1} /Nginx Watch End/ \
            {skip = 0} skip == 0 {print}' "$NGINX_CONFIG")
          echo "$TMP" > "$NGINX_CONFIG"
        else
          # Find http{} block
          HTTP=$(sed -n -e '/http\s{\|http{/,/}/p' "$NGINX_CONFIG" \
            | sed '1d;$d')
          # Add include/s
          HTTP="${HTTP}\n\n\t##### Nginx Watch Start #####\n"
          while read -r line; do
            HTTP="${HTTP}${line}\n"
          done <<< "$LIST"
          HTTP="${HTTP}\t##### Nginx Watch End #####"

          # Write new http{} block with watch blocks
          TMP=$(awk -v "HTTP=$(echo -e "$HTTP")" '/http {/ {print; print HTTP;
            skip = 1} /}/ {skip = 0} skip == 0 {print}' \
            "$NGINX_CONFIG")
          echo "$TMP" > "$NGINX_CONFIG"
        fi
      fi
      # Reload Nginx
      RELOAD=$(/etc/init.d/nginx reload 2>&1 1> /dev/null)

      # Check for errors while reloading
      if [ "$RELOAD" ]; then
        # Debug message
        [ -n "$DEBUG_MODE" ] && echo -e "Nginx reload: FAIL\n$RELOAD\n"

        # Check if user is online
        LINE=$(w | grep "$ALERT_USER")
        if [ -n "$ALERT_USER" ] && [ $? == 0 ]; then
          # Echo Nginx output to user
          $(echo "$RELOAD" | write "$ALERT_USER")
        fi
      else
        # Debug message
        [ -n "$DEBUG_MODE" ] && echo -e "Nginx reload: OK\n"
      fi
    fi
  done
done