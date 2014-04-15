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
#     amp-install.sh [-h] [-q] [-e] [-s] [-u user] [-k key] hostname
#
#set -x # DEBUG

function help() {
    cat <<EOF

AMP Install Script

Options

    -e  Install example blueprint files
    -s  Create and set up user account
    -u  Change the AMP username (default 'amp')
    -k  The private key to use for SSH (default '~/.ssh/id_rsa')
    -q  Quiet install

Usage

    amp-install.sh [-q] [-e] [-s] [-u user] [-k key] hostname

Installs AMP on the given hostname as 'amp' or the specified
user. Optionally installs example blueprints and creates and
configures the AMP user. Passwordless SSH access as root to
the remote host must be enabled with the given key.

Copyright 2014 by Cloudsoft Corporation Limited

EOF
    exit 0
}

function error() {
    echo "Error: $*"
    usage
}

function usage() {
    echo "Usage: $(basename ${0}) [-h] [-q] [-e] [-s] [-u user] [-k key] [-p port] hostname"
    exit 1
}

QUIET=false
LOG="amp-install.log"
AMP_VERSION="2.0.0-M1"

while getopts ":hesu:k:q:p:" o; do
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

HOST="${1}"
PORT="${PORT:-22}"
USER="${AMP_USER:-amp}"
PRIVATE_KEY_FILE="${PRIVATE_KEY_FILE:-${HOME}/.ssh/id_rsa}"

SSH_OPTS="-o StrictHostKeyChecking=no"
if [ -f ${PRIVATE_KEY_FILE} ]; then
    SSH_OPTS="${SSH_OPTS} -i ${PRIVATE_KEY_FILE}"
fi
SSH_PUBLIC_KEY_DATA=$(ssh-keygen -y -f ${PRIVATE_KEY_FILE})

echo "Installing AMP ${AMP_VERSION} on ${HOST} (using port $PORT) as '${USER}'"

# pre-requisites for this script
${QUIET} || echo "Installing pre-requisites..."
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "which which || { yum -y -q install which || apt-get -y install which; }" > ${LOG} 2>&1
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "which curl || { yum -y -q install curl || apt-get -y install curl; }" > ${LOG} 2>&1
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "which sed || { yum -y -q install sed || apt-get -y install sed; }" > ${LOG} 2>&1
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "which tar || { yum -y -q install tar || apt-get -y install tar; }" > ${LOG} 2>&1
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "which gunzip || { yum -y -q install gunzip || apt-get -y install gunzip; }" > ${LOG} 2>&1
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "which git || { yum -q -y install git || apt-get -y install git; }" > ${LOG} 2>&1
# install java6
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "which java || { yum -y -q install java-1.6.0-openjdk || apt-get update && apt-get -y install openjdk-6-jre-headless; }" > ${LOG} 2>&1 
if [ -r /etc/lsb-release ]; then
    JAVA_HOME="/usr/lib/jvm/java-1.6.0-openjdk-amd64/"
else
    JAVA_HOME="/usr/lib/jvm/jre/"
fi
# install maven
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "mkdir -p /usr/local/apache-maven/"
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "curl -s -o /usr/local/apache-maven/apache-maven-3.2.1-bin.tar.gz https://s3-eu-west-1.amazonaws.com/cloudsoft-amp/apache-maven-3.2.1-bin.tar.gz"
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "tar xzf /usr/local/apache-maven/apache-maven-3.2.1-bin.tar.gz -C /usr/local/apache-maven/"
# increase linux kernel entropy for faster ssh connections
ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "which rng-tools || { yum -y -q install rng-tools || apt-get -y install rng-tools; }" > ${LOG} 2>&1
if [ -f "/etc/default/rng-tools" ]; then
    ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "cat >> /etc/default/rng-tools" <<EOF
HRNGDEVICE=/dev/urandom
EOF
    ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "/etc/init.d/rng-tools start" > ${LOG} 2>&1
else
    ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "cat >> /etc/sysconfig/rngd" <<EOF
EXTRAOPTIONS="-r /dev/urandom"
EOF
    ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "/etc/init.d/rngd start" > ${LOG} 2>&1
fi

${QUIET} || echo "...finished"

