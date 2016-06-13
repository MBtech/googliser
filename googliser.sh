#/bin/bash

# Copyright (C) 2016 Teracow Software

# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

# If you find this code useful, please let me know. :) teracow@gmail.com

# The latest copy can be found here [https://github.com/teracow/googliser]

# return values ($?):
#	0	completed successfully
#	1	required program unavailable (wget, perl, montage)
#	2	required parameter unspecified or wrong
#	3	could not create subdirectory for 'search phrase'
#	4	could not get a list of search results from Google
#	5	image download aborted as failure limit was reached
#	6	thumbnail gallery build failed

# debug log first character notation:
#	>	script entry
#	<	script exit
#	\	function entry
#	/	function exit
#	?	variable value
#	=	evaluation
#	~	variable had boundary issues so was set within bounds
#	$	success
#	!	failure
#	T	elapsed time

function Init
	{

	script_version="1.18"
	script_date="2016-06-13"
	script_name="$(basename -- "$(readlink -f -- "$0")")"
	local script_details="$(ColourTextBrightWhite "${script_name}") - v${script_version} (${script_date}) PID:[$$]"

	current_path="$PWD"
	temp_path="/dev/shm/$script_name.$$"
	pids_path="$temp_path/pids"

	mkdir -p "${temp_path}"

	image_file="google-image"
	gallery_name="googliser-gallery"
	imagelinks_file="download.links.list"
	debug_file="debug.log"

	results_success_count_path="${temp_path}/results.success.count"
	mkdir -p "${results_success_count_path}"

	results_fail_count_path="${temp_path}/results.fail.count"
	mkdir -p "${results_fail_count_path}"

	download_success_count_path="${temp_path}/download.success.count"
	mkdir -p "${download_success_count_path}"

	download_fail_count_path="${temp_path}/download.fail.count"
	mkdir -p "${download_fail_count_path}"

	results_pathfile="${temp_path}/results.page.html"
	gallery_title_pathfile="${temp_path}/gallery.title.png"
	gallery_thumbnails_pathfile="${temp_path}/gallery.thumbnails.png"
	gallery_background_pathfile="${temp_path}/gallery.background.png"

	debug_pathfile="${temp_path}/${debug_file}"
	imagelinks_pathfile="${temp_path}/${imagelinks_file}"

	server="www.google.com.au"

	# http://whatsmyuseragent.com
	useragent='Mozilla/5.0 (X11; Linux x86_64; rv:46.0) Gecko/20100101 Firefox/46.0'

	# internals
	script_starttime=$(date)
	script_startseconds=$(date +%s)
	result_index=0
	target_path_created=false
	helpme=false
	showversion=false
	showhelp=false
	results_max=1000
	parallel_max=40
	timeout_max=600
	retries_max=100

	# parameter defaults
	images_required_default=25
	parallel_limit_default=8
	fail_limit_default=40
	upper_size_limit_default=0
	lower_size_limit_default=1000
	timeout_default=15
	retries_default=3

	# user changable parameters
	images_required=$images_required_default
	parallel_limit=$parallel_limit_default
	fail_limit=$fail_limit_default
	upper_size_limit=$upper_size_limit_default
	lower_size_limit=$lower_size_limit_default
	timeout=$timeout_default
	retries=$retries_default
	user_query=""
	gallery_title=""
	create_gallery=true
	verbose=true
	debug=false
	links=false
	colourised=false

	WhatAreMyOptions

	exitcode=$?

	# display start
	if [ "$showversion" == "true" ] ; then
		echo "v${script_version} (${script_date})"
		verbose=false
	fi

	if [ "$verbose" == "true" ] ; then
		if [ "$colourised" == "true" ] ; then
			echo " ${script_details}"
		else
			echo " $(RemoveColourCodes "${script_details}")"
		fi

		echo
	fi

	[ "$showhelp" == "true" ] && DisplayHelp

	DebugThis "> started" "$script_starttime"
	DebugThis "? \$script_details" "$(RemoveColourCodes "${script_details}")"
	DebugThis "? \$user_parameters_raw" "$user_parameters_raw"
	DebugThis "= environment" "*** decoded user parameters ***"
	DebugThis "? \$user_query" "$user_query"
	DebugThis "? \$images_required" "$images_required"
	DebugThis "? \$fail_limit" "$fail_limit"
	DebugThis "? \$parallel_limit" "$parallel_limit"
	DebugThis "? \$timeout" "$timeout"
	DebugThis "? \$retries" "$retries"
	DebugThis "? \$upper_size_limit" "$upper_size_limit"
	DebugThis "? \$lower_size_limit" "$lower_size_limit"
	DebugThis "? \$gallery_title" "$gallery_title"
	DebugThis "? \$links" "$links"
	DebugThis "? \$colourised" "$colourised"
	DebugThis "? \$create_gallery" "$create_gallery"
	DebugThis "? \$verbose" "$verbose"
	DebugThis "= environment" "*** internal parameters ***"
	DebugThis "? \$results_max" "$results_max"
	DebugThis "? \$temp_path" "$temp_path"

	IsProgramAvailable "wget" || exitcode=1
	IsProgramAvailable "perl" || exitcode=1

	if [ "$create_gallery" == "true" ] ; then
		IsProgramAvailable "montage" || exitcode=1
		IsProgramAvailable "convert" || exitcode=1
	fi

	# 'nfpr=1' seems to perform exact string search - does not show most likely match results or suggested search.
	search_match_type="&nfpr=1"

	# 'tbm=isch' seems to search for images
	search_type="&tbm=isch"

	# 'q=' is the user supplied search query
	search_phrase="&q=$(echo $user_query | tr ' ' '+')"	# replace whitepace with '+' to suit curl/wget

	# 'hl=en' seems to be language
	search_language="&hl=en"

	# 'site=imghp' seems to be result layout style
	search_style="&site=imghp"

	}

