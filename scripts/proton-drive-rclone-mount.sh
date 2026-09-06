#!/bin/bash
# Mounts a Proton Drive rclone remote, handling 2FA re-entry via a yad
# dialog and retrying on failure. Configuration is environment-driven.
#
# Env vars, all optional, sane defaults shown:
#   MOUNT_PATH     Where to mount the remote.        default: $HOME/ProtonDrive
#   RCLONE_REMOTE  Name of the configured remote.    default: ProtonDrive
#   RCLONE_CONFIG  Path to the rclone config file.   default: $HOME/.config/rclone/rclone.conf
#   LOGO_PATH      Icon passed to notify-send -i.    default: empty

set +m

MOUNT_PATH="${MOUNT_PATH:-$HOME/ProtonDrive}"
RCLONE_REMOTE="${RCLONE_REMOTE:-ProtonDrive}"
RCLONE_CONFIG="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
LOGO_PATH="${LOGO_PATH:-}"
export RCLONE_CONFIG

DRY_RUN=false
VERBOSE=false
EXTRA_VERBOSE=false

for arg in "$@"; do
    case $arg in
        -h|--help)
            echo "Proton Drive Rclone Mount Script"
            echo "Automatically mounts Proton Drive using rclone with 2FA handling"
            echo ""
            echo "Usage: $0 [-h|--help] [-d|--dry-run] [-v|--verbose] [-vv|--extra-verbose]"
            echo ""
            echo "Options:"
            echo "  -h, --help           Show this help message"
            echo "  -d, --dry-run        Show what would run, without running it"
            echo "  -v, --verbose        Enable detailed logging and output"
            echo "  -vv, --extra-verbose Enable extra verbose mode with all executed commands"
            echo ""
            echo "Environment:"
            echo "  MOUNT_PATH     Mount point (default: \$HOME/ProtonDrive)"
            echo "  RCLONE_REMOTE  Remote name (default: ProtonDrive)"
            echo "  RCLONE_CONFIG  Config file path (default: \$HOME/.config/rclone/rclone.conf)"
            echo "  LOGO_PATH      notify-send icon (default: none)"
            echo ""
            echo "Features:"
            echo "  - Mounts the Proton Drive remote to \$MOUNT_PATH"
            echo "  - Handles 2FA authentication with GUI prompts"
            echo "  - Automatic retry on mount failures"
            echo "  - Desktop notifications for status updates"
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            ;;
        -vv|--extra-verbose)
            VERBOSE=true
            EXTRA_VERBOSE=true
            ;;
        -v|--verbose)
            VERBOSE=true
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

if [ -t 1 ]; then  # Only use colors if output is to a terminal
    COLOR_RESET='\033[0m'
    COLOR_VERBOSE='\033[0;36m'    # Cyan
    COLOR_COMMAND='\033[0;33m'    # Yellow
    COLOR_DRY_RUN='\033[0;35m'    # Magenta
else
    COLOR_RESET=''
    COLOR_VERBOSE=''
    COLOR_COMMAND=''
    COLOR_DRY_RUN=''
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "${COLOR_DRY_RUN}DRY RUN MODE:${COLOR_RESET} Commands will be shown but not executed"
fi

if [ "$EXTRA_VERBOSE" = true ]; then
    echo -e "${COLOR_VERBOSE}EXTRA VERBOSE MODE:${COLOR_RESET} Detailed logging and command tracing enabled"
elif [ "$VERBOSE" = true ]; then
    echo -e "${COLOR_VERBOSE}VERBOSE MODE:${COLOR_RESET} Detailed logging enabled"
fi

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${COLOR_VERBOSE}[VERBOSE]${COLOR_RESET} $1"
    fi
}

log_command() {
    if [ "$EXTRA_VERBOSE" = true ]; then
        echo -e "${COLOR_COMMAND}[COMMAND]${COLOR_RESET} $1"
    fi
}

# Desktop notification helper. Only adds -i when LOGO_PATH is set.
send_notify() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"

    log_command "notify-send \"$title\" \"$message\" -a \"Proton Drive\" --urgency=$urgency${LOGO_PATH:+ -i $LOGO_PATH}"

    if [ -n "$LOGO_PATH" ]; then
        notify-send "$title" "$message" -a "Proton Drive" -i "$LOGO_PATH" --urgency="$urgency"
    else
        notify-send "$title" "$message" -a "Proton Drive" --urgency="$urgency"
    fi
}

