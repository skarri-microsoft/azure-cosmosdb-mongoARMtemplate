#!/bin/bash

mongoAdminUser=$1
mongoAdminPasswd=$2

install_mongo3() {
#create repo
cat > /etc/yum.repos.d/mongodb-org-3.2.repo <<EOF
[mongodb-org-3.2]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/3.2/x86_64/
gpgcheck=0
enabled=1
EOF

	#install
	yum install -y mongodb-org

	#ignore update
	sed -i '$a exclude=mongodb-org,mongodb-org-server,mongodb-org-shell,mongodb-org-mongos,mongodb-org-tools' /etc/yum.conf

	#disable selinux
	sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/sysconfig/selinux
	sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
	setenforce 0

	#kernel settings
	if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]];then
		echo never > /sys/kernel/mm/transparent_hugepage/enabled
	fi
	if [[ -f /sys/kernel/mm/transparent_hugepage/defrag ]];then
		echo never > /sys/kernel/mm/transparent_hugepage/defrag
	fi

	#configure
	sed -i 's/\(bindIp\)/#\1/' /etc/mongod.conf

	#set keyfile
	echo "vfr4CDE1" > /etc/mongokeyfile
	chown mongod:mongod /etc/mongokeyfile
	chmod 600 /etc/mongokeyfile
	sed -i 's/^#security/security/' /etc/mongod.conf
	sed -i '/^security/akeyFile: /etc/mongokeyfile' /etc/mongod.conf
	sed -i 's/^keyFile/  keyFile/' /etc/mongod.conf
}


install_mongo3


#start router server
mongos --configdb crepset/10.0.0.240:27019,10.0.0.241:27019,10.0.0.242:27019 --port 27017 --logpath /var/log/mongodb/mongos.log --fork --keyFile /etc/mongokeyfile


#check router server starts or not
for((i=1;i<=3;i++))
do
	sleep 30
	n=`ps -ef |grep "mongos --configdb" |grep -v grep |wc -l`
	if [[ $n -eq 1 ]];then
		echo "mongos started successfully"
		break
	else
		mongos --configdb crepset/10.0.0.240:27019,10.0.0.241:27019,10.0.0.242:27019 --port 27017 --logpath /var/log/mongodb/mongos.log --fork --keyFile /etc/mongokeyfile
		continue
	fi
done

n=`ps -ef |grep "mongos --configdb" |grep -v grep |wc -l`
if [[ $n -ne 1 ]];then
echo "mongos tried to start 3 times but failed!"
fi

#add shard
mongo --port 27017 <<EOF
use admin
db.auth("$mongoAdminUser","$mongoAdminPasswd")
sh.addShard("repset1/10.0.0.100:27017")
db.runCommand( { listshards : 1 } )
exit
EOF
if [[ $? -eq 0 ]];then
echo "mongo shard added succeefully."
else
echo "mongo shard added failed!"
fi


#set mongod auto start
cat > /etc/init.d/mongod1 <<EOF
#!/bin/bash
#chkconfig: 35 84 15
#description: mongod auto start
. /etc/init.d/functions

Name=mongod1
start() {
if [[ ! -d /var/run/mongodb ]];then
mkdir /var/run/mongodb
chown -R mongod:mongod /var/run/mongodb
fi
mongos --configdb crepset/10.0.0.240:27019,10.0.0.241:27019,10.0.0.242:27019 --port 27017 --logpath /var/log/mongodb/mongos.log --fork --keyFile /etc/mongokeyfile
}
stop() {
pkill mongod
}
restart() {
stop
sleep 15
start
}

case "\$1" in
    start)
	start;;
	stop)
	stop;;
	restart)
	restart;;
	status)
	status \$Name;;
	*)
	echo "Usage: service mongod1 start|stop|restart|status"
esac
EOF
chmod +x /etc/init.d/mongod1
chkconfig mongod1 on