function DisplayHelp
	{

	DebugThis "\ [${FUNCNAME[0]}]" "entry"

	local sample_user_query="cows"
	local message=" - search '"

	if [ "$colourised" == "true" ] ; then
		message+="$(ShowGoogle) $(ColourTextBrightBlue "images")"
	else
		message+="Google images"
	fi

	echo "${message}', download from each of the image URLs, then create a gallery image using ImageMagick."
	echo
	echo " - This is an expansion upon a solution provided by ShellFish on:"
	echo " [https://stackoverflow.com/questions/27909521/download-images-from-google-with-command-line]"
	echo
	echo " - Requirements: Wget and Perl"
	echo " - Optional: montage & convert (from ImageMagick)"
	echo
	echo " - Questions or comments? teracow@gmail.com"
	echo

	if [ "$colourised" == "true" ] ; then
		echo " - Usage: $(ColourTextBrightWhite "./$script_name") [PARAMETERS] ..."
	else
		echo " - Usage: ./$script_name [PARAMETERS] ..."
	fi

	echo
	echo " Mandatory arguments for long options are mandatory for short options too. Defaults values are shown in <>"
	echo

	if [ "$colourised" == "true" ] ; then
		echo " $(ColourTextBrightOrange "* Required *")"
	else
		echo " * Required *"
	fi

	HelpParameterFormat "p" "phrase [STRING]" "Search phrase. A sub-directory will be created with this name."
	echo
	echo " Optional"
	HelpParameterFormat "c" "colourised" "Output with ANSI coloured text."
	HelpParameterFormat "d" "debug" "Save debug log to file [$debug_file] in target directory."
	HelpParameterFormat "f" "failures [INTEGER] <$fail_limit_default>" "How many download failures before exiting? Use 0 for maximum ($results_max)."
	HelpParameterFormat "g" "no-gallery" "Don't create thumbnail gallery."
	HelpParameterFormat "h" "help" "Display this help then exit."
	HelpParameterFormat "i" "title [STRING] <phrase>" "Custom title for thumbnail gallery. Enclose whitespace in quotes."
	HelpParameterFormat "k" "links" "Save URL list to file [$imagelinks_file] in target directory."
	HelpParameterFormat "l" "lower-size [INTEGER] <$lower_size_limit_default>" "Only download images that are larger than this many bytes."
	HelpParameterFormat "n" "number [INTEGER] <$images_required_default>" "Number of images to download. Maximum of $results_max."
	HelpParameterFormat "p" "parallel [INTEGER] <$parallel_limit_default>" "How many parallel image downloads? Maximum of $parallel_max. Use wisely!"
	HelpParameterFormat "q" "quiet" "Suppress standard message output. Error messages are still shown."
	HelpParameterFormat "r" "retries [INTEGER] <$retries_default>" "Retry image download this many times. Maximum of $retries_max."
	HelpParameterFormat "t" "timeout [INTEGER] <$timeout_default>" "Number of seconds before aborting each attempt. Maximum of $timeout_max."
	HelpParameterFormat "u" "upper-size [INTEGER] <$upper_size_limit_default>" "Only download images that are smaller than this many bytes. Use 0 for unlimited."
	HelpParameterFormat "v" "version " "Show script version then exit."
	echo
	echo " - Example:"

	if [ "$colourised" == "true" ] ; then
		echo "$(ColourTextBrightWhite " $ ./$script_name -p \"${sample_user_query}\"")"
	else
		echo " $ ./$script_name -p \"${sample_user_query}\""
	fi

	echo
	echo " This will download the first $images_required available images for the search phrase \"${sample_user_query}\" and build them into a gallery image."

	DebugThis "/ [${FUNCNAME[0]}]" "exit"

	}

function HelpParameterFormat
	{

	# $1 = short parameter
	# $2 = long parameter
	# $3 = description

	printf "  -%-1s   --%-28s %s\n" "$1" "$2" "$3"

	}

function WhatAreMyOptions
	{

	# if getopt exited with an error then show help to user
	[ "$user_parameters_result" != "0" ] && echo && showhelp=true && return 2

	eval set -- "$user_parameters"

	while true
	do
		case "$1" in
			-n | --number )
				images_required="$2"
				shift 2		# shift to next parameter in $1
				;;
			-f | --failures )
				fail_limit="$2"
				shift 2		# shift to next parameter in $1
				;;
			-p | --phrase )
				user_query="$2"
				shift 2		# shift to next parameter in $1
				;;
			-p | --parallel )
				parallel_limit="$2"
				shift 2		# shift to next parameter in $1
				;;
			-t | --timeout )
				timeout="$2"
				shift 2		# shift to next parameter in $1
				;;
			-r | --retries )
				retries="$2"
				shift 2		# shift to next parameter in $1
				;;
			-u | --upper-size )
				upper_size_limit="$2"
				shift 2		# shift to next parameter in $1
				;;
			-l | --lower-size )
				lower_size_limit="$2"
				shift 2		# shift to next parameter in $1
				;;
			-i | --title )
				gallery_title="$2"
				shift 2		# shift to next parameter in $1
				;;
			-k | --links )
				links=true
				shift
				;;
			-h | --help )
				showhelp=true
				return 7
				;;
			-c | --colourised )
				colourised=true
				shift
				;;
			-g | --no-gallery )
				create_gallery=false
				shift
				;;
			-q | --quiet )
				verbose=false
				shift
				;;
			-d | --debug )
				debug=true
				shift
				;;
			-v | --version )
				showversion=true
				return 7
				;;
			-- )
				shift		# shift to next parameter in $1
				break
				;;
			* )
				break		# there are no more matching parameters
				;;
		esac
	done

	}

