namespace :keystone do

    task :build_ubuntu_packages => :tarball do

        src_dir=ENV['SOURCE_DIR']
        raise "Please specify a SOURCE_DIR." if src_dir.nil?
        deb_packager_url=ENV['DEB_PACKAGER_URL']
        if deb_packager_url.nil? then
            deb_packager_url="lp:~openstack-ubuntu-packagers/keystone/ubuntu"
        end
        pwd=Dir.pwd
        keystone_revision=get_revision(src_dir)
        raise "Failed to get keystone revision." if keystone_revision.empty?

        puts "Building keystone packages using: #{deb_packager_url}"

        remote_exec %{
if ! /usr/bin/dpkg -l add-apt-key &> /dev/null; then
  cat > /etc/apt/sources.list.d/nova_ppa-source.list <<-EOF_CAT
deb http://ppa.launchpad.net/nova-core/trunk/ubuntu $(lsb_release -sc) main
EOF_CAT
  apt-get -y -q install add-apt-key &> /dev/null || { echo "Failed to install add-apt-key."; exit 1; }
  add-apt-key 2A2356C9 &> /dev/null || { echo "Failed to add apt key for PPA."; exit 1; }
  apt-get -q update &> /dev/null || { echo "Failed to apt-get update."; exit 1; }
fi

DEBIAN_FRONTEND=noninteractive apt-get -y -q install dpkg-dev bzr git quilt debhelper python-m2crypto python-all python-setuptools python-sphinx python-distutils-extra python-twisted-web python-gflags python-mox python-carrot python-boto python-amqplib python-ipy python-sqlalchemy-ext python-passlib python-eventlet python-routes python-webob python-cheetah python-nose python-paste python-pastedeploy python-tempita python-migrate python-netaddr python-lockfile pep8 python-sphinx &> /dev/null || { echo "Failed to install prereq packages."; exit 1; }

BUILD_TMP=$(mktemp -d)
cd "$BUILD_TMP"
mkdir keystone && cd keystone
tar xzf /tmp/keystone.tar.gz 2> /dev/null || { echo "Failed to extract keystone source tar."; exit 1; }
rm -rf .bzr
rm -rf .git
cd ..
bzr checkout --lightweight #{deb_packager_url} keystone &> /tmp/bzrkeystone.log || { echo "Failed checkout keystone builder: #{deb_packager_url}."; cat /tmp/bzrkeystone.log; exit 1; }
rm -rf keystone/.bzr
rm -rf keystone/.git
cd keystone
echo "keystone (9999.1-vpc#{keystone_revision}) $(lsb_release -sc); urgency=high" > debian/changelog
echo " -- Dev Null <dev@null.com>  $(date +\"%a, %e %b %Y %T %z\")" >> debian/changelog
BUILD_LOG=$(mktemp)
DEB_BUILD_OPTIONS=nocheck,nodocs dpkg-buildpackage -rfakeroot -b -uc -us -d \
 &> $BUILD_LOG || { echo "Failed to build keystone packages."; cat $BUILD_LOG; exit 1; }
cd /tmp
[ -d /root/openstack-packages ] || mkdir -p /root/openstack-packages
rm -f /root/openstack-packages/keystone*
cp $BUILD_TMP/*.deb /root/openstack-packages
rm -Rf "$BUILD_TMP"
BASH_EOF
        } do |ok, out|
            puts out
            fail "Build packages failed!" unless ok
        end
    end

    task :build_fedora_packages do

        packager_url= ENV.fetch("RPM_PACKAGER_URL", "git://pkgs.fedoraproject.org/openstack-keystone.git")
        ENV["RPM_PACKAGER_URL"] = packager_url if ENV["RPM_PACKAGER_URL"].nil?
        if ENV["GIT_MASTER"].nil?
            ENV["GIT_MASTER"] = "git://github.com/openstack/keystone.git"
        end
        ENV["PROJECT_NAME"] = "keystone"
        Rake::Task["fedora:build_packages"].invoke
    end

    task :build_python_keystoneclient do

        packager_url= ENV.fetch("RPM_PACKAGER_URL", "git://pkgs.fedoraproject.org/python-keystoneclient.git")
        ENV["RPM_PACKAGER_URL"] = packager_url if ENV["RPM_PACKAGER_URL"].nil?
        if ENV["GIT_MASTER"].nil?
            ENV["GIT_MASTER"] = "git://github.com/openstack/python-keystoneclient.git"
        end
        ENV["PROJECT_NAME"] = "python-keystoneclient"
        Rake::Task["fedora:build_packages"].invoke
    end

    task :tarball do
        gw_ip = ServerGroup.get.gateway_ip
        src_dir = ENV['SOURCE_DIR'] or raise "Please specify a SOURCE_DIR."
        keystone_revision = get_revision(src_dir)
        raise "Failed to get keystone revision." if keystone_revision.empty?

        shh %{
            set -e
            cd #{src_dir}
            [ -f keystone/__init__.py ] \
                || { echo "Please specify a valid keystone project dir."; exit 1; }
            MY_TMP="#{mktempdir}"
            cp -r "#{src_dir}" $MY_TMP/src
            cd $MY_TMP/src
            [ -d ".git" ] && rm -Rf .git
            [ -d ".bzr" ] && rm -Rf .bzr
            [ -d ".keystone-venv" ] && rm -Rf .keystone-venv
            [ -d ".venv" ] && rm -Rf .venv
            tar czf $MY_TMP/keystone.tar.gz . 2> /dev/null || { echo "Failed to create keystone source tar."; exit 1; }
            scp #{SSH_OPTS} $MY_TMP/keystone.tar.gz root@#{gw_ip}:/tmp
            rm -rf "$MY_TMP"
        } do |ok, out|
            fail "Unable to create keystone tarball! \n #{out}" unless ok
        end
    end

    desc "Build Keystone packages."
    task :build_packages do
        if ENV['RPM_PACKAGER_URL'].nil? then
            Rake::Task["keystone:build_ubuntu_packages"].invoke
        else
            Rake::Task["keystone:build_fedora_packages"].invoke
        end
    end

    desc "Configure keystone"
    task :configure do

        server_name=ENV['SERVER_NAME']
        server_name = "nova1" if server_name.nil?
        keystone_data_file = File.join(File.dirname(__FILE__), '..', 'scripts','keystone_data.sh')
        script = IO.read(keystone_data_file)
        remote_exec %{
ssh #{server_name} bash <<-"EOF_SERVER_NAME"
SERVICE_TOKEN=ADMIN
SERVICE_ENDPOINT=http://localhost:35357/v2.0
AUTH_ENDPOINT=http://localhost:5000/v2.0
#{script}
EOF_SERVER_NAME
RETVAL=$?
exit $RETVAL
        } do |ok, out|
            fail "Keystone configuration failed! \n #{out}" unless ok
        end

    end

end
