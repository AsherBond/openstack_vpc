namespace :glance do

    desc "Install local Glance source code into the group."
    task :install_source => :tarball do
        server_name=ENV['SERVER_NAME']
        server_name = "glance1" if server_name.nil?
        remote_exec %{
scp /tmp/glance.tar.gz #{server_name}:/tmp
ssh #{server_name} bash <<-"EOF_SERVER_NAME"
cd /usr/lib/python2.7/site-packages
rm -Rf glance
tar xf /tmp/glance.tar.gz 2> /dev/null || { echo "Failed to extract glance source tar."; exit 1; }
service openstack-glance-api restart
service openstack-glance-registry restart
EOF_SERVER_NAME
        } do |ok, out|
            puts out
            fail "Failed to install source!" unless ok
        end
    end

    desc "Build Glance packages."
    task :build_packages do
        if ENV['RPM_PACKAGER_URL'].nil? then
            Rake::Task["glance:build_ubuntu_packages"].invoke
        else
            Rake::Task["glance:build_fedora_packages"].invoke
        end
    end

    task :build_fedora_packages do
        packager_url= ENV.fetch("RPM_PACKAGER_URL", "git://pkgs.fedoraproject.org/openstack-glance.git")
        ENV["RPM_PACKAGER_URL"] = packager_url if ENV["RPM_PACKAGER_URL"].nil?
        if ENV["GIT_MASTER"].nil?
            ENV["GIT_MASTER"] = "git://github.com/openstack/glance.git"
        end
        ENV["PROJECT_NAME"] = "glance"
        Rake::Task["fedora:build_packages"].invoke
    end

    task :build_python_warlock do

        # First we build warlock here until it gets into Fedora
        packager_url= ENV.fetch("RPM_PACKAGER_URL", "git://github.com/fedora-openstack/python-warlock.git")
        ENV["RPM_PACKAGER_URL"] = packager_url if ENV["RPM_PACKAGER_URL"].nil?
        if ENV["GIT_MASTER"].nil?
            ENV["GIT_MASTER"] = "git://github.com/bcwaldon/warlock.git"
        end
        ENV["PROJECT_NAME"] = "warlock"
        ENV["SOURCE_URL"] = "git://github.com/bcwaldon/warlock.git"
        Rake::Task["fedora:build_packages"].invoke

    end

    task :build_python_glanceclient do

        # Now build python-glanceclient
        packager_url= ENV.fetch("RPM_PACKAGER_URL", "git://pkgs.fedoraproject.org/python-glanceclient.git")
        ENV["RPM_PACKAGER_URL"] = packager_url if ENV["RPM_PACKAGER_URL"].nil?
        if ENV["GIT_MASTER"].nil?
            ENV["GIT_MASTER"] = "git://github.com/openstack/python-glanceclient.git"
        end
        ENV["PROJECT_NAME"] = "python-glanceclient"
        Rake::Task["fedora:build_packages"].invoke

    end

    task :build_ubuntu_packages => :tarball do

        deb_packager_url=ENV['DEB_PACKAGER_URL']
        if deb_packager_url.nil? then
            deb_packager_url="lp:~openstack-ubuntu-packagers/glance/ubuntu"
        end
        pwd=Dir.pwd
        glance_revision=get_revision(src_dir)
        raise "Failed to get glance revision." if glance_revision.empty?

        puts "Building glance packages using: #{deb_packager_url}"

        remote_exec %{
DEBIAN_FRONTEND=noninteractive apt-get -y -q install dpkg-dev bzr git quilt debhelper python-m2crypto python-all python-setuptools python-sphinx python-distutils-extra python-twisted-web python-gflags python-mox python-carrot python-boto python-amqplib python-ipy python-sqlalchemy-ext  python-eventlet python-routes python-webob python-cheetah python-nose python-paste python-pastedeploy python-tempita python-migrate python-netaddr python-glance python-lockfile pep8 python-sphinx &> /dev/null || { echo "Failed to install prereq packages."; exit 1; }

BUILD_TMP=$(mktemp -d)
cd "$BUILD_TMP"
mkdir glance && cd glance
tar xzf /tmp/glance.tar.gz 2> /dev/null || { echo "Falied to extract glance source tar."; exit 1; }
rm -rf .bzr
rm -rf .git
cd ..
bzr checkout --lightweight #{deb_packager_url} glance &> /tmp/bzrglance.log || { echo "Failed checkout glance builder: #{deb_packager_url}."; cat /tmp/bzrglance.log; exit 1; }
rm -rf glance/.bzr
rm -rf glance/.git
cd glance
#No jsonschema packages for Oneiric.... so lets do this for now (HACK!)
sed -e 's|^import jsonschema||' -i glance/schema.py
sed -e 's|jsonschema.validate.*|pass|' -i glance/schema.py
sed -e 's|jsonschema.ValidationError|Exception|' -i glance/schema.py
echo "glance (9999.1-vpc#{glance_revision}) $(lsb_release -sc); urgency=high" > debian/changelog
echo " -- Dev Null <dev@null.com>  $(date +\"%a, %e %b %Y %T %z\")" >> debian/changelog
BUILD_LOG=$(mktemp)
DEB_BUILD_OPTIONS=nocheck,nodocs dpkg-buildpackage -rfakeroot -b -uc -us -d \
 &> $BUILD_LOG || { echo "Failed to build packages."; cat $BUILD_LOG; exit 1; }
cd /tmp
[ -d /root/openstack-packages ] || mkdir -p /root/openstack-packages
rm -f /root/openstack-packages/glance*
cp $BUILD_TMP/*.deb /root/openstack-packages
rm -Rf "$BUILD_TMP"
        } do |ok, out|
            puts out
            fail "Build packages failed!" unless ok
        end

    end

    task :tarball do
        gw_ip = ServerGroup.get.gateway_ip
        src_dir = ENV['SOURCE_DIR'] or raise "Please specify a SOURCE_DIR."
        glance_revision = get_revision(src_dir)
        raise "Failed to get glance revision." if glance_revision.empty?

        shh %{
            set -e
            cd #{src_dir}
            [ -f glance/version.py ] \
                || { echo "Please specify a valid glance project dir."; exit 1; }
            MY_TMP="#{mktempdir}"
            cp -r "#{src_dir}" $MY_TMP/src
            cd $MY_TMP/src
            [ -d ".git" ] && rm -Rf .git
            [ -d ".bzr" ] && rm -Rf .bzr
            [ -d ".glance-venv" ] && rm -Rf .glance-venv
            [ -d ".venv" ] && rm -Rf .venv
            tar czf $MY_TMP/glance.tar.gz . 2> /dev/null || { echo "Failed to create glance source tar."; exit 1; }
            scp #{SSH_OPTS} $MY_TMP/glance.tar.gz root@#{gw_ip}:/tmp
            rm -rf "$MY_TMP"
        } do |ok, res|
            fail "Unable to create glance tarball! \n #{res}" unless ok
        end
    end

    task :load_images do
        server_name=ENV['SERVER_NAME']
        # default to nova1 if SERVER_NAME is unset
        server_name = "nova1" if server_name.nil?
        remote_exec %{
ssh #{server_name} bash <<-"EOF_SERVER_NAME"
  mkdir -p /var/lib/glance/
  [ -f /root/openstackrc ] && source /root/openstackrc
  if [ ! -d "/tmp/tty_linux" ]; then
    curl http://c3226372.r72.cf0.rackcdn.com/tty_linux.tar.gz | tar xvz -C /tmp/
  fi
  ARI_ID=$(glance image-create --name "ari-tty" --disk-format="ari" --container-format="ari" --is-public=true < /tmp/tty_linux/ramdisk | awk '/ id / { print $4 }')
  echo "ARI_ID=$ARI_ID"
  AKI_ID=$(glance image-create --name "aki-tty" --disk-format="aki" --container-format="aki" --is-public=true < /tmp/tty_linux/kernel | awk '/ id / { print $4 }')
  echo "AKI_ID=$AKI_ID"
  glance image-create --name "ami-tty" --disk-format="ami" --container-format="ami" --is-public=true --property ramdisk_id=$ARI_ID --property kernel_id=$AKI_ID < /tmp/tty_linux/image
EOF_SERVER_NAME
        } do |ok, out|
            puts out
            fail "Load images failed!" unless ok
        end
    end

    task :load_images_xen do
        server_name=ENV['SERVER_NAME']
        # default to nova1 if SERVER_NAME is unset
        server_name = "nova1" if server_name.nil?
        remote_exec %{
if [ -f /images/squeeze-agent-0.0.1.31.ova ]; then
  scp /images/squeeze-agent-0.0.1.31.ova #{server_name}:/tmp/
fi
ssh #{server_name} bash <<-"EOF_SERVER_NAME"
  mkdir -p /var/lib/glance/
  [ -f /root/openstackrc ] && source /root/openstackrc
  if [ ! -f /tmp/squeeze-agent-0.0.1.31.ova ]; then
    cd /tmp
    curl http://c3324746.r46.cf0.rackcdn.com/squeeze-agent-0.0.1.31.ova -o /tmp/squeeze-agent-0.0.1.31.ova
  fi
  glance image-create --name "squeeze" --disk-format="vhd" --container-format="ovf" --is-public=true < /tmp/squeeze-agent-0.0.1.31.ova
EOF_SERVER_NAME
        } do |ok, out|
            puts out
            fail "Load images failed!" unless ok
        end
    end

end