function IsProgramAvailable
	{

	# $1 = name of program to search for with 'which'
	# $? = 0 if 'which' found it, 1 if not

	which "$1" > /dev/null 2>&1

	if [ "$?" -gt "0" ] ; then
		echo " !! required program [$1] is unavailable ... unable to continue."
		echo
		DebugThis "! required program is unavailable" "$1"
		DisplayHelp
		return 1
	else
		DebugThis "$ required program is available" "$1"
		return 0
	fi

	}

function ShowGoogle
	{

	echo -n "$(ColourTextBrightBlue "G")$(ColourTextBrightRed "o")$(ColourTextBrightOrange "o")$(ColourTextBrightBlue "g")$(ColourTextBrightGreen "l")$(ColourTextBrightRed "e")"

	}

function DownloadResultGroup_auto
	{

	# *** This function runs as a background process ***
	# $1 = page group to load:		(0, 1, 2, 3, etc...)
	# $2 = pointer starts at result:	(0, 100, 200, 300, etc...)

	local success_pathfile="$results_success_count_path/$BASHPID"
	local fail_pathfile="$results_fail_count_path/$BASHPID"
	local result=0
	local search_group="&ijn=$1"
	local search_start="&start=$2"
	local response=""
	local debug_number=$(printf "#%02d" $1)

	DebugThis "- result group $debug_number download" "start"
	DebugThis "? result group $debug_number \$BASHPID" "$BASHPID"

	local wget_list_cmd="wget --quiet 'https://${server}/search?${search_type}${search_match_type}${search_phrase}${search_language}${search_style}${search_group}${search_start}' --user-agent '$useragent' --output-document \"${results_pathfile}.$1\""
	DebugThis "? result group $debug_number \$wget_list_cmd" "$wget_list_cmd"

	response=$(eval "$wget_list_cmd")
	result=$?

	if [ "$result" -eq "0" ] ; then
		DebugThis "$ result group $debug_number download" "success!"
		touch "$success_pathfile"
	else
		DebugThis "! result group $debug_number download" "failed! Wget returned: ($result - $(WgetReturnCodes "$result"))"
		touch "$fail_pathfile"
	fi

	return 0

	}

function DownloadResultGroups
	{

	DebugThis "\ [${FUNCNAME[0]}]" "entry"

	local func_startseconds=$(date +%s)
	local groups_max=$(($results_max/100))
	local pointer=0
	local parallel_count=0

	InitProgress

	if [ "$verbose" == "true" ] ; then
		if [ "$colourised" == "true" ] ; then
#			echo -n " -> searching $(ColourTextBrightBlue "G")$(ColourTextBrightRed "o")$(ColourTextBrightOrange "o")$(ColourTextBrightBlue "g")$(ColourTextBrightGreen "l")$(ColourTextBrightRed "e"): "
			echo -n " -> searching $(ShowGoogle): "
		else
			echo -n " -> searching Google: "
		fi
	fi

	for ((group=1; group<=$groups_max; group++)) ; do
		ShowResultDownloadProgress

		if [ "$parallel_count" -eq "$parallel_limit" ] ; then
			# wait here while all running downloads finish
			# when all current downloads have finished, then start next batch

			wait
		fi

		while true; do
			ShowResultDownloadProgress

  			[ "$parallel_count" -lt "$parallel_limit" ] && break

			sleep 0.5
		done

		pointer=$((($group-1)*100))

		# derived from: http://stackoverflow.com/questions/24284460/calculating-rounded-percentage-in-shell-script-without-using-bc
# 		percent="$((200*($group-1)/$groups_max % 2 + 100*($group-1)/$groups_max))% "

		DownloadResultGroup_auto $(($group-1)) "$pointer" &
	done

	# wait here while all running downloads finish
	wait

	ShowResultDownloadProgress

	[ "$parallel_count" -gt "0" ] && DebugThis "! found some leftover parallel!" "$parallel_count ($(jobs -l))"

	# build all groups into a single file
	cat "${results_pathfile}".* > "${results_pathfile}"
	#rm -f "${results_pathfile}".*

	ParseResults

	[ "$fail_count" -gt "0" ] && result=1 || result=0

	DebugThis "T [${FUNCNAME[0]}] elapsed time" "$(ConvertSecs "$(($(date +%s)-$func_startseconds))")"
	DebugThis "/ [${FUNCNAME[0]}]" "exit"

	return $result

	}

