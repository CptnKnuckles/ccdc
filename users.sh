#!/bin/sh
# User account auditing script
# Written by Peter Pilarski for EMUSec competitions

readPWs() {
	if [ -e /etc/shadow ]; then
		pwFile="/etc/shadow"
	elif [ -e /etc/master.passwd ]; then
		pwFile="/etc/master.passwd"
	else
		pwFile="/etc/passwd"
	fi
	while read line; do
		checkPW "$line"
	done < "$pwFile"
}
checkPW() { # Check passwords
	case $line in "#"*) return;; esac # Portable "if line begins with #" test. Skip line if true.
	user="$(echo "$line" | cut -s -d: -f 1)"
	pass="$(echo "$line" | cut -s -d: -f 2)"

	if [ "$(grep "^${user}:" $pwFile | cut -d":" -f 8)" = "1" ] || [ "$(echo "$pass" | grep "^\*LK\**")" ] || [ "$(echo "$pass" | grep "\*LOCKED\*")" ]; then
		printf "%s\t- Locked, no auth allowed. Skipping.\n" "$user"
		
	# *, !, UP, *x13 = password disabled. May still log in via other means (ssh key, etc)
	elif [ "$pass" = "*" ] || [ "$pass" = "UP" ] || [ "$(echo "$pass" | grep "^!*$")" ] || [ "$pass" = "*************" ]; then
		if [ "$(uname)" = "OpenBSD" ] && [ "$pass" = "*" ]; then
			printf "%s\t- Locked, no auth allowed. Skipping.\n" "$user"
			return
		fi
		printf "%s\t- Password disabled, but not locked.\n" "$user"
		shelledUsers "$user"

	# Blank password = open without authentication. This user better not have a shell.
	elif [ "$pass" = "" ] || [ "$pass" = "NP" ]; then
		printf "%s\t- WARNING: blank password!\n" "$user"
		shelledUsers "$user"
		
	# Valid and enabled password
	elif [ "$(echo "$pass" | grep "^\$*\$*\$*")" ]; then
		printf "%s\t- Allows password auth.\n" "$user"
		shelledUsers "$user"
	fi
}
shelledUsers() {
	userPwd="$(grep ^${1}: /etc/passwd)"
	userID="$(echo $userPwd | cut -s -d ":" -f 3)"
	userGECOS="$(echo $userPwd | cut -s -d ":" -f 5)"
	userHome="$(echo $userPwd | cut -s -d ":" -f 6)"
	userSh="$(echo $userPwd | cut -s -d ":" -f 7)"
	if [ "${userSh##*/}" != "nologin" ] && [ "${userSh##*/}" != "false" ]; then
		if [ ! -e "$userSh" ] || [ -e /etc/shells ] && [ ! "$(grep "^$userSh$" /etc/shells 2>/dev/null)" ]; then
			return
		fi
		# Print shell, UID, home, and GECOS
		printf "\n - Shell:\t %s\n - Home:\t %s\n - UID:\t\t %s\n - Comment:\t %s\n" "$userSh" "$userHome" "$userID" "$userGECOS"
		echo " - Select an action for $1:
	1)  Change password
	2)  Disable account
	3)  Delete account
	0)  Skip"
		read changePW < /dev/tty # explicitly read from TTY ($pwFile redirected to STDIN)
		case $changePW in
			1) #change pass
				passwd $1 < /dev/tty ;;
			2) #lock
				if [ "$(uname)" = "FreeBSD" ]; then
					echo "Locking account: $1"
					pw lock $1
				elif [ "$(uname)" = "OpenBSD" ]; then
					echo "Locking account: $1"
					usermod -Z $1
				else
					echo "Locking account: $1"
					passwd -l $1
				fi
				[ -e "$(which usermod 2>/dev/null)" ] && usermod -e 1 $1 2>/dev/null;; # Expire account 
			3) #delete
				if [ -e "$(which userdel 2>/dev/null)" ]; then
					echo "Deleting account: $1"
					userdel -r $1
				elif [ -e "$(which deluser 2>/dev/null)" ]; then
					echo "Deleting account: $1"
					deluser --remove-home $1
				elif [ -e "$(which pw 2>/dev/null)" ]; then
					echo "Deleting account: $1"
					pw userdel -r $1
				fi ;;
			0) #skip 
				;;
		esac
	fi
	return
}
readPWs
