#!/bin/bash
#
# Copyright 2013-2014 Cloudsoft Corporation Limited. All Rights Reserved.
#
# Licensed under the Cloudsoft EULA v1.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.cloudsoftcorp.com/cloudsoft-developer-license/
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# AMP Install Script
#
# Usage:
#     amp-install.sh [-h] [-q] [-r] [-e] [-s] [-u user] [-k key] [-p port] hostname
#
#set -x # DEBUG

function help() {
    cat <<EOF

AMP Install Script

Options

    -e  Install example blueprint files
    -p  The SSH port to connect to (default 22)
    -r  Setup random entropy for SSH
    -s  Create and set up user account
    -u  Change the AMP username (default 'amp')
    -k  The private key to use for SSH (default '~/.ssh/id_rsa')
    -q  Quiet install

Usage

    amp-install.sh [-q] [-r] [-e] [-s] [-u user] [-k key] [-p port] hostname

Installs AMP on the given hostname as 'amp' or the specified
user. Optionally installs example blueprints and creates and
configures the AMP user. Passwordless SSH access as root to
the remote host must be enabled with the given key.

Copyright 2014 by Cloudsoft Corporation Limited

EOF
    exit 0
}

function log() {
    if ! ${QUIET}; then
        echo $@
    fi
    date +"Timestamp: %Y-%m-%d %H:%M:%S.%s" >> ${LOG}
    if [ "$1" == "-n" ]; then
        shift
    fi
    if [ "$*" != "..." ]; then
        echo "Log: $*" | sed -e "s/\.\.\.//" >> ${LOG}
    fi
}

function fail() {
    log "...failed!"
    error "$*"
}

function error() {
    echo "Error: $*" | tee -a "${LOG}"
    usage
}

function usage() {
    echo "Usage: $(basename ${0}) [-h] [-q] [-r] [-e] [-s] [-u user] [-k key] [-p port] hostname"
    exit 1
}

QUIET=false
LOG="amp-install.log"
AMP_VERSION="2.0.0-M1"
SSH=ssh

while getopts ":hesu:k:q:p:r" o; do
    case "${o}" in
        h)  help
            ;;
        e)  INSTALL_EXAMPLES=true
            ;;
        s)  SETUP_USER=true
            ;;
        u)  AMP_USER="${OPTARG}"
            ;;
        k)  PRIVATE_KEY_FILE="${OPTARG}"
            ;;
        r)  SETUP_RANDOM=true
            ;;
        q)  QUIET=true
            ;;
        p)  PORT="${OPTARG}"
            ;;            
        *)  usage "Invalid option: $*"
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -ne 1 ]; then
    error "Must specify remote hostname as last argument"
fi

HOST="$1"
USER="${AMP_USER:-amp}"
PRIVATE_KEY_FILE="${PRIVATE_KEY_FILE:-${HOME}/.ssh/id_rsa}"

SSH_OPTS="-o StrictHostKeyChecking=no -p ${PORT:-22}"
if [ -f "${PRIVATE_KEY_FILE}" ]; then
    SSH_OPTS="${SSH_OPTS} -i ${PRIVATE_KEY_FILE}"
else
    error "SSH private key '${PRIVATE_KEY_FILE}' not found"
fi
SSH_PUBLIC_KEY_DATA=$(ssh-keygen -y -f ${PRIVATE_KEY_FILE})

echo "Installing AMP ${AMP_VERSION} on ${HOST}:$PORT as '${USER}'"

# Pre-requisites for this script
log -n "Configuring '${HOST}'..."

# Install packages
for package in "curl" "sed" "tar"; do
    ssh ${SSH_OPTS} root@${HOST} "which ${package} || { yum -y -q install ${package} || apt-get -y install ${package}; }" >> ${LOG} 2>&1
done
log -n "..."

# Install Java 6
if [ "${INSTALL_EXAMPLES}" ]; then
    check="javac"
else
    check="java"
    JAVA_HOME="/usr"
fi
ssh ${SSH_OPTS} root@${HOST} "which ${check} || { yum -y -q install java-1.6.0-openjdk || apt-get update && apt-get -y install openjdk-6-jre-headless; }" >> ${LOG} 2>&1
for java in "jre" "jdk" "java-1.6.0-openjdk" "java-1.6.0-openjdk-amd64"; do
    if ssh ${SSH_OPTS} root@${HOST} "test -d /usr/lib/jvm/${java}"; then
        JAVA_HOME="/usr/lib/jvm/${java}/" && echo "Java: ${JAVA_HOME}" >> ${LOG}
    fi
done
ssh ${SSH_OPTS} root@${HOST}  "test -x ${JAVA_HOME}/bin/${check}" >> ${LOG} 2>&1 || fail "Java is not installed"
log -n "..."

