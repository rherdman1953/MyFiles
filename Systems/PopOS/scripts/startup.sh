#!/bin/bash

start_if_not_running() {
    local app_name="$1"
    local app_cmd="$2"

    if ! pgrep -f "$app_name" > /dev/null; then
        echo "Starting $app_name..."
        $app_cmd &
    else
        echo "$app_name is already running."
    fi
}

start_if_not_running "firefox" "firefox"
start_if_not_running "vivaldi-stable" "vivaldi-stable"
start_if_not_running "com.discordapp.Discord" "flatpak run com.discordapp.Discord"