# Create AMP user if required
if ! ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "id -o ${USER} > /dev/null 2>&1"; then
    if [ -z "${SETUP_USER}" ]; then
        error "User '${USER}' does not exist on ${HOST}"
    fi
    ${QUIET} || echo -n "Creating user '${USER}'..."
    ssh ${SSH_OPTS} root@${HOST}  -p ${PORT} "useradd ${USER} -s '/bin/bash' -d \"/home/${USER}\" -m" > ${LOG} 2>&1
    ${QUIET} || echo "...finished"
fi

# Setup AMP user
if [ "${SETUP_USER}" ]; then
    ${QUIET} || echo -n "Setting up user '${USER}'..."
    ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "echo '${USER} ALL = (ALL) NOPASSWD: ALL' >> /etc/sudoers"
    ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "sed -i.brooklyn.bak 's/.*requiretty.*/#brooklyn-removed-require-tty/' /etc/sudoers"
    ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "mkdir -p /home/${USER}/.ssh"
    ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "chmod 700 /home/${USER}/.ssh"
    ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "echo ${SSH_PUBLIC_KEY_DATA} >> /home/${USER}/.ssh/authorized_keys"
    ssh ${SSH_OPTS} root@${HOST} -p ${PORT} "chown -R ${USER}.${USER} /home/${USER}/.ssh"
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "ssh-keygen -q -t rsa -N \"\" -f .ssh/id_rsa"
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "ssh-keygen -y -f .ssh/id_rsa | cat >> .ssh/authorized_keys"
    ${QUIET} || echo "...finished"
fi

# Setup AMP
${QUIET} || echo -n "Installing AMP..."
ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "curl -s -o cloudsoft-amp-${AMP_VERSION}.tar.gz https://s3-eu-west-1.amazonaws.com/cloudsoft-amp/cloudsoft-amp-${AMP_VERSION}.tar.gz"
ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "tar zxf cloudsoft-amp-${AMP_VERSION}.tar.gz"
${QUIET} || echo "...finished"

# Configure AMP if no brooklyn.properties
if ! ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "test -f .brooklyn/brooklyn.properties"; then
    ${QUIET} || echo -n "Configuring AMP..."
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "mkdir -p .brooklyn"
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "curl -s -o .brooklyn/brooklyn.properties http://brooklyncentral.github.io/use/guide/quickstart/brooklyn.properties"
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "sed -i.bak 's/^# brooklyn.webconsole.security.provider = brooklyn.rest.security.provider.AnyoneSecurityProvider/brooklyn.webconsole.security.provider = brooklyn.rest.security.provider.AnyoneSecurityProvider/' .brooklyn/brooklyn.properties"
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "curl -s -o .brooklyn/catalog.xml http://brooklyncentral.github.io/use/guide/quickstart/catalog.xml"
    ${QUIET} || echo "...finished"
fi

# Install example Jars and catalog
if [ "${INSTALL_EXAMPLES}" ]; then
    ${QUIET} || echo -n "Installing examples..."
    # Configure required development tools
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "echo 'JAVA_HOME=${JAVA_HOME}' >> ~/.bashrc"
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "cat >> ~/.bashrc" <<EOF
export M2_HOME=/usr/local/apache-maven/apache-maven-3.2.1
export PATH=\${M2_HOME}/bin:\${PATH}
EOF
    ${QUIET} || echo -n "..."

    # Build and install OpenGamma blueprints
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "mkdir projects"
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "git clone https://github.com/cloudsoft/brooklyn-opengamma.git projects/brooklyn-opengamma" > ${LOG} 2>&1
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "bash -ic 'mvn --quiet clean install -f ./projects/brooklyn-opengamma/pom.xml'" > ${LOG} 2>&1
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "cat > .brooklyn/catalog.xml" <<EOF
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
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "curl -s -o .brooklyn/MaxMind-GeoLiteCity.dat.gz http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz"
    ssh ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "gunzip .brooklyn/MaxMind-GeoLiteCity.dat.gz"
    ${QUIET} || echo "...finished"
fi

# Run AMP
${QUIET} || echo -n "Starting AMP..."
ssh -n -f ${SSH_OPTS} ${USER}@${HOST} -p ${PORT} "nohup ./cloudsoft-amp-${AMP_VERSION}/bin/amp launch >> ./cloudsoft-amp-${AMP_VERSION}/amp-console.log 2>&1 &"
${QUIET} || echo "...finished"
echo "Console URL is http://${HOST}:8081/"
