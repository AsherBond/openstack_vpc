CHEF_VPC_PROJECT = "#{File.dirname(__FILE__)}" unless defined?(CHEF_VPC_PROJECT)
SSH_OPTS="-o StrictHostKeyChecking=no"

require 'rubygems'

version_file=(File.join(CHEF_VPC_PROJECT, 'config', 'TOOLKIT_VERSION'))
toolkit_version=nil
if ENV['CHEF_VPC_TOOLKIT_VERSION'] then
  toolkit_version=ENV['CHEF_VPC_TOOLKIT_VERSION']
elsif File.exists?(version_file)
  toolkit_version=IO.read(version_file)
end

gem 'chef-vpc-toolkit', "~>#{toolkit_version}" if toolkit_version

require 'chef-vpc-toolkit'

include ChefVPCToolkit

require 'tempfile'
require 'fileutils'
def mktempdir(prefix="vpc")
    tmp_file=Tempfile.new(prefix)
    path=tmp_file.path
    tmp_file.close(true)
    FileUtils.mkdir_p path
    return path
end

def shh(script)
    out=%x{#{script}}
    retval=$?
    if block_given? then
        yield retval.success?, out
    else
        return [retval.success?, out]
    end
end

def get_revision(source_dir)
    %x{
        cd #{source_dir}
        if [ -d ".git" ]; then
          git log --oneline | wc -l
        else
          bzr revno --tree
        fi
    }.strip
end

Dir[File.join("#{ChefVPCToolkit::Version::CHEF_VPC_TOOLKIT_ROOT}/rake", '*.rake')].each do  |rakefile|
    import(rakefile)
end

if File.exist?(File.join(CHEF_VPC_PROJECT, 'tasks')) then
  Dir[File.join(File.dirname("__FILE__"), 'tasks', '*.rake')].each do  |rakefile|
    import(rakefile)
  end
end

#git clone w/ retry
BASH_COMMON=%{
function fail {
    local MSG=$1
    echo "FAILURE_MSG=$MSG"
    exit 1
}

function git_clone_with_retry {
    local URL=${1:?"Please specify a URL."}
    local DIR=${2:?"Please specify a DIR."}
    local COUNT=1
    until GIT_ASKPASS=echo git clone "$URL" "$DIR"; do
        [ "$COUNT" -eq "3" ] && { echo"Failed to clone: $URL"; exit 1; }
        sleep $(( $COUNT * 5 ))
        COUNT=$(( $COUNT + 1 ))
    done
}

# Test if the rpms we require are in the cache allready
# If present this function downloads them to ~/rpms
function download_cached_rpm {
    local PROJECT="$1"
    local SRC_URL="$2"
    local SRC_BRANCH="$3"
    local PKG_URL="$4"
    local PKG_BRANCH="$5"
    
    SRCUUID=$(git ls-remote "$SRC_URL" "$SRC_BRANCH" | cut -f 1)
    SPECUUID=$(git ls-remote "$PKG_URL" "$PKG_BRANCH" | cut -f 1)

    FILESFROMCACHE=$(curl $CACHEURL/rpmcache/$SPECUUID/$SRCUUID 2> /dev/null)
    echo Checking cache For $SPECUUID $SRCUUID

    mkdir -p "${PROJECT}_cached_rpms"
    echo $FILESFROMCACHE
    for file in $FILESFROMCACHE ; do
        HADFILE=1
        filename="${PROJECT}_cached_rpms/$(echo $file | sed -e 's/.*\\///g')"
        echo Downloading $file -\\> $filename
        curl $CACHEURL/$file 2> /dev/null > "$filename" || HADERROR=1
    done

    if [ -z "$HADERROR" -a -n "$HADFILE" ] ; then
        mkdir -p rpms
        cp "${PROJECT}_cached_rpms"/* rpms 
        return 0
    fi
    return 1
}

}
