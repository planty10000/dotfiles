 	#!/usr/bin/env sh

#versioning system:
#major.minor.bugs
YTFZF_VERSION="2.2.alpha-32"

# Scraping: query -> video json
# User Interface: video json -> user selection -> ID
# Player: ID -> video player

# error codes:
# 0: success
# 1: general error
# 2: invalid -opt or command argument, invalid argument for opt, configuration error
	# eg: ytfzf -c terminal (invalid scrape)
# 3: missing dependancy
# 4: scraping error
# 5: empty search

# colors {{{
c_red="\033[1;31m"
c_green="\033[1;32m"
c_yellow="\033[1;33m"
c_blue="\033[1;34m"
c_magenta="\033[1;35m"
c_cyan="\033[1;36m"
c_reset="\033[0m"
#}}}

# debugging
: ${log_level:=2}

#state variables
: "${__is_submenu:=0}"
: "${__is_scrape_for_submenu:=0}"
: "${__is_fzf_preview:=0}"

# Utility functions {{{

source_scrapers () {
	set -f
	IFS=","
	for _scr in $scrape; do
		if [ -f "$YTFZF_CUSTOM_SCRAPERS_DIR/$_scr" ]; then
			. "${YTFZF_CUSTOM_SCRAPERS_DIR}/$_scr"
		elif [ -f "$YTFZF_SYSTEM_ADDON_DIR/scrapers/$_scr" ]; then
			. "${YTFZF_SYSTEM_ADDON_DIR}/scrapers/$_scr"
		fi
		command_exists "on_startup_$_scr" && on_startup_$_scr
	done
	unset IFS
}

add_commas () {
	awk '
		{
			for(i=length($1); i>0; i--){
				if(i % 3 == 0 && i != length($1)){
					printf ","
				}
				printf substr($1, length($1) - i, 1)
			}
		}
		END{
			#print a new line
			print ""
		}'
}

command_exists () {
	command -v "$1" > /dev/null 2>&1
}

get_key_value() {
	value="${1##* ${2}=}"
	printf "%s" "${value%% *}"
	unset value
}

#capitalizes the first letter of a string
title_str () {
	printf "%s" "$1" | dd bs=1 count=1 conv=ucase 2>/dev/null
	printf "%s\n" "${1#?}"
}

#backup shuf function, as shuf is not posix
command_exists "shuf" || shuf () {
	awk -F'\n' 'BEGIN{srand()} {print rand() " " $0}' | sort -n | sed -E 's/[^ ]* //'
}

print_info () {
	# information goes to stdout ( does not disturb show_link_only )
	[ $log_level -ge 0 ] && printf "$1" >&2
}
print_warning () {
	[ $log_level -ge 1 ] && printf "${c_yellow}${1}${c_reset}" >&2
}
print_error () {
	[ $log_level -ge 2 ] && printf "${c_red}${1}${c_reset}" >&2
}

clean_up () {
	# print_info "cleaning up\n"
	# clean up only as parent process
	#kill ytfzf sub process{{{
	#i think this needs to be written to a file becuase of sub-shells
	jobs_file="${session_cache_dir:-/tmp}/the-jobs-need-to-be-written-to-a-file.list"
	jobs -p > "$jobs_file"
	while read -r line; do
		[ "$line" ] && kill "$line" 2> /dev/null
	done < "$jobs_file"
	#}}}
	if [ $__is_fzf_preview -eq 0 ]; then
		[ -d "$session_cache_dir" ] && [ $keep_cache -eq 0 ] && rm -r "$session_cache_dir"
	fi
	command_exists  "on_clean_up" && on_clean_up
}

