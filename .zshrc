# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="/home/garrett/.config/oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
#ZSH_THEME="powerlevel9k/powerlevel9k"
# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to automatically update without prompting.
# DISABLE_UPDATE_PROMPT="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
#	git
	#zsh_reload
themes
transfer
jsontools
copyfile
	colored-man-pages
	zsh-autosuggestions
	zsh-syntax-highlighting
	calculator
	gulp
	history
	web-search
)

ZSH_WEB_SEARCH_ENGINES=(
cmc "https://coinmarketcap.com/"
)

source $ZSH/oh-my-zsh.sh

HISTSIZE=100000
SAVEHIST=100000

#    _    _ _
#   / \  | (_) __ _ ___
#  / _ \ | | |/ _` / __|
# / ___ \| | | (_| \__ \
#/_/   \_\_|_|\__,_|___/
##########################
#reload zsh
alias reloadzsh='omz reload'
alias rzsh="src"
#list last x amount of packages installed - "pack 25" lists last 25 packages installed.
alias pack="expac --timefmt='%Y-%m-%d %T' '%l\t%n' | sort | tail -n"
#lsd
alias l='lsd -a'
alias la='lsd -la'
alias lr='lsd -lR'
alias c="clear"
#config files
alias i3c="nano ~/.config/i3/config"
alias picomc="nano ~/.config/picom/picom.conf"
alias polyc="cd ~/.config/polybar"
alias zshc="nano ~/.zshrc"
alias kittyc="nano ~/.config/kitty/kitty.conf"
#i will never use these
alias javas="archlinux-java status"
alias javathink="sudo archlinux-java set java-8-openjdk/jre"
alias javadefault="sudo archlinux-java set java-11-openjdk"
alias newsh="~/Scripts/autoscript.sh"
alias randomp="openssl rand -base64 29 | tr -d '=+/' | cut -c1-25"
alias myip="curl ipinfo.io/ip"
alias via="/opt/VIA/via %U --no-sandbox &; exit"
alias youtubei="youtube-dl -F"
alias youtubed="youtube-dl -f"
alias sqlg="mysql -u garrett -p"
alias noteq="sudo notepadqq --allow-root"
alias windowsserver="remmina"
#dev
alias proxc="nano ~/Scripts/dev/proxy.txt"
alias proxr="./Scripts/dev/proxy-tester.sh"
alias vshort="image ~/Notes/vscode/sc1.png"
alias sshdev="~/Scripts/dev/ssh-menu.sh"
alias lamp="~/Scripts/dev/lamp-menu.sh"
#i3ipc
alias image="~/.config/i3/i3ipc/image_view.py qimgv"
#git
alias gits="git status"
alias gitrc="git rm -r --cached"
alias gitrm="git rm -r"
alias gita="git add"
alias gitstats="git quick-stats"
#git dot files
alias dot='git --git-dir=$HOME/dotfiles/ --work-tree=$HOME'
alias dotls="dot ls-tree --full-tree -r --name-only HEAD"
alias dotrc="dot rm -r --cached"
alias dotrm="dot rm -r"
alias dota="dot add"
alias dots="dot status"
#pi
alias sshpi="ssh pi@10.0.0.192"
#search history
hist() {
hs "$1"
}
#file system breakdown
alias storage="gtk-launch qdirstat"

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
(cat ~/.cache/wal/sequences &)
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