get_2fa_code() {
	log_verbose "Prompting user for 2FA code"

	if [ "$DRY_RUN" = true ]; then
		echo -e "${COLOR_DRY_RUN}[DRY RUN]${COLOR_RESET} Would show 2FA input dialog"
		echo "123456" # Mock 2FA code for dry run
		echo "0" # Mock successful exit code
		return
	fi

	log_verbose "Launching YAD dialog for 2FA input"
	log_command "yad --center --title=\"2FA Required\" --text=\"Enter your new 2FA code for Proton Drive:\" --entry --hide-text --undecorated --width=400 --height=100"
	yad --center --title="2FA Required" --text="Enter your new 2FA code for Proton Drive:" --entry --hide-text --undecorated --width=400 --height=100
	local yad_exit=$?
	log_verbose "YAD dialog closed with exit code: $yad_exit"
	echo $yad_exit # Return exit status of yad for cancel detection
}

update_rclone_config() {
	local new_2fa_code="$1"
	local config_file="$RCLONE_CONFIG"

	log_verbose "Starting 2FA configuration update with code: ${new_2fa_code:0:3}***"

	if [ "$DRY_RUN" = true ]; then
		echo -e "${COLOR_DRY_RUN}[DRY RUN]${COLOR_RESET} Would update 2FA code in $config_file to: $new_2fa_code"
		echo -e "${COLOR_DRY_RUN}[DRY RUN]${COLOR_RESET} Would run: sed -i \"/^\[${RCLONE_REMOTE}\]/,/^\[.*\]/{s/^[[:space:]]*2fa[[:space:]]*=[[:space:]]*.*/2fa = ${new_2fa_code}/}\" \"$config_file\""
		return 0 # Mock success
	fi

	if [ ! -f "$config_file" ]; then
		log_verbose "ERROR: Rclone config file not found: $config_file"
		send_notify "Rclone Error" "Could not find Rclone configuration file at $config_file." critical
		return 1 # Indicate failure
	fi

	log_verbose "Using rclone config file: $config_file"
	echo "Updating Rclone configuration file: $config_file"
	echo "Searching for '2fa = ' below section '[${RCLONE_REMOTE}]' to update."

	log_verbose "Executing sed command to update 2FA line"
	log_command "sed -i \"/^\\[${RCLONE_REMOTE}\\]/,/^\\[.*\\]/{s/^[[:space:]]*2fa[[:space:]]*=[[:space:]]*.*/2fa = ${new_2fa_code}/}\" \"$config_file\""
	sed -i "/^\[${RCLONE_REMOTE}\]/,/^\[.*\]/{s/^[[:space:]]*2fa[[:space:]]*=[[:space:]]*.*/2fa = ${new_2fa_code}/}" "$config_file"
	local sed_exit=$?

	if [ $sed_exit -ne 0 ]; then
		log_verbose "ERROR: sed command failed with exit code: $sed_exit"
		send_notify "Rclone Error" "Failed to update Rclone configuration file. Check permissions or file format." critical
		return 1 # Indicate failure
	fi

	log_verbose "Verifying 2FA update in config file"
	log_command "grep -q -E \"^[[:space:]]*2fa[[:space:]]*=[[:space:]]*${new_2fa_code}\" \"$config_file\""
	if grep -q -E "^[[:space:]]*2fa[[:space:]]*=[[:space:]]*${new_2fa_code}" "$config_file"; then
		log_verbose "2FA update verification successful"
		echo "2FA line successfully updated in $config_file."
		return 0 # Indicate success
	else
		log_verbose "WARNING: 2FA update verification failed"
		send_notify "Rclone Warning" "2FA line might not have been updated correctly in config file."
		return 1 # Indicate failure (even if sed returned 0, verify the change)
	fi
}

log_verbose "Starting main mount loop"
log_verbose "Remote: $RCLONE_REMOTE, Mount path: $MOUNT_PATH, Config: $RCLONE_CONFIG"