function DownloadImage_auto
	{

	# *** This function runs as a background process ***
	# $1 = URL to download
	# $2 = current counter relative to main list

	local success_pathfile="$download_success_count_path/$BASHPID"
	local fail_pathfile="$download_fail_count_path/$BASHPID"
	local result=0
	local size_ok=true
	local get_download=true
	local response=""
	local debug_number=$(printf "#%04d" $2)

	DebugThis "- link $debug_number download" "start"
	DebugThis "? link $debug_number \$BASHPID" "$BASHPID"

	# extract file extension by checking only last 5 characters of URL (to handle .jpeg as worst case)
	ext=$(echo ${1:(-5)} | sed "s/.*\(\.[^\.]*\)$/\1/")

	[[ "$ext" =~ "." ]] || ext=".jpg"	# if URL did not have a file extension then choose jpg as default

	targetimage_pathfileext="${targetimage_pathfile}($2)${ext}"

	# are file size limits going to be applied before download?
	if [ "$upper_size_limit" -gt "0" ] || [ "$lower_size_limit" -gt "0" ] ; then
		# try to get file size from server
		local wget_server_response_cmd="wget --spider --server-response --max-redirect 0 --timeout=${timeout} --tries=${retries} --user-agent \"$useragent\" \"${imagelink}\" 2>&1"
		DebugThis "? link $debug_number \$wget_server_response_cmd" "$wget_server_response_cmd"

		response=$(eval "$wget_server_response_cmd")
		result=$?

		if [ "$result" -eq "0" ] ; then
			estimated_size=$(grep -v "Access-Control-Expose-Headers:" <<< "$response" | sed -ne '/Content-Length/{s/.*: //;p}')

			if [ -z "$estimated_size" ] || [ "$estimated_size" == "unspecified" ] ; then
				estimated_size="unknown"
			fi

			DebugThis "? link $debug_number \$estimated_size" "$estimated_size bytes"

			if [ "$estimated_size" != "unknown" ] ; then
				if [ "$estimated_size" -lt "$lower_size_limit" ] ; then
					DebugThis "! link $debug_number (before download) is too small!" "$estimated_size bytes < $lower_size_limit bytes"
					size_ok=false
					get_download=false
				fi

				if [ "$upper_size_limit" -gt "0" ] && [ "$estimated_size" -gt "$upper_size_limit" ] ; then
					DebugThis "! link $debug_number (before download) is too large!" "$estimated_size bytes > $upper_size_limit bytes"
					size_ok=false
					get_download=false
				fi
			fi
		else
			DebugThis "! link $debug_number (before download) server-response" "failed!"
			estimated_size="unknown"
		fi
	fi

	# perform actual image download
	if [ "$get_download" == "true" ] ; then
		local wget_download_cmd="wget --max-redirect 0 --timeout=${timeout} --tries=${retries} --user-agent \"$useragent\" --output-document \"${targetimage_pathfileext}\" \"${imagelink}\" 2>&1"
		DebugThis "? link $debug_number \$wget_download_cmd" "$wget_download_cmd"

		response=$(eval "$wget_download_cmd")
		result=$?

		if [ "$result" -eq "0" ] ; then
			# http://stackoverflow.com/questions/36249714/parse-download-speed-from-wget-output-in-terminal
			download_speed=$(grep -o '\([0-9.]\+ [KM]B/s\)' <<< "$response")

			if [ -e "${targetimage_pathfileext}" ] ; then
				actual_size=$(wc -c < "$targetimage_pathfileext")

				if [ "$actual_size" == "$estimated_size" ] ; then
					DebugThis "? link $debug_number \$actual_size" "$actual_size bytes (estimate was correct)"
				else
					DebugThis "? link $debug_number \$actual_size" "$actual_size bytes (estimate of $estimated_size bytes was incorrect)"
				fi

				if [ "$actual_size" -lt "$lower_size_limit" ] ; then
					DebugThis "! link $debug_number \$actual_size (after download) is too small!" "$actual_size bytes < $lower_size_limit bytes"
					rm -f "$targetimage_pathfileext"
					size_ok=false
				fi

				if [ "$upper_size_limit" -gt "0" ] && [ "$actual_size" -gt "$upper_size_limit" ] ; then
					DebugThis "! link $debug_number \$actual_size (after download) is too large!" "$actual_size bytes > $upper_size_limit bytes"
					rm -f "$targetimage_pathfileext"
					size_ok=false
				fi
			else
				# file does not exist
				size_ok=false
			fi

			if [ "$size_ok" == "true" ] ; then
				DebugThis "$ link $debug_number download" "success!"
				touch "$success_pathfile"
				DebugThis "? link $debug_number \$download_speed" "$download_speed"
			else
				# files that were outside size limits still count as failures
				touch "$fail_pathfile"
			fi
		else
			DebugThis "! link $debug_number download" "failed! Wget returned $result ($(WgetReturnCodes "$result"))"
			touch "$fail_pathfile"

			# delete temp file if one was created
			[ -e "${targetimage_pathfileext}" ] && rm -f "${targetimage_pathfileext}"
		fi
	else
		touch "$fail_pathfile"
	fi

	return 0

	}

function DownloadImages
	{

	DebugThis "\ [${FUNCNAME[0]}]" "entry"

	local func_startseconds=$(date +%s)
	local result_index=0
	local file_index=1
	local message=""
	local countdown=$images_required		# control how many files are downloaded. Counts down to zero.
	local result=0

	[ "$verbose" == "true" ] && echo -n " -> acquiring images: "

	InitProgress

	while read imagelink; do
		while true; do
			ShowImageDownloadProgress

			[ "$parallel_count" -lt "$parallel_limit" ] && break

			sleep 0.5
		done

		if [ "$countdown" -gt "0" ] ; then
			# some images are still required
			if [ "$fail_count" -ge "$fail_limit" ] ; then
				# but too many failures so stop downloading.
 				result=1

 				# wait here while all running downloads finish
				wait

 				break
 			fi

			((result_index++))

			DownloadImage_auto "$msg" "$result_index" &
			((countdown--))
		else
			# can't start any more concurrent downloads yet so kill some time
			# wait here while all running downloads finish
			wait

			ShowImageDownloadProgress

			# how many were successful?
			if [ "$success_count" -lt "$images_required" ] ; then
				# not enough yet, so go get some more
				# increase countdown again to get remaining files
				countdown=$(($images_required-$success_count))
			else
				break
			fi
		fi
	done < "${imagelinks_pathfile}"

	# wait here while all running downloads finish
	wait

	ShowImageDownloadProgress

	if [ "$fail_count" -ge "$fail_limit" ] ; then
		DebugThis "! failure limit reached" "$fail_count/$fail_limit"

		if [ "$colourised" == "true" ] ; then
			echo "$(ColourTextBrightRed "Too many failures!")"
		else
			echo "Too many failures!"
		fi
	else
		[ "$verbose" == "true" ] && echo
	fi

	[ "$parallel_count" -gt "0" ] && DebugThis "! found some leftover parallel!" "$parallel_count ($(jobs -l))"

	DebugThis "? \$success_count" "$success_count"
	DebugThis "? \$fail_count" "$fail_count"
	DebugThis "T [${FUNCNAME[0]}] elapsed time" "$(ConvertSecs "$(($(date +%s )-$func_startseconds))")"
	DebugThis "/ [${FUNCNAME[0]}]" "exit"

	return $result

	}