is_relative_dir () {
	case "$1" in
		../*|./*|~/*|/*) return 0 ;;
	esac
	return 1
}

die () {
	_return_status=$1
	print_error "$2"
	exit "$_return_status"
}

trim_url () {
	while IFS= read _line;do
		printf '%s\n' "${_line##*|}"
	done
}

command_exists "quick_menu" || quick_menu () {
	fzf --reverse --prompt="$1"
}
command_exists "quick_menu_ext" || quick_menu_ext (){
	external_menu "$1"
}
command_exists "quick_menu_scripting" || quick_menu_scripting () {
	quick_menu "$1"
}

quick_menu_wrapper () {
	prompt="$1"
	fn_name=quick_menu$(printf "%s" "${interface:+_$interface}" | sed 's/-/_/g')
	if command_exists "$fn_name"; then
		$fn_name "$prompt"
	else quick_menu_ext "$prompt"
	fi
	unset fn_name
}

# Traps {{{
[ $__is_fzf_preview -eq 0 ] && trap 'clean_up' EXIT
[ $__is_fzf_preview -eq 0 ] && trap 'exit' INT TERM HUP
#}}}

# }}}

# Global Variables and Start Up {{{

# expansions where the variable is a string and globbing shouldn't happen should be surrounded by quotes
# variables that cannot be empty should use := instead of just =

# hard dependancy checks{{{
for dep in jq curl; do
	command_exists "$dep" || die 3 "$dep is a required dependency, please install it\n"
done
#}}}


#configuration handling {{{
: "${YTFZF_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/ytfzf}"
: "${YTFZF_CONFIG_FILE:=$YTFZF_CONFIG_DIR/conf.sh}"
: "${YTFZF_SUBSCRIPTIONS_FILE:=$YTFZF_CONFIG_DIR/subscriptions}"
: "${YTFZF_THUMBNAIL_VIEWERS_DIR:=$YTFZF_CONFIG_DIR/thumbnail-viewers}"
: "${YTFZF_SORT_NAMES_DIR:=$YTFZF_CONFIG_DIR/sort-names}"
: "${YTFZF_CUSTOM_INTERFACES_DIR:=$YTFZF_CONFIG_DIR/interfaces}"
: "${YTFZF_URL_HANDLERS_DIR:=$YTFZF_CONFIG_DIR/url-handlers}"
: "${YTFZF_CUSTOM_THUMBNAILS_DIR:=$YTFZF_CONFIG_DIR/thumbnails}"

: "${YTFZF_SYSTEM_ADDON_DIR:=/usr/local/share/ytfzf/addons}"

[ -f "$YTFZF_CONFIG_FILE" ] && . "$YTFZF_CONFIG_FILE"
#}}}

# Custom Scrapers {{{
: "${YTFZF_CUSTOM_SCRAPERS_DIR:=$YTFZF_CONFIG_DIR/scrapers}"
#}}}

: "${useragent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.152 Safari/537.36}"

# menu options
#the menu to use instead of fzf when -D is specified
command_exists "external_menu" || external_menu () {
	#dmenu extremely laggy when showing tabs
	tr -d '\t' | dmenu -i -l 30 -p "$1"
}

command_exists "search_prompt_menu" || search_prompt_menu () {
	printf "Search\n>"
	read -r _search
	printf "\033[1A\033[K\r%s\n" "> $_search"
}
command_exists "search_prompt_menu_ext" || search_prompt_menu_ext () {
	_search="$(printf '' | external_menu "Search: ")"
}
command_exists "search_prompt_menu_scripting" || search_prompt_menu_scripting () {
	search_prompt_menu
}

search_prompt_menu_wrapper () {
	#the last sed is to set it to quick_menu if $interfce is "" (default)
	[ $use_search_hist -eq 1 ] && { _search="$(parse_search_hist_file < "$search_hist_file" | quick_menu_wrapper)"; return; }
	 fn_name=search_prompt_menu"$(printf "%s" "${interface:+_$interface}" | sed 's/-/_/g')"
	 #we could do :
	 # $fn_name 2>/dev/null || [ "$?" -eq 127 ] && search_prompt_menu_ext
	 #however, if we do that, the user won't get their error messages from their script
	 if command_exists "$fn_name"; then
		 $fn_name
	 else search_prompt_menu_ext
	 fi
}

: ${enable_submenus:=1}

: ${submenu_opts=}
: ${submenu_scraping_opts=}

: ${interface=}

: ${fancy_subs:=0}
: "${fancy_subs_left=-------------}"
: "${fancy_subs_right="${fancy_subs_left}"}"

: "${enable_back_button:=1}"

: "${fzf_preview_side:=left}"

: "${thumbnail_viewer:=ueberzug}"

: "${w3mimgdisplay_path:=/usr/lib/w3m/w3mimgdisplay}"

# shortcuts
: "${download_shortcut:=alt-d}"
: "${video_shortcut:=alt-v}"
: "${audio_shortcut:=alt-m}"
: "${detach_shortcut:=alt-e}"
: "${print_link_shortcut:=alt-l}"
: "${show_formats_shortcut:=alt-f}"
: "${info_shortcut:=alt-i}"
: "${search_again_shortcut:=alt-s}"
: "${next_page_shortcut:=alt-p}"

: "${custom_shortcut_binds=}"
: "${shortcut_binds:=Enter,double-click,${next_page_shortcut},${download_shortcut},${video_shortcut},${audio_shortcut},${detach_shortcut},${print_link_shortcut},${show_formats_shortcut},${info_shortcut},${search_again_shortcut},${custom_shortcut_binds}}"

#number of columns (characters on a line) the external menu can have
: ${external_menu_len:=210}

: ${is_loop:=0}
: ${search_again:=0}

# Notifications

: ${notify_playing:=0}

command_exists "handle_playing_notifications" || handle_playing_notifications (){
	#if no notify-send push error to /dev/null
	[ $# -le 1 ] && {
		IFS="$tab_space"
		while read -r id title; do
			notify-send -c ytfzf -i "$thumb_dir/${id}.jpg" "Ytfzf Info" "Opening: $title" 2>/dev/null
		done <<-EOF
		$(jq -r '.[]|select(.url=="'"$@"'")|"\(.ID)\t\(.title)"' < "$ytfzf_video_json_file")
		EOF
	} || { notify-send -c ytfzf "ytfzf info" "Opening: $# videos" 2>/dev/null; }
}

# urlhandlers
#job of url handlers is:
# handle the given urls, and take into account some requested attributes, eg: video_pref, and --detach
# print what the handler is doing
command_exists "video_player" || video_player () {
	#this function should not be set as the url_handler as it is part of multimedia_player
	command_exists "mpv" || die 3 "mpv is not installed\n"
	case "$is_detach" in
		0) mpv --ytdl-format="$video_pref" "$@" ;;
		1) setsid -f mpv --ytdl-format="$video_pref" "$@" > /dev/null 2>&1 ;;
	esac
}
command_exists "audio_player" || audio_player () {
	#this function should not be set as the url_handler as it is part of multimedia_player
	command_exists "mpv" || die 3 "mpv is not installed\n"
	case "$is_detach" in
		0) mpv --no-video --ytdl-format="$video_pref" "$@" ;;
		1) setsid -f mpv --force-window --no-video --ytdl-format="$video_pref" "$@"  > /dev/null 2>&1 ;;
	esac
}
command_exists "multimedia_player" || multimedia_player () {
	#this function differentiates whether or not audio_only was requested
	case "$is_audio_only" in
		0) video_player "$@" ;;
		1) audio_player "$@" ;;
	esac
}
command_exists "downloader" || downloader () {
	command_exists "${ytdl_path}" || die 3 "${ytdl_path} is not installed\n"
	case $is_audio_only in
	    0) ${ytdl_path} -f "${video_pref}" $ytdl_opts "$@"	;;
	    1) ${ytdl_path} -x $ytdl_opts "$@" ;;
	esac
}

[ -z "$ytdl_path" ] && { command_exists "yt-dlp" && ytdl_path="yt-dlp" || ytdl_path="youtube-dl"; }

# directories
: "${cache_dir:=${XDG_CACHE_HOME:-$HOME/.cache}/ytfzf}"

: "${keep_cache:=0}"

# files
: "${hist_file:=$cache_dir/watch_hist}"
: "${search_hist_file:=$cache_dir/search_hist}"

command_exists "parse_search_hist_file" || parse_search_hist_file () {
	awk -F"${tab_space}" '{ if ($2 == "") {print $1} else {print $2} }'
}

# history
: ${enable_hist:=1}
: ${enable_search_hist:=1}
: ${use_search_hist:=0}

# format options
#variable for switching on sort (date)
: ${is_detach:=0}
: ${is_audio_only:=0}
: "${url_handler:=multimedia_player}"
: ${info_to_print=}
: ${info_wait_action=q}
: "${info_wait:=0}"
: "${video_pref:=best}"
: ${show_formats:=0}

: ${is_sort:=0}
: ${show_thumbnails:=0}
: ${skip_thumb_download:=0}

: ${scripting_video_count:=1}
: ${is_random_select:=0}
: ${is_auto_select:=0}
: ${is_specific_select:=0}

# option parsing
: "${long_opt_char:=-}"

# scrape
: "${scrape=youtube}"
#this comes from invidious' api
: "${thumbnail_quality=high}"
: ${sub_link_count:=2}
: "${invidious_instance:=https://vid.puffyan.us}"
: "${yt_video_link_domain:=https://youtube.com}"
: ${pages_to_scrape:=1}
: ${odysee_video_search_count:=30}

: "${search_sort_by:=relevance}"
: "${search_upload_date=}"
: "${search_video_duration=}"
: "${search_result_type:=video}"
: "${search_result_features=}"
: "${search_region:=US}"

: "${multi_search:=0}"

: "${nsfw:=false}"

: "${custom_scrape_search_exclude=}"
: "${scrape_search_exclude:= youtube-subscriptions S SI T youtube-trending H history ${custom_scrape_search_exclude} }"

: ${max_thread_count:=20}


# Option Checks {{{
case "$long_opt_char" in
        [a-uw-zA-UW-Z0-9]) die 2 "long_opt_char must be v or non alphanumeric\n" ;;
	#? = 1 char, * = 1+ chars; ?* = 2+ chars
	??*) die 2 "long_opt_char must be 1 char\n" ;;
esac
#}}}

new_line='
'
tab_space=$(printf '\t')
: "${gap_space:=                                                                                                                   }"

# }}}

usage () {
	printf "%s" \
"Usage: ytfzf [OPTIONS...] <search-query>
    The search-query can also be read from stdin
    OPTIONS:
	-h			Show this help text
	-d			Download the selected video(s)
	-m			Only play audio
	-f                      Select a video format before playing
	-l                      Reopen the menu when the video stops playing
	-s                      After closing fzf make another search
	-q                      Use a search query from search history
	-L			Show the link of selected video(s)
	-a                      Automatically select the first video
	-r                      Automatically select a random video
	-A                      Select all videos
	-S <number>             Automatically selects a specific video
	-n <video count>        The amount of videos to select with -a and -r
	-c <scraper>       	The scraper to use,
				Builtin scrapers:
				    youtube/Y, youtube-trending/T, youtube-subscriptions/S/SI,
				    peertube/P, odysee/lbry/O,
				    history/H,
				    url/U,
				    youtube-playlist
				    	instead of giving a search, give a link to a playlist
				    youtube-channel
				    	instead of giving a search, give a link to a channel
				    comments
				    	scrapes a comments json file produced by ytfzf
				    * SI scrapes invidious for channels instead of youtube,
				    * Y and T both scrape invidious
				you can use multiple scrapers by separating each with a , eg: youtube,odysee
	-H                      alias for -c H
	-t			Show thumbnails
	--thumb-viewer=viewer   The program to use for displaying thumbnails.
	-D			Use an external menu
	-I <info>               Instead of playing the selected video(s), get information about them.
				Options can be separated with a comma, eg: L,R
	                        Options for info:
				    L:         print the link of the video
				    VJ:        print the json of the video
				    J:         print the json of all videos shown in the search
				    R:         print the data of the selected videos, as appears in the menu
				    F:         print the selected video format
        -x                       Clear search and watch history (use --history-clear=<search|watch> to specify 1)
	--disable-submenus       Whether or not to disable submenus, which are menus for things like playlists and channels
	--version                Get the current version
    See ytfzf(1) and ytfzf(5) for more information.
"
}


# Scraping {{{
# * a scraper function takes a search query as $1 and returns video json to file $2
# * argument 3 and above are undefined and can be used for filters
# * return codes:
#            5 : scrape is disabled
#            6 : no response from site (matches curl)
#            22: error scraping site (matches curl)

# Json keys:
#	Needed:
#	ID url title
#	Optional:
#	thumbs channel duration views date description

# Scraping backends {{{
_get_request () {
	_base_url=$1
	shift 1
	# Get search query from youtube
	curl -f "$_base_url" -s -L \
		"$@" \
		-H "User-Agent: $useragent" \
		-H 'Accept-Language: en-US,en;q=0.9' \
		--compressed
}

_start_series_of_threads () {
	_thread_count=0
}

_thread_started (){
	_latest_fork="$1"
	_thread_count=$((_thread_count+1))
	[ $_thread_count -ge $max_thread_count ] && wait "$_latest_fork" && _thread_count=$(jobs -p | wc -l)
}

#}}}

## Youtube  {{{
# Youtube backend functions {{{

_youtube_channel_name () {
	# takes channel page html (stdin) and returns the channel name
	grep -o '[<]title[>].*[<]/title[>]' |
		sed \
		-e 's/ - YouTube//' \
		-e 's/<\/\?title>//g' \
		-e "s/&apos;/'/g" \
		-e "s/&#39;/'/g" \
		-e "s/&quot;/\"/g" \
		-e "s/&#34;/\"/g" \
		-e "s/&amp;/\&/g" \
		-e "s/&#38;/\&/g"
}

_youtube_get_json (){
       # Separates the json embedded in the youtube html page
       # * removes the content after ytInitialData
       # * removes all newlines and trims the json out
       sed -n '/var *ytInitialData/,$p' |
               tr -d '\n' |
               sed -E ' s_^.*var ytInitialData ?=__ ; s_;</script>.*__ ;'
}

_youtube_channel_json () {
	channel_name=$1
	jq '[ .contents | ..|.gridVideoRenderer? | select(. !=null) |
	    {
		scraper: "youtube_search",
	    	ID: .videoId,
		url: "'"$yt_video_link_domain"'/watch?v=\(.videoId)",
		title: "\(if .title.simpleText then .title.simpleText else .title.runs[0].text end)",
	    	channel: "'"$channel_name"'",
	    	thumbs: .thumbnail.thumbnails[0].url|sub("\\?.*";""),
	    	duration:.thumbnailOverlays[0].thumbnailOverlayTimeStatusRenderer.text.simpleText,
	    	views: .shortViewCountText.simpleText,
	    	date: .publishedTimeText.simpleText,
	    }
	]'
}
#}}}

scrape_subscriptions () {
    ! [ -f "$YTFZF_SUBSCRIPTIONS_FILE" ] && die 2 "subscriptions file doesn't exist\n"

    [ "$scrape_type" = "SI" ] && { channel_scraper="scrape_invidious_channel"; sleep_time=0.03; } || { channel_scraper="scrape_youtube_channel"; sleep_time=0.01; }

    #if _tmp_subfile does not have a unique name, weird things happen
    #must be _i because scrape_invidious_channel uses $i
    _i=0
    while IFS= read channel_url || [ -n "$channel_url" ] ; do
	    _i=$((_i+1))
	    {
			_tmp_subfile="${session_temp_dir}/channel-$_i"
			$channel_scraper "$channel_url" "$_tmp_subfile" "channel-$_i" < /dev/null || return "$?"
			if [ ${fancy_subs} -eq 1 ]; then
				jq --arg left "${fancy_subs_left}" --arg right "${fancy_subs_right}" '"\($left + .[0].channel + $right)" as $div | [{"title": $div, "action": "do-nothing", "url": $div, "ID": "subscriptions-channel:\(.[0].channel)" }]' < "$_tmp_subfile"
			fi >> "$ytfzf_video_json_file"
			jq '.[0:'"$sub_link_count"']' < "$_tmp_subfile" >> "$ytfzf_video_json_file"
	    } &
	    sleep $sleep_time
    done <<- EOF
	$(sed \
		-e "s/#.*//" \
		-e "/^[[:space:]]*$/d" \
		-e "s/[[:space:]]*//g" \
		"$YTFZF_SUBSCRIPTIONS_FILE" )
	EOF
    wait
}

