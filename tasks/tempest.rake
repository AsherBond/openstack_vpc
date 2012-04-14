include ChefVPCToolkit::CloudServersVPC

desc "Run tempest."
task :tempest do

sg=ServerGroup.fetch(:source => "cache")
gw_ip=sg.vpn_gateway_ip
server_name=ENV['SERVER_NAME']
server_name = "nova1" if server_name.nil?
git_url=ENV['GIT_URL']
git_url = "git://github.com/openstack/tempest.git" if git_url.nil?
image_name=ENV.fetch('IMAGE_NAME', "ami-tty")
out=%x{
ssh #{SSH_OPTS} root@#{gw_ip} bash <<-"BASH_EOF"
ssh #{server_name} bash <<-"EOF_SERVER_NAME"

for PKG in git python-unittest2 python-paramiko euca2ools python-nose; do
if [ -e /bin/rpm ]; then
  rpm -qi $PKG &> /dev/null || yum -y -q install $PKG &> /dev/null
else
  dpkg -l $PKG &> /dev/null || apt-get install -q -y $PKG &> /dev/null
fi
done

[ -d "/root/tempest" ] || git clone #{git_url} "tempest"
[ -f /root/novarc ] && source /root/novarc
[ -f /root/openstackrc ] && source /root/openstackrc

IMG_ID=$(nova image-list | grep #{image_name} | tail -n 1 | sed -e "s|\\| \\([^ ]*\\) .*|\\1|")
[ -z "$IMG_ID" ] && { echo "Failed to set image ID."; exit 1; }
cat > /root/tempest/etc/tempest.conf <<EOF_CAT
[identity]
use_ssl=False
host=127.0.0.1
port=5000
api_version=v2.0
path=tokens
strategy=keystone

[compute]
username=admin
password=AABBCC112233
tenant_name=admin

alt_username=demo
alt_password=DDEEFF445566
alt_tenant_name=demo

image_ref=$IMG_ID
image_ref_alt=$IMG_ID
flavor_ref=1
flavor_ref_alt=2

build_interval=10
build_timeout=600
catalog_type=compute

create_image_enabled=true
resize_available=true
authentication=keystone_v2
ssh_timeout=300

[image]
username=admin
password=AABBCC112233
tenant_name=admin
EOF_CAT

cd /root/tempest
nosetests tempest -a type=smoke

EOF_SERVER_NAME
BASH_EOF
}
retval=$?
puts out
fail "Tempest failed!" if not retval.success?
end