while true; do
	echo "Attempting to mount $RCLONE_REMOTE..."
	log_verbose "Mount attempt started"

	if [ "$DRY_RUN" = true ]; then
		echo -e "${COLOR_DRY_RUN}[DRY RUN]${COLOR_RESET} Would execute: rclone mount \"$RCLONE_REMOTE\":/ \"$MOUNT_PATH\" --daemon --vfs-cache-mode full --poll-interval 10m"
		echo -e "${COLOR_DRY_RUN}[DRY RUN]${COLOR_RESET} Would send notification: Mounting was successful!"
		break # Exit loop in dry run mode
	fi

	log_verbose "Executing rclone mount command"
	log_command "rclone mount \"$RCLONE_REMOTE\":/ \"$MOUNT_PATH\" --daemon --vfs-cache-mode full --poll-interval 10m"
	output=$(rclone mount \
		"$RCLONE_REMOTE":/ \
		"$MOUNT_PATH" \
		--daemon \
		--vfs-cache-mode full \
		--poll-interval 10m 2>&1)

	exit_status=$?
	log_verbose "Rclone mount command completed with exit status: $exit_status"

	if [ $exit_status -eq 0 ]; then
		log_verbose "Mount successful, sending success notification"
		send_notify "$RCLONE_REMOTE Mount" "Mounting was successful!"
		break # Exit loop on success
	else
		log_verbose "Mount failed with exit status: $exit_status"
		log_verbose "Rclone output: $output"

		local_message="Mounting failed!"
		local_detail=""
		local_action_taken=false

		if [[ "$output" == *"2fa: Incorrect login credentials."* ]] ||
			[[ "$output" == *"Auth error: 2FA required."* ]]; then

			log_verbose "Detected 2FA authentication error"
			local_detail="2FA expired or incorrect."

			if [ "$DRY_RUN" = true ]; then
				echo -e "${COLOR_DRY_RUN}[DRY RUN]${COLOR_RESET} Would send notification: $local_message $local_detail. Prompting for new 2FA."
				echo -e "${COLOR_DRY_RUN}[DRY RUN]${COLOR_RESET} Would prompt for 2FA code and update configuration"
				local_action_taken=true
			else
				log_verbose "Sending 2FA error notification"
				send_notify "$RCLONE_REMOTE Mount" "$local_message $local_detail. Prompting for new 2FA." critical

				# get_2fa_code echoes two lines: the code, then yad's exit
				# status. Read each separately, a combined read only fills the first.
				{
					read -r new_2fa_code_entered
					read -r yad_exit_code
				} < <(get_2fa_code)

				if [ "$yad_exit_code" -ne 0 ]; then # YAD's exit code 1 is typically Cancel/No
					log_verbose "User cancelled 2FA input"
					send_notify "$RCLONE_REMOTE Mount" "2FA code input cancelled. Aborting." critical
					exit 1
				fi

				if [ -z "$new_2fa_code_entered" ]; then
					log_verbose "No 2FA code provided by user"
					send_notify "$RCLONE_REMOTE Mount" "2FA code not provided. Aborting." critical
					exit 1
				fi

				log_verbose "Received 2FA code from user, updating configuration"
				if update_rclone_config "$new_2fa_code_entered"; then
					local_action_taken=true
					log_verbose "2FA configuration updated successfully"
					send_notify "$RCLONE_REMOTE Mount" "2FA updated. Retrying mount."
				else
					log_verbose "Failed to update 2FA configuration"
					send_notify "$RCLONE_REMOTE Mount" "Failed to update 2FA configuration. Check it manually." critical
				fi
			fi
		else
			log_verbose "Non-2FA mount error detected"
			local_detail="An unexpected error occurred."
			echo "Failed output: $output" # Log the full output for debugging
		fi

		# If no action was taken, ask the user what to do next.
		if ! $local_action_taken; then
			log_verbose "No automatic action taken, prompting user for next step"

			if [ "$DRY_RUN" = true ]; then
				echo -e "${COLOR_DRY_RUN}[DRY RUN]${COLOR_RESET} Would show retry/cancel dialog for mount failure"
				echo -e "${COLOR_DRY_RUN}[DRY RUN]${COLOR_RESET} Would assume user selects 'Cancel' and exit"
				exit 1
			else
				log_verbose "Showing retry/cancel dialog to user"
				log_command "yad --center --title=\"$RCLONE_REMOTE Mount Failed\" --text=\"<b>$local_message</b>\\n\\n$local_detail\\n\\nWould you like to retry the mount?\" --button=\"Retry!gtk-refresh:0\" --button=\"Cancel!gtk-cancel:1\" --undecorated --width=450 --height=150"
				yad_response=$(yad --center --title="$RCLONE_REMOTE Mount Failed" \
					--text="<b>$local_message</b>\n\n$local_detail\n\nWould you like to retry the mount?" \
					--button="Retry!gtk-refresh:0" \
					--button="Cancel!gtk-cancel:1" \
					--undecorated --width=450 --height=150)

				yad_exit_code=$? # Capture yad's exit code for button pressed
				log_verbose "User dialog response: exit code $yad_exit_code"

				if [ "$yad_exit_code" -eq 1 ]; then # YAD's exit code for the second button (Cancel)
					log_verbose "User selected Cancel, exiting script"
					send_notify "$RCLONE_REMOTE Mount" "Mount attempt cancelled by user."
					exit 1 # Exit the script
				fi
				log_verbose "User selected Retry, continuing mount loop"
			fi
		fi
	fi
done

log_verbose "Script completed successfully"
exit 0 # Script successfully completed