scrape_youtube_channel () {
	channel_url="$1"
	output_json_file="$2"
	tmp_filename="$3"
	print_info "Scraping Youtube channel: $channel_url\n"
	_tmp_html="${session_temp_dir}/${tmp_filename}.html"
	_tmp_json="${session_temp_dir}/${tmp_filename}.json"

	# Converting channel title page url to channel video url
	case "$channel_url" in
		*/videos) : ;;
		*) channel_url="${channel_url}/videos"
	esac
	channel_id="$(_get_channel_id "$channel_url")"
	[ "$channel_id/videos" = "$channel_url" ] &&\
		print_warning "$channel_url is not a scrapable link run:\n$0 --channel-link='$channel_url'\nto fix this warning\n" &&\
		channel_url="$(_get_real_channel_link "$channel_url")" && channel_id="$(_get_channel_id "$channel_url")"

	_get_request "https://www.youtube.com/channel/${channel_id}/videos" > "$_tmp_html"
	_youtube_get_json < "$_tmp_html" > "$_tmp_json"

	channel_name=$(_youtube_channel_name < "$_tmp_html" )
	_youtube_channel_json "$channel_name" < "$_tmp_json"  >> "$output_json_file"
}
# }}}

## Invidious {{{
# invidious backend functions {{{
_get_real_channel_link () {
	domain=${1#https://}
	domain=${domain%%/*}
	url=$(printf "%s" "$1" | sed -E "s_(https://)?www.youtube.com_${invidious_instance}_")
	real_path="$(curl -is "$url" | grep "^[lL]"ocation | sed 's/[Ll]ocation: //')"
	#prints the origional url because it was correct
	[ -z "$real_path" ] && printf "%s\n" "$1" && return 0
	#printf is not used because weird flushing? issues.
	echo "https://${domain}${real_path}"
}

_get_channel_id () {
	link="$1"
	link="${link##*channel/}"
	link="${link%/*}"
	printf "%s" "$link"
}

_get_invidious_thumb_quality_name () {
	case "$thumbnail_quality" in
		high) thumbnail_quality="hqdefault" ;;
		medium) thumbnail_quality="mqdefault" ;;
		start) thumbnail_quality="1" ;;
		middle) thumbnail_quality="2" ;;
		end) thumbnail_quality="3" ;;
	esac
}

_invidious_search_json_playlist () {
	jq '[ .[] | select(.type=="playlist") |
		{
			scraper: "youtube_search",
			ID: .playlistId,
			url: "'"${yt_video_link_domain}"'/playlist?list=\(.playlistId)",
			title: "[playlist] \(.title)",
			channel: .author,
			thumbs: .playlistThumbnail,
			duration: "\(.videoCount) videos",
			action: "scrape type=invidious-playlist search='"${yt_video_link_domain}"'/playlist?list=\(.playlistId)"
		}
	]'
}
_invidious_search_json_channel () {
	jq '
	[ .[] | select(.type=="channel") |
		{
			scraper: "youtube_search",
			ID: .authorId,
			url: "'"${yt_video_link_domain}"'/channel/\(.authorId)",
			title: "[channel] \(.author)",
			channel: .author,
			thumbs: "https:\(.authorThumbnails[4].url)",
			duration: "\(.videoCount) uploaded videos",
			action: "scrape type=invidious-channel search='"${invidious_instance}"'/channel/\(.authorId)"
		}
	]'
}
_invidious_search_json_live () {
	jq '[ .[] | select(.type=="video" and .liveNow==true) |
		{
			scraper: "youtube_search",
			ID: .videoId,
			url: "'"${yt_video_link_domain}"'/watch?v=\(.videoId)",
			title: "[live] \(.title)",
			channel: .author,
			thumbs: "'"${invidious_instance}"'/vi/\(.videoId)/'"$thumbnail_quality"'.jpg"
		}
	]'
}
_invidious_search_json_videos () {
	jq '
	def pad_left(n; num):
		num | tostring |
			if (n > length) then ((n - length) * "0") + (.) else . end
		;
	[ .[] | select(.type=="video" and .liveNow==false) |
		{
			scraper: "youtube_search",
			ID: .videoId,
			url: "'"${yt_video_link_domain}"'/watch?v=\(.videoId)",
			title: .title,
			channel: .author,
			thumbs: "'"${invidious_instance}"'/vi/\(.videoId)/'"$thumbnail_quality"'.jpg",
			duration: "\(.lengthSeconds / 60 | floor):\(pad_left(2; .lengthSeconds % 60))",
			views: "\(.viewCount)",
			date: .publishedText,
			description: .description
		}
	]'
}

_invidious_playlist_json () {
	jq '
	def pad_left(n; num):
		num | tostring |
			if (n > length) then ((n - length) * "0") + (.) else . end
		;
	[ .videos | .[] |
		{
			scraper: "invidious_search",
			ID: .videoId,
			url: "'"${yt_video_link_domain}"'/watch?v=\(.videoId)",
			title: .title,
			channel: .author,
			thumbs: "'"${invidious_instance}"'/vi/\(.videoId)/'"$thumbnail_quality"'.jpg",
			duration: "\(.lengthSeconds / 60 | floor):\(pad_left(2; .lengthSeconds % 60))",
			date: .publishedText,
			description: .description
		}
	]'
}

_concatinate_json_file () {
	template="$1"
	page_count=$2
	_output_json_file="$3"
	__cur_page=1
	set --
	#this sets the arguments to the files in order for cat
	while [ "$__cur_page" -le "$page_count" ]; do
		set -- "$@" "${template}${__cur_page}.json.final"
		__cur_page=$((__cur_page+1))
	done
	cat "$@" 2>/dev/null >> "$_output_json_file"

}
#}}}

scrape_invidious_playlist () {
	playlist_url=$1
	output_json_file=$2

	playlist_id="${playlist_url##*[?]list=}"

	_get_invidious_thumb_quality_name

	#used to put the full playlist in, to later remove duplicates
	_full_playlist_json="${session_temp_dir}/full-playlist-$playlist_id.json"

	_cur_page=1
	while :; do
		_tmp_json="${session_temp_dir}/yt-playlist-$playlist_id-$_cur_page.json"
		_get_request "$invidious_instance/api/v1/playlists/$playlist_id" \
		-G --data-urlencode "page=$_cur_page" > "$_tmp_json" || return "$?"
		jq -e '.videos==[]' < "$_tmp_json" > /dev/null 2>&1  && break
		print_info "Scraping Youtube playlist (with $invidious_instance) (playlist: $playlist_url, pg: $_cur_page)\n"

		_invidious_playlist_json < "$_tmp_json" >> "$_full_playlist_json"
		_cur_page=$((_cur_page+1))
	done

	#some instances give duplicates over multiple pages, remove the duplicates
	jq -s '. | flatten | sort_by(.ID) | unique_by(.ID)' < "$_full_playlist_json" >> "$output_json_file"

}

scrape_invidious_search () {
	page_query=$1
	output_json_file=$2
	pagetype=$3
	page_num=$4

	_cur_page=1
	_start_series_of_threads
	while [ ${_cur_page} -le $page_num ]; do
		{
			_tmp_json="${session_temp_dir}/yt-search-$_cur_page.json"

			print_info "Scraping YouTube (with $invidious_instance) ($page_query, pg: $_cur_page)\n"

			_get_request "$invidious_instance/api/v1/search" \
				-G --data-urlencode "q=$page_query" \
				--data-urlencode "type=${search_result_type}" \
				--data-urlencode "sort_by=${search_sort_by}" \
				--data-urlencode "date=${search_upload_date}" \
				--data-urlencode "duration=${search_video_duration}" \
				--data-urlencode "features=${search_result_features}" \
				--data-urlencode "region=${search_region}" \
				--data-urlencode "page=${_cur_page}" > "$_tmp_json" || return "$?"

			_get_invidious_thumb_quality_name

			{
				_invidious_search_json_live < "$_tmp_json"
				_invidious_search_json_videos < "$_tmp_json"
				_invidious_search_json_channel < "$_tmp_json"
				_invidious_search_json_playlist < "$_tmp_json"
			} >> "$_tmp_json.final"
		} &
		_cur_page=$((_cur_page+1))
		_thread_started "$!"
	done
	wait
	_concatinate_json_file "${session_temp_dir}/yt-search-" "$page_num" "$output_json_file"
}

scrape_invidious_trending () {
	trending_tab=$(title_str $1)
	output_json_file=$2
	print_info "Scraping YouTube (with $invidious_instance) trending (${trending_tab:-Normal})\n"

	_tmp_json="${session_temp_dir}/yt-trending"

	url="$invidious_instance/api/v1/trending"
	[ -n "$trending_tab" ] && url="${url}?type=${trending_tab}" && _tmp_json="${_tmp_json}-$trending_tab"

	_get_request "$url" \
		-G --data-urlencode "region=${search_region}" > "$_tmp_json" || return "$?"

	_get_invidious_thumb_quality_name

	_invidious_search_json_videos < "$_tmp_json" >> "$output_json_file"
}

scrape_invidious_channel () {
	channel_url=$1
	output_json_file=$2
	tmp_file_name=$3
	#default to one, because -cSI does not give a page count
	page_num=${4:-1}

	# Converting channel title page url to channel video url
	case "$channel_url" in
		*/videos) : ;;
		*) channel_url="${channel_url}/videos"
	esac
	channel_id="$(_get_channel_id "$channel_url")"
	[ "$channel_id/videos" = "$channel_url" ] &&\
		print_warning "$channel_url is not a scrapable link run:\n$0 --channel-link='$channel_url'\nto fix this warning\n" &&\
		channel_url="$(_get_real_channel_link "$channel_url")" && channel_id="$(_get_channel_id "$channel_url")"


	#here because if scrape_invidious_channel is called more than once, i needs to be reset
	_cur_page=1
	_start_series_of_threads
	while [ ${_cur_page} -le $page_num ]; do
		{
			print_info "Scraping Youtube (with $invidious_instance) channel: $channel_url (pg: $_cur_page)\n"
			#if this var isn't unique, weird things happen,
			_tmp_json="${session_temp_dir}/$tmp_file_name-$_cur_page.json"
			channel_url="$invidious_instance/api/v1/channels/$channel_id/videos"
			_get_request "${channel_url##* }" \
				-G --data-urlencode "page=$_cur_page" \
				> "$_tmp_json" || return "$?"

			_get_invidious_thumb_quality_name

			{
				_invidious_search_json_videos < "$_tmp_json"
				_invidious_search_json_live < "$_tmp_json"
			} | jq 'select(.!=[])' >> "$_tmp_json.final"
		} &
		_cur_page=$((_cur_page+1))
		_thread_started "$!"
	done
	wait
	_concatinate_json_file "${session_temp_dir}/${tmp_file_name}-" "$page_num" "$output_json_file"
}