function ParseResults
	{

	DebugThis "\ [${FUNCNAME[0]}]" "entry"

	result_count=0

	#------------- when Google change their web-code again, these regexes will need to be changed too --------------
	#
	# sed   1. look for lines with '<div' and insert 2 linefeeds before them
	#
	# grep  2. only list lines with '<div class="rg_meta">' and eventually followed by 'http'
	#
	# grep  3. only list lines without 'youtube' or 'vimeo' (case insenstive)
	#
	# perl  4. remove everything from '<div class="rg_meta">' up to 'http' on each line
	#       5. remove everything including and after '","ow"' on each line
	#       6. remove everything including and after '?' on each line

	cat "${results_pathfile}" |\
	sed 's|<div|\n\n<div|g' |\
	grep '<div class=\"rg_meta\">.*http' |\
	grep -ivE 'youtube|vimeo' |\
	perl -pe 's|(<div class="rg_meta">)(.*?)(http)|\3|; s|","ow".*||; s|\?.*||' \
	> "${imagelinks_pathfile}"
	#---------------------------------------------------------------------------------------------------------------

	if [ -e "$imagelinks_pathfile" ] ; then
		result_count=$(wc -l < "${imagelinks_pathfile}")

		if [ "$verbose" == "true" ] ; then
			if [ "$colourised" == "true" ] ; then
				echo "$(ColourTextBrightWhite "${result_count}") results!"
			else
				echo "${result_count} results!"
			fi
		fi
	else
		if [ "$verbose" == "true" ] ; then
			if [ "$colourised" == "true" ] ; then
				echo "$(ColourTextBrightRed "No results!")"
			else
				echo "No results!"
			fi
		fi
	fi

	DebugThis "? \$result_count" "$result_count"
	DebugThis "/ [${FUNCNAME[0]}]" "exit"

	}

function BuildGallery
	{

	local title_font="Century-Schoolbook-L-Bold-Italic"
	local title_colour="goldenrod1"

	DebugThis "\ [${FUNCNAME[0]}]" "entry"

	local func_startseconds=$(date +%s)

	InitProgress

	if [ "$verbose" == "true" ] ; then
		echo -n " -> building gallery: "
		ProgressUpdater "stage 1/4 (construct thumbnails)"
	fi

	# build gallery
	build_foreground_cmd="montage \"${target_path}/*[0]\" -background none -shadow -geometry 400x400 miff:- | convert - -background none -gravity north -splice 0x140 -bordercolor none -border 30 \"${gallery_thumbnails_pathfile}\""

	DebugThis "? \$build_foreground_cmd" "$build_foreground_cmd"

	eval $build_foreground_cmd 2> /dev/null
	result=$?

	if [ "$result" -eq "0" ] ; then
		DebugThis "$ \$build_foreground_cmd" "success!"
	else
		DebugThis "! \$build_foreground_cmd" "failed! montage returned: ($result)"
	fi

	if [ "$result" -eq "0" ] ; then
		[ "$verbose" == "true" ] && ProgressUpdater "stage 2/4 (draw background pattern)"

		# get image dimensions
		read -r width height <<< $(convert -ping "${gallery_thumbnails_pathfile}" -format "%w %h" info:)

		# create a dark image with light sphere in centre
		build_background_cmd="convert -size ${width}x${height} radial-gradient:WhiteSmoke-gray10 \"${gallery_background_pathfile}\""

		DebugThis "? \$build_background_cmd" "$build_background_cmd"

		eval $build_background_cmd 2> /dev/null
		result=$?

		if [ "$result" -eq "0" ] ; then
			DebugThis "$ \$build_background_cmd" "success!"
		else
			DebugThis "! \$build_background_cmd" "failed! convert returned: ($result)"
		fi
	fi

	if [ "$result" -eq "0" ] ; then
		[ "$verbose" == "true" ] && ProgressUpdater "stage 3/4 (draw title text image)"

		# create title image
		# let's try a fixed height of 100 pixels
		build_title_cmd="convert -size x100 -font $title_font -background none -stroke black -strokewidth 10 label:\"${gallery_title}\" -blur 0x5 -fill $title_colour -stroke none label:\"${gallery_title}\" -flatten \"${gallery_title_pathfile}\""

		DebugThis "? \$build_title_cmd" "$build_title_cmd"

		eval $build_title_cmd 2> /dev/null
		result=$?

		if [ "$result" -eq "0" ] ; then
			DebugThis "$ \$build_title_cmd" "success!"
		else
			DebugThis "! \$build_title_cmd" "failed! convert returned: ($result)"
		fi
	fi

	if [ "$result" -eq "0" ] ; then
		[ "$verbose" == "true" ] && ProgressUpdater "stage 4/4 (compile all images)"

		# compose thumbnails image on background image, then title image on top
		build_compose_cmd="convert \"${gallery_background_pathfile}\" \"${gallery_thumbnails_pathfile}\" -gravity center -composite \"${gallery_title_pathfile}\" -gravity north -geometry +0+25 -composite \"${target_path}/${gallery_name}-($safe_query).png\""

		DebugThis "? \$build_compose_cmd" "$build_compose_cmd"

		eval $build_compose_cmd 2> /dev/null
		result=$?

		if [ "$result" -eq "0" ] ; then
			DebugThis "$ \$build_compose_cmd" "success!"
		else
			DebugThis "! \$build_compose_cmd" "failed! convert returned: ($result)"
		fi
	fi

	[ -e "${gallery_title_pathfile}" ] && rm -f "${gallery_title_pathfile}"
	[ -e "${gallery_thumbnails_pathfile}" ] && rm -f "${gallery_thumbnails_pathfile}"
	[ -e "${gallery_background_pathfile}" ] && rm -f "${gallery_background_pathfile}"

	if [ "$result" -eq "0" ] ; then
		DebugThis "$ [${FUNCNAME[0]}]" "success!"
		if [ "$verbose" == "true" ] ; then
			if [ "$colourised" == "true" ] ; then
				ProgressUpdater "$(ColourTextBrightGreen "done!")"
			else
				ProgressUpdater "done!"
			fi
		fi
	else
		DebugThis "! [${FUNCNAME[0]}]" "failed! See previous!"
		[ "$verbose" == "true" ] && echo "failed!"
	fi

	DebugThis "T [${FUNCNAME[0]}] elapsed time" "$(ConvertSecs "$(($(date +%s)-$func_startseconds))")"
	DebugThis "/ [${FUNCNAME[0]}]" "exit"

	return $result

	}