# Increase linux kernel entropy for faster ssh connections
if [ "${SETUP_RANDOM}" ]; then
    ssh ${SSH_OPTS} root@${HOST} "which rng-tools || { yum -y -q install rng-tools || apt-get -y install rng-tools; }" >> ${LOG} 2>&1
    if ssh ${SSH_OPTS} root@${HOST} "test -f /etc/default/rng-tools"; then
        echo "HRNGDEVICE=/dev/urandom" | ssh ${SSH_OPTS} root@${HOST} "cat >> /etc/default/rng-tools"
        ssh ${SSH_OPTS} root@${HOST} "/etc/init.d/rng-tools start" >> ${LOG} 2>&1
    else
        echo "EXTRAOPTIONS=\"-r /dev/urandom\"" | ssh ${SSH_OPTS} root@${HOST} "cat >> /etc/sysconfig/rngd"
        ssh ${SSH_OPTS} root@${HOST} "/etc/init.d/rngd start" >> ${LOG} 2>&1
    fi
    log "...done"
fi

# Create AMP user if required
if ! ssh ${SSH_OPTS} root@${HOST} "id ${USER} > /dev/null 2>&1"; then
    if [ -z "${SETUP_USER}" ]; then
        error "User '${USER}' does not exist on ${HOST}"
    fi
    log -n "Creating user '${USER}'..."
    ssh ${SSH_OPTS} root@${HOST}  "useradd ${USER} -s /bin/bash -d /home/${USER} -m" >> ${LOG} 2>&1
    ssh ${SSH_OPTS} root@${HOST}  "id ${USER}" >> ${LOG} 2>&1 || fail "User was not created"
    log "...done"
fi

# Setup AMP user
if [ "${SETUP_USER}" ]; then
    log -n "Setting up user '${USER}'..."
    ssh ${SSH_OPTS} root@${HOST} "echo '${USER} ALL = (ALL) NOPASSWD: ALL' >> /etc/sudoers"
    ssh ${SSH_OPTS} root@${HOST} "sed -i.brooklyn.bak 's/.*requiretty.*/#brooklyn-removed-require-tty/' /etc/sudoers"
    ssh ${SSH_OPTS} root@${HOST} "mkdir -p /home/${USER}/.ssh"
    ssh ${SSH_OPTS} root@${HOST} "chmod 700 /home/${USER}/.ssh"
    ssh ${SSH_OPTS} root@${HOST} "echo ${SSH_PUBLIC_KEY_DATA} >> /home/${USER}/.ssh/authorized_keys"
    ssh ${SSH_OPTS} root@${HOST} "chown -R ${USER}.${USER} /home/${USER}/.ssh"
    ssh ${SSH_OPTS} ${USER}@${HOST} "ssh-keygen -q -t rsa -N \"\" -f .ssh/id_rsa"
    ssh ${SSH_OPTS} ${USER}@${HOST} "ssh-keygen -y -f .ssh/id_rsa >> .ssh/authorized_keys"
    log "...done"
fi

# Setup AMP
log -n "Installing AMP..."
ssh ${SSH_OPTS} ${USER}@${HOST} "curl -s -o cloudsoft-amp-${AMP_VERSION}.tar.gz https://s3-eu-west-1.amazonaws.com/cloudsoft-amp/cloudsoft-amp-${AMP_VERSION}.tar.gz"
ssh ${SSH_OPTS} ${USER}@${HOST} "tar zxvf cloudsoft-amp-${AMP_VERSION}.tar.gz" >> ${LOG} 2>&1
ssh ${SSH_OPTS} ${USER}@${HOST} "test -x cloudsoft-amp-${AMP_VERSION}/bin/amp" || fail "AMP was not downloaded correctly"
log "...done"

# Configure AMP if no brooklyn.properties
if ! ssh ${SSH_OPTS} ${USER}@${HOST} "test -f .brooklyn/brooklyn.properties"; then
    log -n "Configuring AMP..."
    ssh ${SSH_OPTS} ${USER}@${HOST} "mkdir -p .brooklyn"
    ssh ${SSH_OPTS} ${USER}@${HOST} "curl -s -o .brooklyn/brooklyn.properties http://brooklyncentral.github.io/use/guide/quickstart/brooklyn.properties"
    ssh ${SSH_OPTS} ${USER}@${HOST} "sed -i.bak 's/^# brooklyn.webconsole.security.provider = brooklyn.rest.security.provider.AnyoneSecurityProvider/brooklyn.webconsole.security.provider = brooklyn.rest.security.provider.AnyoneSecurityProvider/' .brooklyn/brooklyn.properties"
    ssh ${SSH_OPTS} ${USER}@${HOST} "curl -s -o .brooklyn/catalog.xml http://brooklyncentral.github.io/use/guide/quickstart/catalog.xml"
    log "...done"
fi