## }}}

## Peertube {{{
scrape_peertube () {
	page_query=$1
	output_json_file=$2
	print_info "Scraping Peertube ($page_query)\n"

	_tmp_json="${session_temp_dir}/peertube.json"

	#gets a list of videos
	_get_request "https://sepiasearch.org/api/v1/search/videos" -G --data-urlencode "search=$1" > "$_tmp_json" || return "$?"

	jq '
	def pad_left(n; num):
		num | tostring |
			if (n > length) then ((n - length) * "0") + (.) else . end
		;
	[ .data | .[] |
			{
				scraper: "peertube_search",
				ID: .uuid,
				url: .url,
				title: .name,
				channel: .channel.displayName,
				thumbs: .thumbnailUrl,
				duration: "\(.duration / 60 | floor):\(pad_left(2; .duration % 60))",
				views: "\(.views)",
				date: .publishedAt
			}
		]' < "$_tmp_json" >> "$output_json_file"

}
## }}}

## Odysee {{{
scrape_odysee () {
	page_query=$1
	[ "${#page_query}" -le 2 ] && die 4 "Odysee searches must be 3 or more characters\n"
	output_json_file=$2
	print_info "Scraping Odysee ($page_query)\n"

	_tmp_json="${session_temp_dir}/odysee.json"

	case "$search_sort_by" in
		upload_date|newest_first) search_sort_by="release_time" ;;
		oldest_first) search_sort_by="^release_time" ;;
		relevance) search_sort_by="" ;;
	esac
	case "$search_upload_date" in
		week|month|year) search_upload_date="this${search_upload_date}" ;;
		day) search_upload_date="today" ;;
	esac

	case "$nsfw" in
		1) nsfw=true ;;
		0) nsfw=false ;;
	esac

	#this if is because when search_sort_by is empty, it breaks lighthouse
	if [ -n "$search_sort_by" ]; then
		_get_request "https://lighthouse.lbry.com/search" -G \
		    --data-urlencode "s=$page_query" \
		    --data-urlencode "mediaType=video,audio" \
		    --data-urlencode "include=channel,title,thumbnail_url,duration,cq_created_at,description,view_cnt" \
		    --data-urlencode "sort_by=$search_sort_by" \
		    --data-urlencode "time_filter=$search_upload_date" \
		    --data-urlencode "nsfw=$nsfw" \
		    --data-urlencode "size=$odysee_video_search_count" > "$_tmp_json" || return "$?"
	else
		_get_request "https://lighthouse.lbry.com/search" -G \
		    --data-urlencode "s=$page_query" \
		    --data-urlencode "mediaType=video,audio" \
		    --data-urlencode "include=channel,title,thumbnail_url,duration,cq_created_at,description,view_cnt" \
		    --data-urlencode "time_filter=$search_upload_date" \
		    --data-urlencode "nsfw=$nsfw" \
		    --data-urlencode "size=$odysee_video_search_count" > "$_tmp_json" || return "$?"

	fi
	#select(.duration != null) selects videos that aren't live, there is no .is_live key
	jq '
	def pad_left(n; num):
		num | tostring |
			if (n > length) then ((n - length) * "0") + (.) else . end
		;
	[ .[] |select(.duration != null) |
	    {
		    scraper: "odysee_search",
			ID: .claimId,
			title: .title,
			url: "https://www.odysee.com/\(.channel)/\(.name)",
			channel: .channel,
			thumbs: .thumbnail_url,
			duration: "\(.duration / 60 | floor):\(pad_left(2; .duration % 60))",
			views: "\(.view_cnt)",
			date: .cq_created_at
	    }
	]' < "$_tmp_json" >> "$output_json_file"

}
## }}}

# History{{{
scrape_history () {
	[ $enable_hist -eq 0 ] && print_info "enable_hist must be set to 1 for this option" && return 5
	output_json_file="$2"
	enable_hist=0 #enabling history while scrape is history causes issues
	cp "$hist_file" "$output_json_file" 2>/dev/null
}

scrape_json_file () {
	search="$1"
	output_json_file="$2"
	cp "$search" "$output_json_file" 2>/dev/null
}
#}}}