function InitProgress
	{

	# needs to be called prior to first call of ProgressUpdater

	previous_length=0
	previous_msg=""

	}

function ProgressUpdater
	{

	# $1 = message to display.

	if [ "$1" != "$previous_msg" ] ; then
		temp=$(RemoveColourCodes "$1")
		current_length=$((${#temp}+1))

		if [ "$current_length" -lt "$previous_length" ] ; then
			appended_length=$(($current_length-$previous_length))
			# backspace to start of previous msg, print new msg, add additional spaces, then backspace to end of msg
			printf "%${previous_length}s" | tr ' ' '\b' ; echo -n "$1 " ; printf "%${appended_length}s" ; printf "%${appended_length}s" | tr ' ' '\b'
		else
			# backspace to start of previous msg, print new msg
			printf "%${previous_length}s" | tr ' ' '\b' ; echo -n "$1 "
		fi

		previous_length=$current_length
		previous_msg="$1"
	fi

	}

function ShowResultDownloadProgress
	{

	success_count=$(ls "$results_success_count_path" | wc -l )
	fail_count=$(ls "$results_fail_count_path" | wc -l )
	parallel_count=$(jobs -l | grep Running | wc -l)

	if [ "$verbose" == "true" ] ; then
		if [ "$colourised" == "true" ] ; then
			if [ "$success_count" -eq "$groups_max" ] ; then
				progress_message="$(ColourTextBrightGreen "${success_count}/${groups_max}")"
			else
				progress_message="$(ColourTextBrightOrange "${success_count}/${groups_max}")"
			fi
		else
			progress_message="${success_count}/${groups_max}"
		fi

		progress_message+=" result groups downloaded."

		ProgressUpdater "${progress_message}"
	fi

	}

function ShowImageDownloadProgress
	{

	success_count=$(ls "$download_success_count_path" | wc -l )
	fail_count=$(ls "$download_fail_count_path" | wc -l )
	parallel_count=$(jobs -l | grep Running | wc -l)

	if [ "$verbose" == "true" ] ; then
		# number of image downloads that are OK
		if [ "$colourised" == "true" ] ; then
			progress_message="$(ColourTextBrightGreen "${success_count}/${images_required}")"
		else
			progress_message="${success_count}/${images_required}"
		fi

		progress_message+=" downloaded"

		# show the number of files currently downloading (if any)
		if [ "$parallel_count" -gt "0" ] ; then
			progress_message+=", "

			if [ "$colourised" == "true" ] ; then
				progress_message+="$(ColourTextBrightOrange "${parallel_count}/${parallel_limit}")"
			else
				progress_message+="${parallel_count}/${parallel_limit}"
			fi

			progress_message+=" are in progress"
		fi

		# include failures (if any)
		if [ "$fail_count" -gt "0" ] ; then
			progress_message+=" and "

			if [ "$colourised" == "true" ] ; then
				progress_message+="$(ColourTextBrightRed "${fail_count}/${fail_limit}")"
			else
				progress_message+="${fail_count}/${fail_limit}"
			fi

			progress_message+=" failed"
		fi

 		progress_message+="."

		ProgressUpdater "${progress_message}"
	fi

	}

function DebugThis
	{

	# $1 = item
	# $2 = value

	echo "$1: '$2'" >> "${debug_pathfile}"

	}

function WgetReturnCodes
	{

	# converts a return code from wget into a text string explanation of the code
	# https://gist.github.com/cosimo/5747881#file-wget-exit-codes-txt

	# $1 = wget return code
	# echo = text string

	case "$1" in
		0 )
			echo "No problems occurred"
			;;
		2 )
			echo "Parse error — for instance, when parsing command-line options, the .wgetrc or .netrc…"
			;;
		3 )
			echo "File I/O error"
			;;
		4 )
			echo "Network failure"
			;;
		5 )
			echo "SSL verification failure"
			;;
		6 )
			echo "Username/password authentication failure"
			;;
		7 )
			echo "Protocol errors"
			;;
		8 )
			echo "Server issued an error response"
			;;
		* )
			echo "Generic error code"
			;;
	esac

	}

function ConvertSecs
	{

	# http://stackoverflow.com/questions/12199631/convert-seconds-to-hours-minutes-seconds
	# $1 = a time in seconds to convert to 'hh:mm:ss'

	((h=${1}/3600))
	((m=(${1}%3600)/60))
	((s=${1}%60))

	printf "%02dh:%02dm:%02ds\n" $h $m $s

	}

function ColourTextBrightWhite
	{

	echo -en '\E[1;97m'"$(PrintResetColours "$1")"

	}

function ColourTextBrightGreen
	{

	echo -en '\E[1;32m'"$(PrintResetColours "$1")"

	}