# Install example Jars and catalog
if [ "${INSTALL_EXAMPLES}" ]; then
    log -n "Installing examples..."

    # Install gunzip, git and maven
    ssh ${SSH_OPTS} root@${HOST} "which gunzip || { yum -y -q install gunzip || apt-get -y install gunzip; }" >> ${LOG} 2>&1
    ssh ${SSH_OPTS} root@${HOST} "which git || { yum -y -q install git || apt-get -y install git; }" >> ${LOG} 2>&1
    ssh ${SSH_OPTS} root@${HOST} "mkdir -p /usr/local/apache-maven/"
    ssh ${SSH_OPTS} root@${HOST} "curl -s -o /usr/local/apache-maven/apache-maven-3.2.1-bin.tar.gz https://s3-eu-west-1.amazonaws.com/cloudsoft-amp/apache-maven-3.2.1-bin.tar.gz"
    ssh ${SSH_OPTS} root@${HOST} "tar zxvf /usr/local/apache-maven/apache-maven-3.2.1-bin.tar.gz -C /usr/local/apache-maven/" >> ${LOG} 2>&1
    log -n "..."

    # Configure required development tools
    ssh ${SSH_OPTS} ${USER}@${HOST} "cat >> .bashrc" <<EOF
export JAVA_HOME=${JAVA_HOME}
export M2_HOME=/usr/local/apache-maven/apache-maven-3.2.1
export PATH=\${M2_HOME}/bin:\${JAVA_HOME}/bin:\${PATH}
EOF
    log -n "..."

    # Build and install OpenGamma blueprints
    ssh ${SSH_OPTS} ${USER}@${HOST} "mkdir projects"
    ssh ${SSH_OPTS} ${USER}@${HOST} "git clone https://github.com/cloudsoft/brooklyn-opengamma.git projects/brooklyn-opengamma" >> ${LOG} 2>&1
    ssh ${SSH_OPTS} ${USER}@${HOST} "bash -ic 'mvn --quiet clean install -f ./projects/brooklyn-opengamma/pom.xml'" >> ${LOG} 2>&1
    ssh ${SSH_OPTS} ${USER}@${HOST} "cat > .brooklyn/catalog.xml" <<EOF
<?xml version="1.0"?>
<catalog>
  <name>AMP Example Blueprints</name>
  <template type="brooklyn.demo.WebClusterDatabaseExample" name="Web Cluster with DB">
    <description>Deploys a demonstration web application to a managed JBoss cluster with elasticity, persisting to a MySQL</description>
    <iconUrl>http://downloads.cloudsoftcorp.com/brooklyn/catalog/logos/JBoss_by_Red_Hat.png</iconUrl>
  </template>
  <template type="brooklyn.demo.GlobalWebFabricExample" name="GeoDNS Web Fabric DB">
    <description>Deploys a demonstration web application to JBoss clusters around the world</description>
    <iconUrl>http://downloads.cloudsoftcorp.com/brooklyn/catalog/logos/JBoss_by_Red_Hat.png</iconUrl>
  </template>
  <template type="io.cloudsoft.opengamma.app.ElasticOpenGammaApplication" name="OpenGamma Cluster">
    <description>Deploys the OpenGamma financial analytics platform.</description>
    <iconUrl>http://downloads.cloudsoftcorp.com/brooklyn/catalog/logos/opengamma-circle-icon.png</iconUrl>
  </template>
  <classpath>
    <entry>https://oss.sonatype.org/service/local/artifact/maven/redirect?r=releases&amp;g=io.brooklyn.example&amp;a=brooklyn-example-simple-web-cluster&amp;v=0.7.0-M1&amp;e=jar</entry>
    <entry>https://oss.sonatype.org/service/local/artifact/maven/redirect?r=releases&amp;g=io.brooklyn.example&amp;a=brooklyn-example-global-web-fabric&amp;v=0.7.0-M1&amp;e=jar</entry>
    <entry>file://~/.m2/repository/io/cloudsoft/opengamma/brooklyn-opengamma/0.3.0-SNAPSHOT/brooklyn-opengamma-0.3.0-SNAPSHOT.jar</entry>
  </classpath>
</catalog>
EOF
    ssh ${SSH_OPTS} ${USER}@${HOST} "curl -s -o .brooklyn/MaxMind-GeoLiteCity.dat.gz http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz"
    ssh ${SSH_OPTS} ${USER}@${HOST} "gunzip .brooklyn/MaxMind-GeoLiteCity.dat.gz"
    log "...done"
fi

# Run AMP
log -n "Starting AMP..."
ssh -n -f ${SSH_OPTS} ${USER}@${HOST} "nohup ./cloudsoft-amp-${AMP_VERSION}/bin/amp launch >> ./cloudsoft-amp-${AMP_VERSION}/amp-console.log 2>&1 &"
log "...done"
echo "Console URL is http://${HOST}:8081/"