# Comments{{{
scrape_comments () {
	video_id="$1"
	case "$video_id" in
		*/*) video_id="${video_id##*=}" ;;
	esac
	output_json_file="$2"
	page_count="$3"
	_comment_file="${session_temp_dir}/comments-$video_id.tmp.json"
	i=1
	while [ "$i" -le $page_count ]; do
		print_info "Scraping comments (pg: $i)\n"
		_out_comment_file="${session_temp_dir}/comments-$i.json.final"
		_get_request "$invidious_instance/api/v1/comments/${video_id}" -G \
			--data-urlencode "continuation=$continuation" > "$_comment_file"
		continuation=$(jq -r '.continuation' < "$_comment_file")
		jq --arg continuation "$continuation" '[ .comments[] | {"scraper": "comments", "channel": .author, "date": .publishedText, "ID": .commentId, "title": .author, "description": .content, "url": "'"$yt_video_link_domain"'/watch?v='"$video_id"'&lc=\(.commentId)", "action": "do-nothing", "thumbs": .authorThumbnails[2].url, "continuation": $continuation} ]' < "$_comment_file"  >>  "$output_json_file"
		i=$((i+1))
	done
}

scrape_next_page_comments () {
	#we can do this because _comment_file is overritten every time, meaning it will contain the latest scrape
	scrape_comments "$_search" "$video_json_file" "1"
}
#}}}

# }}}

# Sorting {{{

command_exists "get_sort_by" || get_sort_by () {
	line="$1"
	date="${line%|*}"
	date=${date##*|}
	#youtube specific
	date=${date#*Streamed}
	date=${date#*Premiered}
	date -d "$date" '+%s' 2>/dev/null || date -f "$date" '+%s' 2> /dev/null || printf "null"
	unset line
}

command_exists "data_sort_fn" || data_sort_fn () {
	sort -nr
}

sort_video_data_fn () {
	if [ $is_sort -eq 1 ]; then
		while IFS= read -r line
		do
			#run the key function to get the value to sort by
			get_sort_by "$line" | tr -d '\n'
			printf "\t%s\n" "$line"
		done | data_sort_fn | cut -f2-
	else
		cat
	fi
}
#}}}

# History Management {{{
add_to_hist () {
	#id of the video to add to hist will be passed through stdin
	#if multiple videos are selected, multiple ids will be present on multiple lines
	json_file="$1"
	while read -r url; do
		jq -r --arg url "${url% }" '[ .[]|select(.url==$url) ]'< "$json_file" | sed 's/\[\]//g'>> "$hist_file"
	done
	unset url urls json_file
}

clear_hist () {
	case "$1" in
		search) : > "$search_hist_file"; print_info "Search history cleared\n" ;;
		watch) : > "$hist_file"; print_info "Watch history cleared\n" ;;
		*)
			: > "$search_hist_file"
			: > "$hist_file"
			print_info "History cleared\n" ;;
	esac
}

#}}}

# User Interface {{{

# Keypresses {{{
set_keypress () {
	#this function uses echo to keep new lines
	read -r keypress
	while read -r line; do
		input="${input}${new_line}${line}"
	done
	#this if statement checks if there is a keypress, if so, print the input, otherwise print everything
	# $keypress could also be a standalone variable, but it's nice to be able to interact with it externally
	if printf "%s" "$keypress" | grep -E '^[[:alnum:]-]+$' > "$keypress_file"; then
		echo "$input" | sed -n '2,$p'
	else
		#there was no key press, remove all blank lines
		echo "${keypress}${new_line}${input}" | grep -Ev '^[[:space:]]*$'
	fi
	unset keypress
}

handle_keypress () {
	keypress="$1"
	command_exists "handle_custom_keypresses" && { handle_custom_keypresses "$keypress" || return "$?"; }
	case "$keypress" in
		$download_shortcut) url_handler=downloader ;;
		$video_shortcut) url_handler=video_player ;;
		$audio_shortcut) url_handler=audio_player ;;
		$detach_shortcut) is_detach=1 ;;
		$print_link_shortcut) info_to_print="L" ;;
		$show_formats_shortcut) show_formats=1 ;;
		$info_shortcut) info_to_print="VJ" ;;
		$next_page_shortcut) 
			read -r url < "$selected_id_file"
			hovered_scraper="$(jq -r '.[]|select(.url=="'"$url"'").scraper' < "$ytfzf_video_json_file")"
			scrape_next_page_$hovered_scraper
			unset hovered_scraper
			;;
		$search_again_shortcut)
			clean_up
			make_search ""
			$(printf "%s" "interface_$interface" | sed 's/-/_/g' | sed 's/^interface_$/interface_text/') "$ytfzf_video_json_file" "$ytfzf_selected_urls" ;;
		*)
			_fn_name=handle_keypress_$(sed 's/-/_/g' <<-EOF
							$keypress
						EOF
						)
			command_exists "$_fn_name" && $_fn_name ;;
	esac
	unset keypress
}

#}}}

# Takes video json file as $1 and returns the selected video IDs to file $2
command_exists "video_info_text" || video_info_text () {
	#we can't just change the views line to %d because it needs to display the "|", and "|$views" is NaN
	[ "${views#|}" -eq "${views#|}" ] 2>/dev/null && views="$(printf "|%s" "${views#|}" | add_commas)"
	printf "%-${title_len}.${title_len}s\t" "$title"
	printf "%-${channel_len}.${channel_len}s\t" "$channel"
	printf "%-${dur_len}.${dur_len}s\t" "$duration"
	printf "%-${view_len}.${view_len}s\t" "$views"
	printf "%-${date_len}.${date_len}s\t" "$date"
	printf "%s" "$url"
	printf "\n"
}

command_exists "thumbnail_video_info_text_comments" || thumbnail_video_info_text_comments () {
	[ -n "$title" ] && printf "\033[1m%s\n\033[0m" "$title"
	[ -n "$description" ] && printf "\n%s" "$description"
}

command_exists "thumbnail_video_info_text" || thumbnail_video_info_text () {
	[ "$views" -eq "$views" ] 2>/dev/null && views="$(printf "%s" "$views" | add_commas)"
	[ -n "$title" ] && printf "\n ${c_cyan}%s" "$title"
	[ -n "$channel" ] && printf "\n ${c_blue}Channel  ${c_green}%s" "$channel"
	[ -n "$duration" ] && printf "\n ${c_blue}Duration ${c_yellow}%s" "$duration"
	[ -n "$views" ] && printf "\n ${c_blue}Views    ${c_magenta}%s" "$views"
	[ -n "$date" ] && printf "\n ${c_blue}Date     ${c_cyan}%s" "$date"
	[ -n "$description" ] && printf "\n ${c_blue}Description ${c_reset}: %s" "$(printf "%s" "$description" | sed 's/\\n/\n/g')"
}

# Scripting interfaces {{{
interface_scripting () {
	video_json_file=$1
	selected_id_file=$2
	case 1 in
		"$is_auto_select") jq -r ".[].url"  < "$video_json_file" | sed -n "1,$scripting_video_count"p  ;;
		"$is_random_select") jq -r ".[].url"  < "$video_json_file"  | shuf  | sed -n "1,$scripting_video_count"p ;;
		"$is_specific_select") jq -r '.[].url' < "$video_json_file" | sed -n "$scripting_video_count"p 
	esac > "$selected_id_file"
	# jq '.[]' < "$video_json_file" | jq -s -r --arg N "$scripting_video_count" '.[0:$N|tonumber]|.[]|.ID' > "$selected_id_file"
}
# }}}

# Text interface {{{
interface_text () {
	command_exists "fzf" || die 3 "fzf not installed, cannot use the default menu\n"
	[ $show_thumbnails -eq 1 ] && { interface_thumbnails "$@"; return; }
	video_json_file=$1
	selected_id_file=$2

	# video_info_text can be set in the conf.sh, if set it will be preferred over the default given below
	TTY_COLS=$(tput cols)
	title_len=$((TTY_COLS/2))
	channel_len=$((TTY_COLS/5))
	dur_len=7
	view_len=10
	date_len=100

	IFS=" ${tab_space}${new_line}"

	jq -r '.[]|"\(.title)\t|\(.channel)\t|\(.duration)\t|\(.views)\t|\(.date)\t|\(.url)"' < "$video_json_file" |
		sort_video_data_fn |
		while IFS=$tab_space read title channel duration views date url
		do
			video_info_text
		done |
		column -t -s "$tab_space" |
		fzf -m --tabstop=1 --layout=reverse --expect="$shortcut_binds" $fzf_opts | set_keypress |
		trim_url > "$selected_id_file"
	#we can't do handle_keypress < "$keypress_file" because it leaves fd0 open which breaks $search_again_shortcut
	handle_keypress "$(cat "$keypress_file")"
}
#}}}

# External interface {{{
interface_ext () {
	video_json_file=$1
	selected_id_file=$2

	# video_info_text can be set in the conf.sh, if set it will be preferred over the default given below
	TTY_COLS=$external_menu_len
	title_len=$((TTY_COLS/2))
	channel_len=$((TTY_COLS/5))
	dur_len=7
	view_len=10
	date_len=100

	jq -r '.[]|"\(.title)\t|\(.channel)\t|\(.duration)\t|\(.views)\t|\(.date)\t|\(.url)"' < "$video_json_file" |
		sort_video_data_fn |
		while IFS=$tab_space read title channel duration views date url
		do
			video_info_text
		done |
		external_menu "Select video: " |
		trim_url > "$selected_id_file"
}
#}}}

# Thumbnail Interface {{{

get_missing_thumbnails () {
	#this function could be done in a more pure-shell way, however it is extremely slow
	_tmp_id_list_file="${session_temp_dir}/all-ids.list"
	_downloaded_ids_file="${session_temp_dir}/downloaded-ids.list"

	jq -r '.[]|select(.thumbs!=null)|.ID' < "$video_json_file" | sort > $_tmp_id_list_file
	ids="$(jq -r '.[]|select(.thumbs!=null)|.thumbs + ";" + .ID' < "$video_json_file")"
	ls -1 "$thumb_dir" | sed 's/\..*//' > "$_downloaded_ids_file"

	missing_ids="$(diff "$_downloaded_ids_file" "$_tmp_id_list_file" | sed -n 's/^> //p')"

	set -f
	set -- $missing_ids
	IFS="|"
	search_grep="$*"
	grep -E "(${search_grep:-${tab_space}})" <<EOF
$ids
EOF
	unset IFS _tmp_id_list_file _downloaded_ids_file
}

download_thumbnails () {
	[ $skip_thumb_download -eq 1 ] && { print_info "Skipping thumbnail download\n"; return 0; }
	print_info 'Fetching thumbnails...\n'
	curl_config_file="${session_temp_dir}/curl_config"
	[ -z "$*" ] && return 0
	for line in "$@"; do
		printf "url=\"%s\"\noutput=\"$thumb_dir/%s.jpg\"\n" "${line%%;*}" "${line##*;}"
	done >> "$curl_config_file"
	curl -fLZ -K "$curl_config_file"
	[ $? -eq 2 ] && curl -fL -K "$curl_config_file"
}

get_video_json_attr () {
	sed -n 's/^[[:space:]]*"'"$1"'":[[:space:]]*"\([^"\n]*\)",*/\1/p' <<EOF
$_correct_json
EOF
}

