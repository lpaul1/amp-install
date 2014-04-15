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
    echo "Usage: $(basename ${0}) [-h] [-q] [-e] [-s] [-u user] [-k key] hostname"
    exit 1
}

QUIET=false
LOG="amp-install.log"
AMP_VERSION="2.0.0-M1"

while getopts ":hesu:k:q" o; do
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
        *)  usage "Invalid option: $*"
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -ne 1 ]; then
    error "Must specify remote hostname as last argument"
fi

HOST="${1}"
USER="${AMP_USER:-amp}"
PRIVATE_KEY_FILE="${PRIVATE_KEY_FILE:-${HOME}/.ssh/id_rsa}"

SSH_OPTS="-o StrictHostKeyChecking=no"
if [ -f ${PRIVATE_KEY_FILE} ]; then
    SSH_OPTS="${SSH_OPTS} -i ${PRIVATE_KEY_FILE}"
fi
SSH_PUBLIC_KEY_DATA=$(ssh-keygen -y -f ${PRIVATE_KEY_FILE})

echo "Installing AMP ${AMP_VERSION} on ${HOST} as '${USER}'"

# Create AMP user if required
if ! ssh ${SSH_OPTS} root@${HOST} "id -o ${USER} > /dev/null 2>&1"; then
    if [ -z "${SETUP_USER}" ]; then
        error "User '${USER}' does not exist on ${HOST}"
    fi
    ${QUIET} || echo -n "Creating user '${USER}'..."
    ssh ${SSH_OPTS} root@${HOST} "useradd ${USER}" > ${LOG} 2>&1
    ${QUIET} || echo "...finished"
fi

# Setup AMP user
if [ "${SETUP_USER}" ]; then
    ${QUIET} || echo -n "Setting up user '${USER}'..."
    ssh ${SSH_OPTS} root@${HOST} "echo '${USER} ALL = (ALL) NOPASSWD: ALL' >> /etc/sudoers"
    ssh ${SSH_OPTS} root@${HOST} "sed -i.brooklyn.bak 's/.*requiretty.*/#brooklyn-removed-require-tty/' /etc/sudoers"
    ssh ${SSH_OPTS} root@${HOST} "mkdir -p /home/${USER}/.ssh"
    ssh ${SSH_OPTS} root@${HOST} "chmod 700 /home/${USER}/.ssh"
    ssh ${SSH_OPTS} root@${HOST} "echo ${SSH_PUBLIC_KEY_DATA} >> /home/${USER}/.ssh/authorized_keys"
    ssh ${SSH_OPTS} root@${HOST} "chown -R ${USER}.${USER} /home/${USER}/.ssh"
    ssh ${SSH_OPTS} ${USER}@${HOST} "ssh-keygen -q -t rsa -N \"\" -f .ssh/id_rsa"
    ssh ${SSH_OPTS} ${USER}@${HOST} "ssh-keygen -y -f .ssh/id_rsa | cat >> .ssh/authorized_keys"
    ${QUIET} || echo "...finished"
fi

# Setup AMP
${QUIET} || echo -n "Installing AMP..."
ssh ${SSH_OPTS} ${USER}@${HOST} "curl -s -o cloudsoft-amp-${AMP_VERSION}.tar.gz https://s3-eu-west-1.amazonaws.com/cloudsoft-amp/cloudsoft-amp-${AMP_VERSION}.tar.gz"
ssh ${SSH_OPTS} ${USER}@${HOST} "tar zxf cloudsoft-amp-${AMP_VERSION}.tar.gz"
${QUIET} || echo "...finished"

# Configure AMP if no brooklyn.properties
if ! ssh ${SSH_OPTS} ${USER}@${HOST} "test -f .brooklyn/brooklyn.properties"; then
    ${QUIET} || echo -n "Configuring AMP..."
    ssh ${SSH_OPTS} ${USER}@${HOST} "mkdir -p .brooklyn"
    ssh ${SSH_OPTS} ${USER}@${HOST} "curl -s -o .brooklyn/brooklyn.properties http://brooklyncentral.github.io/use/guide/quickstart/brooklyn.properties"
    ssh ${SSH_OPTS} ${USER}@${HOST} "sed -i.bak 's/^# brooklyn.webconsole.security.provider = brooklyn.rest.security.provider.AnyoneSecurityProvider/brooklyn.webconsole.security.provider = brooklyn.rest.security.provider.AnyoneSecurityProvider/' .brooklyn/brooklyn.properties"
    ssh ${SSH_OPTS} ${USER}@${HOST} "curl -s -o .brooklyn/catalog.xml http://brooklyncentral.github.io/use/guide/quickstart/catalog.xml"
    ${QUIET} || echo "...finished"
fi

# Install example Jars and catalog
if [ "${INSTALL_EXAMPLES}" ]; then
    ${QUIET} || echo -n "Installing examples..."
    # Install required development tools
    ssh ${SSH_OPTS} root@${HOST} "curl -s -o /etc/yum.repos.d/epel-apache-maven.repo http://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo"
    ssh ${SSH_OPTS} root@${HOST} "yum -q -y install apache-maven" > ${LOG} 2>&1
    ssh ${SSH_OPTS} root@${HOST} "yum -q -y install git" > ${LOG} 2>&1
    ssh ${SSH_OPTS} ${USER}@${HOST} "cat >> ~/.bashrc" <<EOF
export M2_HOME=/usr/share/apache-maven
export PATH=\${M}2_HOME/bin:\${PATH}
EOF
    ${QUIET} || echo -n "..."

    # Build and install OpenGamma blueprints
    ssh ${SSH_OPTS} ${USER}@${HOST} "mkdir projects"
    ssh ${SSH_OPTS} ${USER}@${HOST} "git clone https://github.com/cloudsoft/brooklyn-opengamma.git projects/brooklyn-opengamma" > ${LOG} 2>&1
    ssh ${SSH_OPTS} ${USER}@${HOST} "mvn --quiet clean install -f ./projects/brooklyn-opengamma/pom.xml" > ${LOG} 2>&1
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
    ${QUIET} || echo "...finished"
fi

# Run AMP
${QUIET} || echo -n "Starting AMP..."
ssh -n -f ${SSH_OPTS} ${USER}@${HOST} "nohup ./cloudsoft-amp-${AMP_VERSION}/bin/amp launch >> ./cloudsoft-amp-${AMP_VERSION}/amp-console.log 2>&1 &"
${QUIET} || echo "...finished"
echo "Console URL is http://${HOST}:8081/"