function ColourTextBrightOrange
	{

	echo -en '\E[1;38;5;214m'"$(PrintResetColours "$1")"

	}

function ColourTextBrightRed
	{

	echo -en '\E[1;31m'"$(PrintResetColours "$1")"

	}

function ColourTextBrightBlue
	{

	echo -en '\E[1;94m'"$(PrintResetColours "$1")"

	}

function PrintResetColours
	{

	echo -en "$1"'\E[0m'

	}

function RemoveColourCodes
	{

	# http://www.commandlinefu.com/commands/view/3584/remove-color-codes-special-characters-with-sed
	echo -n "$1" | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g"

	}

function ShowAsFailed
	{

	# $1 = message to show in colour if colourised is set

	if [ "$colourised" == "true" ] ; then
		echo -n "$(ColourTextBrightRed "$1")"
	else
		echo -n "$1"
	fi

	}

function ShowAsSucceed
	{

	# $1 = message to show in colour if colourised is set

	if [ "$colourised" == "true" ] ; then
		echo -n "$(ColourTextBrightGreen "$1")"
	else
		echo -n "$1"
	fi

	}

# check for command-line parameters
user_parameters=$(getopt -o h,g,d,k,q,v,c,i:,l:,u:,r:,t:,p:,f:,n:,p: --long help,no-gallery,debug,links,quiet,version,colourised,title:,lower-size:,upper-size:,retries:,timeout:,parallel:,failures:,number:,phrase: -n $(readlink -f -- "$0") -- "$@")
user_parameters_result=$?
user_parameters_raw="$@"

Init

# user parameter validation and bounds checks
if [ "$exitcode" -eq "0" ] ; then
	case ${images_required#[-+]} in
		*[!0-9]* )
			DebugThis "! specified \$images_required" "invalid"
			DisplayHelp
			echo
			echo "$(ShowAsFailed " !! number specified after (-n --number) must be a valid integer ... unable to continue.")"
			exitcode=2
			;;
		* )
			if [ "$images_required" -lt "1" ] ; then
				images_required=1
				DebugThis "~ \$images_required too small so set sensible minimum" "$images_required"
			fi

			if [ "$images_required" -gt "$results_max" ] ; then
				images_required=$results_max
				DebugThis "~ \$images_required too large so set as \$results_max" "$images_required"
			fi
			;;
	esac

	if [ "$exitcode" -eq "0" ] ; then
		case ${fail_limit#[-+]} in
			*[!0-9]* )
				DebugThis "! specified \$fail_limit" "invalid"
				DisplayHelp
				echo
				echo "$(ShowAsFailed " !! number specified after (-f --failures) must be a valid integer ... unable to continue.")"
				exitcode=2
				;;
			* )
				if [ "$fail_limit" -le "0" ] ; then
					fail_limit=$results_max
					DebugThis "~ \$fail_limit too small so set as \$results_max" "$fail_limit"
				fi

				if [ "$fail_limit" -gt "$results_max" ] ; then
					fail_limit=$results_max
					DebugThis "~ \$fail_limit too large so set as \$results_max" "$fail_limit"
				fi
				;;
		esac
	fi

	if [ "$exitcode" -eq "0" ] ; then
		case ${parallel_limit#[-+]} in
			*[!0-9]* )
				DebugThis "! specified \$parallel_limit" "invalid"
				DisplayHelp
				echo
				echo "$(ShowAsFailed " !! number specified after (-p --parallel) must be a valid integer ... unable to continue.")"
				exitcode=2
				;;
			* )
				if [ "$parallel_limit" -lt "1" ] ; then
					parallel_limit=1
					DebugThis "~ \$parallel_limit too small so set as" "$parallel_limit"
				fi

				if [ "$parallel_limit" -gt "$parallel_max" ] ; then
					parallel_limit=$parallel_max
					DebugThis "~ \$parallel_limit too large so set as" "$parallel_limit"
				fi
				;;
		esac
	fi

	if [ "$exitcode" -eq "0" ] ; then
		case ${timeout#[-+]} in
			*[!0-9]* )
				DebugThis "! specified \$timeout" "invalid"
				DisplayHelp
				echo
				echo "$(ShowAsFailed " !! number specified after (-t --timeout) must be a valid integer ... unable to continue.")"
				exitcode=2
				;;
			* )
				if [ "$timeout" -lt "1" ] ; then
					timeout=1
					DebugThis "~ \$timeout too small so set as" "$timeout"
				fi

				if [ "$timeout" -gt "$timeout_max" ] ; then
					timeout=$timeout_max
					DebugThis "~ \$timeout too large so set as" "$timeout"
				fi
				;;
		esac
	fi

	if [ "$exitcode" -eq "0" ] ; then
		case ${retries#[-+]} in
			*[!0-9]* )
				DebugThis "! specified \$retries" "invalid"
				DisplayHelp
				echo
				echo "$(ShowAsFailed " !! number specified after (-r --retries) must be a valid integer ... unable to continue.")"
				exitcode=2
				;;
			* )
				if [ "$retries" -lt "1" ] ; then
					retries=1
					DebugThis "~ \$retries too small so set as" "$retries"
				fi

				if [ "$retries" -gt "$retries_max" ] ; then
					retries=$retries_max
					DebugThis "~ \$retries too large so set as" "$retries"
				fi
				;;
		esac
	fi

	if [ "$exitcode" -eq "0" ] ; then
		case ${upper_size_limit#[-+]} in
			*[!0-9]* )
				DebugThis "! specified \$upper_size_limit" "invalid"
				DisplayHelp
				echo
				echo "$(ShowAsFailed " !! number specified after (-u --upper-size) must be a valid integer ... unable to continue.")"
				exitcode=2
				;;
			* )
				if [ "$upper_size_limit" -lt "0" ] ; then
					upper_size_limit=0
					DebugThis "~ \$upper_size_limit too small so set as" "$upper_size_limit (unlimited)"
				fi
				;;
		esac
	fi

	if [ "$exitcode" -eq "0" ] ; then
		case ${lower_size_limit#[-+]} in
			*[!0-9]* )
				DebugThis "! specified \$lower_size_limit" "invalid"
				DisplayHelp
				echo
				echo "$(ShowAsFailed " !! number specified after (-l --lower-size) must be a valid integer ... unable to continue.")"
				exitcode=2
				;;
			* )
				if [ "$lower_size_limit" -lt "0" ] ; then
					lower_size_limit=0
					DebugThis "~ \$lower_size_limit too small so set as" "$lower_size_limit"
				fi

				if [ "$upper_size_limit" -gt "0" ] && [ "$lower_size_limit" -gt "$upper_size_limit" ] ; then
					lower_size_limit=$(($upper_size_limit-1))
					DebugThis "~ \$lower_size_limit larger than \$upper_size_limit ($upper_size_limit) so set as" "$lower_size_limit"
				fi
				;;
		esac
	fi

	if [ "$exitcode" -eq "0" ] ; then
		if [ ! "$user_query" ] ; then
			DebugThis "! \$user_query" "unspecified"
			DisplayHelp
			echo
			echo "$(ShowAsFailed " !! search phrase (-p --phrase) was unspecified ... unable to continue.")"
			exitcode=2
		else
			safe_query="$(echo $user_query | tr ' ' '_')"	# replace whitepace with '_' so less issues later on!
			DebugThis "? \$safe_query" "$safe_query"
			target_path="${current_path}/${safe_query}"
			DebugThis "? \$target_path" "$target_path"
			targetimage_pathfile="${target_path}/${image_file}"
		fi
	fi

	if [ "$exitcode" -eq "0" ] ; then
		if [ ! "$gallery_title" ] ; then
			gallery_title=$user_query
			DebugThis "~ \$gallery_title was unspecified so set as" "$gallery_title"
		fi
	fi