# Image preview {{{
preview_start () {
	thumbnail_viewer=$1
	case $thumbnail_viewer in
		ueberzug)
			# starts uberzug to this fifo
			UEBERZUG_FIFO="$session_temp_dir/ytfzf-ueberzug-fifo"
			rm -f "$UEBERZUG_FIFO"
			mkfifo "$UEBERZUG_FIFO"
			ueberzug layer --parser simple < "$UEBERZUG_FIFO" 2>/dev/null &
			exec 3> "$UEBERZUG_FIFO" # to keep the fifo open
			;;
		chafa|chafa-16|chafa-tty|catimg|catimg-256|display|w3m) : ;;
		imv)
			first_img="$(jq -r '.[0].ID|select(.!=null)' < "$ytfzf_video_json_file")"
			imv "$thumb_dir/${first_img}.jpg" &
			export imv_pid="$!"
			#helps prevent imv seg fault
			sleep 0.1
			;;
		*)
			"$thumbnail_viewer" "start" "$FZF_PREVIEW_COLUMNS" "$FZF_PREVIEW_LINES" 2>/dev/null ;;
	esac
}
preview_stop () {
	thumbnail_viewer=$1
	case $thumbnail_viewer in
		ueberzug)
			exec 3>&- # close file descriptor 3, closing ueberzug
			;;
		chafa|chafa-16|chafa-tty|catimg|catimg-256|display|w3m) : ;;
		imv) kill "$imv_pid" ;;
		*)
			"$thumbnail_viewer" "stop" "$FZF_PREVIEW_COLUMNS" "$FZF_PREVIEW_LINES" 2>/dev/null ;;
	esac
}
preview_no_img (){
	thumbnail_viewer="$1"
	case $thumbnail_viewer in
		ueberzug|chafa|chafa-16|chafa-tty|catimg|catimg-256|display|w3m|imv) : ;;
		*) "$thumbnail_viewer" "no-img" ;;
	esac && die 1 "\nno image found" 
}
# ueberzug positioning{{{
command_exists "get_ueberzug_positioning_left" || get_ueberzug_positioning_left (){
	width=$1
	height=$(($2-10))
	x=2
	y=10
}
command_exists "get_ueberzug_positioning_right" || get_ueberzug_positioning_right (){
	width=$1
	height=$(($2-10))
	x=$(($1+6))
	y=10
}
command_exists "get_ueberzug_positioning_up" || get_ueberzug_positioning_up (){
	width=$1
	height=$(($2-10))
	x=2
	y=9
}
command_exists "get_ueberzug_positioning_down" || get_ueberzug_positioning_down (){
	width=$1
	height=$(($2-10))
	#$2*2 goes to the bottom subtracts height, adds padding
	y=$(($2*2-height+2))
	x=2
}
get_ueberzug_positioning () {
	max_width=$1
	max_height=$2
	side=$3
	case "$fzf_preview_side" in
		left) get_ueberzug_positioning_left "$max_width" "$max_height" ;;
		right) get_ueberzug_positioning_right "$max_width" "$max_height" ;;
		up) get_ueberzug_positioning_up "$max_width" "$max_height" ;;
		down) get_ueberzug_positioning_down "$max_width" "$max_height" ;;
	esac
}
#}}}
preview_display_image () {
	thumbnail_viewer=$1
	id=$2
	thumb_path="${thumb_dir}/${id}.jpg"
	[ -f "${thumb_path}" ] || thumb_path="${YTFZF_CUSTOM_THUMBNAILS_DIR}/$id.jpg"
	[ -f "${thumb_path}" ] || preview_no_img "$thumbnail_viewer"
	case $thumbnail_viewer in
		ueberzug)
			get_ueberzug_positioning "$FZF_PREVIEW_COLUMNS" "$FZF_PREVIEW_LINES" "$fzf_preview_side"
			command_exists "ueberzug" || die 3 "ueberzug is not installed\n"
			printf '%s\t' \
				'action' 'add' \
				'identifier' 'ytfzf' \
				'path' "$thumb_path" \
				'x' "$x" \
				'y' "$y" \
				'scaler' 'fit_contain' \
				'width' "$width" > "$UEBERZUG_FIFO"
			printf '%s\t%s\n' \
				'height' "$height" > "$UEBERZUG_FIFO"
			;;
		chafa)
			printf '\n'
			command_exists "chafa" || die 3 "\nchafa is not installed\n"
			chafa -s "$((FZF_PREVIEW_COLUMNS-2))x$((FZF_PREVIEW_LINES-10))" "$thumb_path" ;;
		chafa-16)
			printf '\n'
			command_exists "chafa" || die 3 "\nchafa is not installed\n"
			chafa -c 240 -s "$((FZF_PREVIEW_COLUMNS-2))x$((FZF_PREVIEW_LINES-10))" "$thumb_path" ;;
		chafa-tty)
			printf '\n'
			command_exists "chafa" || die 3 "\nchafa is not installed\n"
			chafa -c 16 -s "$((FZF_PREVIEW_COLUMNS-2))x$((FZF_PREVIEW_LINES-10))" "$thumb_path" ;;
		catimg)
			printf '\n'
			command_exists "catimg" || die 3 "\ncatimg is not installed\n"
			catimg -w $((FZF_PREVIEW_COLUMNS+50)) "$thumb_path" ;;
		catimg-256)
			printf '\n'
			command_exists "catimg" || die 3 "\ncatimg is not installed\n"
			catimg -c -w $((FZF_PREVIEW_COLUMNS+50)) "$thumb_path" ;;
		display)
			command_exists "display" || die 3 "\nimagemagick is not installed\n"
			killall display
			display "$thumb_dir/${id}.jpg" ;;
		w3m)
			while true; do
				printf "%b\n%s;\n" "0;1;10;130;$((FZF_PREVIEW_COLUMNS*5));$((FZF_PREVIEW_COLUMNS*3));;;;;$thumb_path" 3 | $w3mimgdisplay_path
			done ;;
		imv) 
			imv-msg "$imv_pid" open "$thumb_path"
			imv-msg "$imv_pid" next
			;;
		*) 
			get_ueberzug_positioning "$FZF_PREVIEW_COLUMNS" "$FZF_PREVIEW_LINES" "$fzf_preview_side"
			"$thumbnail_viewer" "view" "$thumb_path" "$x" "$y" "$width" "$height" "$FZF_PREVIEW_COLUMNS" "$FZF_PREVIEW_LINES" "$fzf_preview_side";;

	esac
}
#}}}

preview_img () {
	# This function is common to every thumbnail viewer
	thumbnail_viewer=$1
	line=$2
	video_json_file=$3
	url=${line##*|}

	#make sure all variables are set{{{
	_correct_json=$(jq -r --arg url "$url" '[.[]|select(.url==$url)]|unique_by(.ID)[0]' < "$video_json_file")
	id="$(get_video_json_attr "ID")"
	title="$(get_video_json_attr "title")"
	channel="$(get_video_json_attr "channel")"
	views="$(get_video_json_attr "views")"
	date="$(get_video_json_attr "date")"
	scraper="$(get_video_json_attr "scraper")"
	duration="$(get_video_json_attr "duration")"
	description="$(get_video_json_attr "description" | sed 's/\\n/\n/g')"
#}}}

	if command_exists "thumbnail_video_info_text${scraper:+_$scraper}"; then
		thumbnail_video_info_text${scraper:+_$scraper}
	else
		thumbnail_video_info_text
	fi

	preview_display_image "$thumbnail_viewer" "$id"
}

interface_thumbnails () {
	# Takes video json file and downloads the thumnails as ${ID}.png to thumb_dir
	video_json_file=$1
	selected_id_file=$2

	# Download thumbnails, only if they're not already downloaded
	
	set -f
	unset IFS
	download_thumbnails $(get_missing_thumbnails)

	preview_start "$thumbnail_viewer"

	IFS=" ${tab_space}${new_line}"

	# ytfzf -U preview_img ueberzug {} "$video_json_file"
	#fzf_preview_side will get reset if we don't pass it in
	jq -r '.[]|[.title,"'"$gap_space"'|"+.channel,"|"+.duration,"|"+.views,"|"+.date,"|"+.url]|@tsv' < "$video_json_file" |
	sort_video_data_fn |
	fzf -m \
	--preview "__is_fzf_preview=1 fzf_preview_side='$fzf_preview_side' scrape='$scrape' thumb_dir='$thumb_dir' YTFZF_PID='$YTFZF_PID' UEBERZUG_FIFO='$UEBERZUG_FIFO' $0 -U preview_img '$thumbnail_viewer' {} '$video_json_file'" \
	--preview-window "$fzf_preview_side:50%:wrap" --layout=reverse --expect="$shortcut_binds" $fzf_thumbnail_opts | set_keypress |
	trim_url > "$selected_id_file"

	preview_stop "$thumbnail_viewer"

	#we can't do handle_keypress < "$keypress_file" because it leaves fd0 open which breaks $search_again_shortcut
	handle_keypress "$(cat "$keypress_file")"
}
#}}}

#}}}

# Player {{{
print_requested_info () {
	url_list="$1"
	set -f
	IFS=,
	for request in $info_to_print; do
		unset IFS
		case "$request" in
		    [Ll]|link)
			    #cat is better here because a lot of urls could be selected
			    cat "$url_list" ;;
		    VJ|vj|video-json)
			    while read -r line; do 
				    jq '.[]|select(.url=="'"$line"'")' < "$ytfzf_video_json_file"; 
			    done < "$url_list"  ;;
		    [Jj]|json) jq < "$ytfzf_video_json_file" ;;
		    [Ff]|format) printf "%s\n" "$video_pref" ;;
		    [Rr]|raw) 
			    while read -r line; do
				    jq -r '.[]|select(.url=="'"$line"'")|"\(.title)\t|\(.channel)\t|\(.duration)\t|\(.views)\t|\(.date)\t|\(.url)"' < "$ytfzf_video_json_file";
			    done < "$url_list" ;;
		esac
	done
	[ $info_wait -eq 1 ] && { print_info "quit (q), quit (override -l) (Q), open menu (c|m), play (enter): "; read -r info_wait_action; }
	return 0
}

submenu_handler () {
	final_submenu_json_file="${session_temp_dir}/submenu.json"
	#reset for future submenus
	: > "$final_submenu_json_file"

        [ $enable_back_button -eq 1 ] && printf "%s\n" '[{"title": "[BACK]", "ID": "BACK-BUTTON", "url": "back", "action": "back"}]' >> "$final_submenu_json_file"

	unset IFS
	while read -r line; do
		#calls ytfzf to reduce code complexity
		__is_scrape_for_submenu=1 cache_dir="${session_cache_dir}" $0 --info-exit $submenu_scraping_opts \
			-ac "$(get_key_value "$line" "type")" -IJ "$(get_key_value "$line" "search")" \
			>> "$final_submenu_json_file"
	done <<-EOF
	$(printf "%s" "$_submenu_actions" | sed 1d)
	EOF

	#the hist_file thing is to prevent watch_hist from being put in $session_cache_dir
	set -f
	__is_submenu=1 hist_file="$hist_file" cache_dir="${session_cache_dir}" $0 $submenu_opts --keep-cache -cp "$final_submenu_json_file"
}

open_url_handler () {
	# isaudio, isdownload, video_pref
	urls="$(tr '\n' ' ' < "$1")"
	set -f
	IFS=' '
	set -- $urls
	[ -z "$*" ] && return 0

	[ $show_formats -eq 1 ] && video_pref="$(get_video_format "$1")"

	[ $notify_playing -eq 1 ] && handle_playing_notifications "$@"

	#if we provide video_pref etc as arguments, we wouldn't be able to add more as it would break every url handler function
	printf "%s\t" "$video_pref" "$is_audio_only" "$is_detach" | "$url_handler" "$@"
}

get_video_format(){
	#the sed gets rid of random information
	case 1 in
		$is_audio_only) ${ytdl_path} -q -F "$1" | grep 'audio only' | quick_menu_wrapper "Audio format: " | awk '{print $1}' ;;
		1) ${ytdl_path} -q -F "$1" | sed '1,2d' | grep -v 'audio only' | quick_menu_wrapper "Video Format: "| awk '{print $1 "+bestaudio/" $1}' ;;
	esac
}
#}}}

# Options {{{
parse_opt () {
	opt=$1
	optarg=$2
	#for some reason optarg may equal opt intentionally,
	#this checks the unmodified optarg, which will only be equal if there is no = sign
	[ "$opt" = "$OPTARG" ] && optarg=""
	command_exists "on_opt_parse" && { on_opt_parse "$opt" "$optarg" "$OPT" "$OPTARG" || return 0; }
	fn_name="on_opt_parse_$(printf "%s" "$opt" | tr '-' '_')"
	command_exists "$fn_name" && { $fn_name "$optarg" "$OPT" "$OPTARG" || return 0; }
	case $opt in
		h|help) usage; exit 0 ;;
		D|external-menu) [ -z "$optarg" ] || [ $optarg -eq 1 ] && interface='ext' ;;
		m|audio-only) is_audio_only=${optarg:-1};;
		d|download) url_handler=downloader ;;
		f|formats) show_formats=${optarg:-1} ;;
		H|history) scrape="history" ;;
		x|history-clear) clear_hist "${optarg:-all}"; exit 0 ;;
		S|select) interface="scripting" && is_specific_select="1" && scripting_video_count="$optarg" ;;
		a|auto-select) [ -z "$optarg" ] || [ $optarg -eq 1 ] &&  interface="scripting" && is_auto_select=${optarg:-1} ;;
		A|select-all) [ -z "$optarg" ] || [ $optarg -eq 1 ] && interface="scripting" && is_auto_select=${optarg:-1} && scripting_video_count='$' ;;
		r|random-select) [ -z "$optarg" ] || [ $optarg -eq 1 ] && interface="scripting" && is_random_select=${optarg:-1} ;;
		n|link-count) scripting_video_count=$optarg;;
		l|loop) is_loop=${optarg:-1} ;;
		s|search-again) search_again=${optarg:-1} ;;
		t|show-thumbnails) show_thumbnails=${optarg:-1} ;;
		version) printf 'ytfzf: %s \n' "$YTFZF_VERSION"; exit 0;;
		L) info_to_print="$info_to_print,L" ;;
		q|search-hist) [ ! -s "$search_hist_file" ] && die 1 "You have no search history\n"a; use_search_hist=1 ;;
		pages) pages_to_scrape="$optarg" ;;
		odysee-video-count) odysee_video_search_count="$optarg" ;;
		interface)
			interface="$optarg"
			# if we don't check which interface, itll try to source $YTFZF_CUSTOM_INTERFACES_DIR/{ext,scripting} which won't work
			case "$interface" in
				"ext"|"scripting"|"") : ;;
				./*|../*|/*|~/*) [ -f "$interface" ] && . "$interface" && interface="${interface##*/}" ;; 
				*) 
					if [ -f "${YTFZF_CUSTOM_INTERFACES_DIR}/${interface}" ]; then
						. "$YTFZF_CUSTOM_INTERFACES_DIR/$interface"
					elif [ -f "${YTFZF_SYSTEM_ADDON_DIR}/interfaces/${interface}" ]; then
						. "${YTFZF_SYSTEM_ADDON_DIR}/interfaces/${interface}"
					fi ;;
			esac || die 2 "$optarg is not an interface\n" ;;
		c|scrape) scrape=$optarg ;;
		scrape+) scrape="$scrape,$optarg" ;;
		scrape-) scrape="$(printf '%s' "$scrape" | sed 's/'"$optarg"'//; s/,,/,/g')" ;;
		I) info_to_print=$optarg ;;
		notify-playing) notify_playing="${optarg:-1}" ;;
		#long-opt exclusives
		sort) is_sort=${optarg:-1} ;;
		sort-name)
			case "$optarg" in
				./*|../*|/*|~/*) command_exists "$optarg" && . "$optarg" ;;
				*)
					if command_exists "$optarg"; then
						"$optarg"
					elif [ -f "${YTFZF_SORT_NAMES_DIR}/${optarg}" ]; then
						. "${YTFZF_SORT_NAMES_DIR}/${optarg}"
					elif [ -f "${YTFZF_SYSTEM_ADDON_DIR}/sort-names/${optarg}" ]; then
						. "${YTFZF_SYSTEM_ADDON_DIR}/sort-names/${optarg}"
					else false
					fi ;;
			esac && is_sort=1 || die 2 "$optarg is not a sort-name\n" ;;
		video-pref) video_pref=$optarg ;;
		detach) is_detach=${optarg:-1} ;;
		ytdl-opts) ytdl_opts="$optarg" ;;
		ytdl-path) ytdl_path="$optarg" ;;
		preview-side) fzf_preview_side="${optarg}"; [ -z "$fzf_preview_side" ] && die 2 "no preview side given\n" ;;
		thumb-viewer)
			case "$optarg" in
				#these are special cases, where they are not themselves commands
				chafa-16|catimg-256|chafa|chafa-tty|catimg|catimg-256|display|w3m|imv|ueberzug) thumbnail_viewer="$optarg" ; true ;;
				./*|/*|../*|~/*) thumbnail_viewer="$optarg"; false ;;
				*)
					if [ -f "${YTFZF_THUMBNAIL_VIEWERS_DIR}/${optarg}" ]; then
						thumbnail_viewer="${YTFZF_THUMBNAIL_VIEWERS_DIR}/${optarg}"
					else
						thumbnail_viewer="${YTFZF_SYSTEM_ADDON_DIR}/thumbnail-viewers/$optarg"
					fi; false
			esac || [ -f "$thumbnail_viewer" ] || die 2 "$optarg is not a thumb-viewer\n" ;;
		force-youtube) yt_video_link_domain="https://www.youtube.com" ;;
		info-print-exit|info-exit) [ "${optarg:-1}" -eq 1 ] && info_wait_action=q ;;
		info-action) info_wait_action="$optarg" ;;
		info-wait) info_wait="${optarg:-1}" ;;
		sort-by) search_sort_by="$optarg" ;;
		upload-date) search_upload_date="$optarg" ;;
		video-duration) search_video_duration=$optarg ;;
		type) search_result_type=$optarg ;;
		features) search_result_features=$optarg ;;
		region) search_region=$optarg ;;
		channel-link) _get_real_channel_link "$optarg"; exit 0 ;;
		disable-submenus) enable_submenus="${optarg:-0}" ;;
		thumbnail-quality) thumbnail_quality="$optarg" ;;
		url-handler) 
			if command_exists "$optarg"; then
				url_handler="${optarg:-multimedia_player}"
			else 
				if [ -f "${YTFZF_URL_HANDLERS_DIR}/$optarg" ]; then
					url_handler="${YTFZF_URL_HANDLERS_DIR}/$optarg"
				elif [ -f "${YTFZF_SYSTEM_ADDON_DIR}/url-handlers/$optarg" ]; then
					url_handler="${YTFZF_SYSTEM_ADDON_DIR}/url-handlers/$optarg"
				else die 2 "$optarg is not a url-handler"
				fi
			fi ;;
		keep-cache) keep_cache="${optarg:-1}" ;;
		submenu-opts) submenu_opts="${optarg}" ;;
		submenu-scraping-opts) submenu_scraping_opts="${optarg}" ;;
		nsfw)  nsfw="${optarg:-true}" ;;
		fzf-opts) fzf_opts="${optarg}" ;;
		fzf-thumbnail-opts) fzf_thumbnail_opts="${optarg}" ;;
		max-threads|single-threaded) max_thread_count=${optarg:-1} ;;
		#flip the bit
		disable-back) enable_back_button=${optarg:-0} ;;
		skip-thumb-download) skip_thumb_download=${optarg:-1} ;;
		multi-search) multi_search=${optarg:-1} ;;
		fancy-subs) 
			fancy_subs=${optarg:-1} 
			[ "$fancy_subs" -eq 1 ] && is_sort=0 ;;
		*)
			[ "$OPT" = "$long_opt_char" ] && print_info "$0: illegal long option -- $opt\n";;
	esac
}
while getopts "ac:dfhlmn:qrstxADHI:LS:TU${long_opt_char}:" OPT; do
	case $OPT in
		U)
			shift $((OPTIND-1))
			case $1 in
				preview_img)
					session_cache_dir=$cache_dir/$SEARCH_PREFIX-$YTFZF_PID
					shift
					source_scrapers
					preview_img "$@"
					;;
			esac
			exit 0
			;;
		"$long_opt_char")
			parse_opt "${OPTARG%%=*}" "${OPTARG#*=}" ;;
		*)
			parse_opt "${OPT}" "${OPTARG}" ;;
	esac
done
shift $((OPTIND-1))
#}}}

#Post opt scrape{{{
source_scrapers
#}}}

# Get search{{{
#$initial_search should be used before make_search is called
#$_search should be used in make_search or after it's called and outisde of any scrapers themselves
#$search should be used in a scraper: eg scrape_json_file
: "${initial_search:=$*}"
#}}}

# files {{{
init_files (){
	YTFZF_PID=$$
	#$1 will be a search
	SEARCH_PREFIX=$(printf "%s" "$1" | tr '/' '_' | tr -d "\"'")
	#if no search is provided, use a fallback value of SCRAPE-$scrape
	SEARCH_PREFIX="${SEARCH_PREFIX:-SCRAPE-$scrape}"
	[ "${#SEARCH_PREFIX}" -gt 200 ] && SEARCH_PREFIX="SCRAPE-$scrape"
	session_cache_dir="${cache_dir}/${SEARCH_PREFIX}-${YTFZF_PID}"
	session_temp_dir="${session_cache_dir}/tmp"
	thumb_dir="${session_cache_dir}/thumbnails"
	mkdir -p "$session_temp_dir" "$thumb_dir"
	ytfzf_selected_urls=$session_cache_dir/ids
	ytfzf_video_json_file=$session_cache_dir/videos_json
	keypress_file="${session_temp_dir}/menu_keypress"
	: > "$ytfzf_video_json_file"
	: > "$ytfzf_selected_urls"
}

# }}}

#actions {{{
#actions are attached to videos/items in the menu
handle_actions () {
	unset _submenu_actions
	while read -r url; do
		_action=$(jq -r --arg url "$url" '.[]|select(.url==$url).action' < "$ytfzf_video_json_file")
		case "$_action" in
			back*) [ $__is_submenu -eq 1 ] && exit ;;
			scrape*)
				[ $enable_submenus -eq 0 ] && continue
				url_handler=submenu_handler
				_submenu_actions="${_submenu_actions}${new_line}${_action}" ;;
			do-nothing*) return 1 ;;
			*) 
				fn_name="handle_custom_action_$(printf "%s" "${_action%% *}" | tr '-' '_')"
				if command_exists "$fn_name"; then
					$fn_name "${_action#* }"
				elif command_exists "handle_custom_action"; then
					handle_custom_action "$_action"
				fi || return $? ;;
		esac
	done
}

#}}}

# scraping wrappers {{{
#there are 2 sets of backup variables because of -s, total_search* gets used up in manage_multi_filters
#there has to be at least 1 set of backup variables because search_sort_by=${search_sort_by%%,*} will give incorrect filters when there are 3+ filters
# multi {{{
set_save_filters () {
	IFS=","
	set -f -C
	printf "%s\n" $search_sort_by > "${session_cache_dir}/sort-by.list"
	printf "%s\n" $search_upload_date > "${session_cache_dir}/upload-date.list"
	set +C
	unset IFS
}
manage_multi_filters () {
	#if this is empty search_sort_by will be set to empty which isn't what we want
	search_sort_by=$(head -n "${__scrape_count}" "${session_cache_dir}/sort-by.list" | tail -n 1)
	search_upload_date=$(head -n "${__scrape_count}" "${session_cache_dir}/upload-date.list" | tail -n 1)
	#for custom scrapers
}
init_multi_search () {
	IFS=","
	set -f
	printf "%s\n" $1 > "${session_cache_dir}/searches.list"
	unset IFS
}
next_search (){
	head -n "$__scrape_count" "${session_cache_dir}/searches.list" | tail -n 1
}
#}}}
handle_scrape_error () {
	case "$1" in
		1) print_info "$curr_scrape failed to load website\n" ;;
		6) print_error "Website unresponsive (do you have internet?)\n" ;;
		9) print_info "$curr_scrape does not have a configuration file\n" ;;
	 	22)
			case "$curr_scrape" in
				youtube|Y|youtube-trending|T)
					print_error "There was an error scraping $curr_scrape ($invidious_instance)\nTry changing invidious instances\n" ;;
				*) print_error "There was an error scraping $curr_scrape\n" ;;
			esac ;;
		126) print_info "$curr_scrape does not have execute permissions\n" ;;
		127) die 2 "invalid scraper: $curr_scrape\n" ;;
	esac
}

scrape_website () {
	scrape_type="$1"
	_search="$2"
	case $scrape_type in
		invidious-playlist|youtube-playlist) scrape_invidious_playlist "$_search" "$ytfzf_video_json_file" ;;
		history|H) scrape_history "" "$ytfzf_video_json_file" ;;
		playlist|p|json-file) scrape_json_file "$_search" "$ytfzf_video_json_file" ;;
		invidious-channel) scrape_invidious_channel "$_search" "$ytfzf_video_json_file" "channel-1" "$pages_to_scrape" ;;
		youtube-channel) scrape_youtube_channel "$_search" "$ytfzf_video_json_file" "channel-1" ;;
		youtube|Y) scrape_invidious_search  "$_search" "$ytfzf_video_json_file" "search" "$pages_to_scrape" || return "$?" ;;
		youtube-trending|T) scrape_invidious_trending  "$_search" "$ytfzf_video_json_file" "trending";;
		youtube-subscriptions|S|SI) scrape_subscriptions "$scrape_type" "$ytfzf_video_json_file" ;;
		odysee|O) scrape_odysee "$_search" "$ytfzf_video_json_file" ;;
		peertube|P) scrape_peertube "$_search" "$ytfzf_video_json_file" ;;
		comments) scrape_comments "$_search" "$ytfzf_video_json_file" "$pages_to_scrape" ;;
		url|U) 
			printf "%s\n" "$_search" > "$ytfzf_selected_urls"
			open_url_handler  "$ytfzf_selected_urls" ;;
                *)
                        #custom scrapers {{{
			scrape_$(printf "%s" "$scrape_type" | sed 's/-/_/g') "$_search" "$ytfzf_video_json_file" || return "$?"
                        #}}}
	esac
	rv="$?"
	unset scrape_type
	return $rv
}

is_asking_for_search_necessary () {
	_scr=" $(sed 's/,/ | /g' <<EOF
$scrape
EOF
) "
	#for some reason using [ "$_search-" = "-" ] doesn't work, but the code below does
	grep -Eqv "($_scr)" <<EOF && [ "${_search:--}" = "-" ] && return 0
$scrape_search_exclude
EOF
	return 1
}

handle_scraping (){
	_search="$1"
	IFS=","
	set -f
	for curr_scrape in $scrape; do
		__scrape_count=$((__scrape_count+1))
		manage_multi_filters
		[ $multi_search -eq 1 ] && _search="$(next_search)"
		command_exists "on_search" && on_search "$_search" "$curr_scrape"
		command_exists "on_search_$_search" && on_search_$_search "$curr_scrape"
		scrape_website "$curr_scrape" "$_search"
		handle_scrape_error "$?"
	done
}

#check if nothing was scraped{{{
handle_empty_scrape () {
	[ ! -s "$ytfzf_video_json_file" ] && die 4 "Nothing was scraped\n"

	#sometimes the file fils up with empty arrays, we have to check if that's the case
	something_was_scraped=0
	while read -r line; do
		[ "$line" = "[]" ] && continue
		something_was_scraped=1
		#we can break if something was scraped, otherwise we are wasting time in the loop
		break
	done < "$ytfzf_video_json_file"
	[ $something_was_scraped -eq 0 ] && die 4 "Nothing was scraped\n"
}
#}}}


command_exists "handle_search_history" || handle_search_history () {
	#search history
	printf "%s${tab_space}%s\n" "$(date +'%D %H:%M:%S')" "${1}" >> "$2"
}

make_search () {
	_search="$1"
	#only ask for search if it's empty and scrape isn't something like S or T
	#this cannot be done inside handle_scraping, because otherwise init_files will get an empty search with search_again
	is_asking_for_search_necessary && { search_prompt_menu_wrapper; [ -z "$_search" ] && exit 5; }
	init_files "$_search"
	init_multi_search "$_search"
	set_save_filters
	[ $enable_search_hist -eq 1 ] && [ -n "$_search" ] && [ $__is_submenu -eq 0 ] && [ $__is_fzf_preview -eq 0 ] && handle_search_history "$_search" "$search_hist_file"
	handle_scraping "$_search" "$_save_search"
	handle_empty_scrape
}
#}}}

# Main {{{

make_search "$initial_search"

main() { 
	while :; do
		#calls the interface
		$(printf "%s" "interface_$interface" | sed 's/-/_/g' | sed 's/^interface_$/interface_text/') "$ytfzf_video_json_file" "$ytfzf_selected_urls"
		handle_actions < "$ytfzf_selected_urls" || { [ "$?" -eq 2 ] || continue && break; }

		[ $enable_hist -eq 1 ] && add_to_hist "$ytfzf_video_json_file" < "$ytfzf_selected_urls"

		#nothing below needs to happen if  this is empty (causes bugs when this is not here)
		[ ! -s "$ytfzf_selected_urls" ] && break

		[ "$info_to_print" ] && print_requested_info "$ytfzf_selected_urls" && case "$info_wait_action" in
				#simulates old behavior of when alt-l or alt-i is pressed and -l is enabled
				q) [ $is_loop -eq 1 ]  && continue || break ;;
				Q) break  ;;
				[MmCc]) continue ;;
				'') : ;;
				*) custom_info_wait_action_"$info_wait_action" ;;
			esac
		open_url_handler "$ytfzf_selected_urls"

		[ $is_loop -eq 0 ] && break
	done
}
main

#doing this after the loop allows for -l and -s to coexist
while [ $search_again -eq 1 ] ; do
	clean_up
	make_search ""
	main
done
#}}}

# vim:foldmethod=marker