fi

# create directory for search phrase
if [ "$exitcode" -eq "0" ] ; then
	if [ -e "${target_path}" ] ; then
		DebugThis "! create sub-directory [${target_path}]" "failed! Sub-directory already exists!"
		echo "$(ShowAsFailed " !! sub-directory [${target_path}] already exists ... unable to continue.")"
		exitcode=3
	fi

	if [ "$exitcode" -eq "0" ] ; then
		mkdir -p "${target_path}"
		result=$?

		if [ "$result" -gt "0" ] ; then
			DebugThis "! create sub-directory [${target_path}]" "failed! mkdir returned: ($result)"
			echo "$(ShowAsFailed " !! couldn't create sub-directory [${target_path}] ... unable to continue.")"
			exitcode=3
		else
			DebugThis "$ create sub-directory [${target_path}]" "success!"
			target_path_created=true
		fi
	fi
fi

# get list of search results
if [ "$exitcode" -eq "0" ] ; then
	DownloadResultGroups

	if [ "$?" -gt "0" ] ; then
		echo "$(ShowAsFailed " !! couldn't download Google search results ... unable to continue.")"
		exitcode=4
	else
		if [ "$fail_limit" -gt "$result_count" ] ; then
			fail_limit=$result_count
			DebugThis "~ \$fail_limit too high so set as \$result_count" "$fail_limit"
		fi
	fi
fi

# download images and build gallery
if [ "$exitcode" -eq "0" ] ; then
	DownloadImages

	[ "$?" -gt "0" ] && exitcode=5
fi

# build thumbnail gallery even if fail_limit was reached
if [ "$exitcode" -eq "0" ] || [ "$exitcode" -eq "5" ] ; then
	if [ "$create_gallery" == "true" ] ; then
		BuildGallery

		if [ "$?" -gt "0" ] ; then
			echo "$(ShowAsFailed " !! couldn't build thumbnail gallery ... unable to continue (but we're all done anyway).")"
			exitcode=6
		fi
	fi
fi

# copy links file into target directory if possible. If not, then copy to current directory.
if [ "$exitcode" -eq "0" ] ; then
	if [ "$links" == "true" ] ; then
		if [ "$target_path_created" == "true" ] ; then
			cp -f "${imagelinks_pathfile}" "${target_path}/${imagelinks_file}"
		else
			cp -f "${imagelinks_pathfile}" "${current_path}/${imagelinks_file}"
		fi
	fi
fi

# write results into debug file
DebugThis "T [$script_name] elapsed time" "$(ConvertSecs "$(($(date +%s)-$script_startseconds))")"
DebugThis "< finished" "$(date)"

# copy debug file into target directory if possible. If not, then copy to current directory.
if [ "$debug" == "true" ] ; then
	if [ "$target_path_created" == "true" ] ; then
		[ -e "${target_path}/${debug_file}" ] && echo "" >> "${target_path}/${debug_file}"

		cp -f "${debug_pathfile}" "${target_path}/${debug_file}"
	else
		# append to current path debug file (if it exists)
		[ -e "${current_path}/${debug_file}" ] && echo "" >> "${current_path}/${debug_file}"

		cat "${debug_pathfile}" >> "${current_path}/${debug_file}"
	fi
fi

# display end
if [ "$verbose" == "true" ] ; then
	case "$exitcode" in
		0 )
			echo
			echo " -> $(ShowAsSucceed "All done!")"
			;;
		[1-6] )
			echo
			echo " -> $(ShowAsFailed "All done! (with errors)")"
			;;
		* )
			;;
	esac
fi

# reset exitcode if only displaying info
if [ "$showversion" == "true" ] || [ "$showhelp" == "true" ] ; then
	exitcode=0
fi

exit $exitcode
