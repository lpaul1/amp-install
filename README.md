Cloudsoft AMP Installation
==========================

The [AMP Getting Started](https://s3-eu-west-1.amazonaws.com/cloudsoft-amp/AMPGettingStarted+2.0.0-M1.pdf)
guide describes the installation of Cloudsoft AMP. The 
[AMP Entities](https://s3-eu-west-1.amazonaws.com/cloudsoft-amp/AMP+Entities+2014-04-09.pdf)
document lists the available entities and applications that are supported.

# AMP Install Script

### Options

* `-e` Install example blueprint files
* `-p` The SSH port to connect to (default 22)
* `-r` Setup random entropy for SSH
* `-s` Create and set up user account
* `-u` Change the AMP username (default 'amp')
* `-k` The private key to use for SSH (default '~/.ssh/id_rsa')
* `-q` Quiet install

### Usage

`amp-install.sh [-q] [-r] [-e] [-s] [-u user] [-k key] hostname`

Installs AMP on the given hostname as 'amp' or the specified
user. Optionally installs example blueprints and creates and
configures the AMP user. Passwordless SSH access as root to
the remote host must be enabled with the given key.

----
Copyright 2014 by Cloudsoft Corporation Limited

Use of this software is subject to the Cloudsoft EULA, provided at:

  http://www.cloudsoftcorp.com/cloudsoft-developer-license

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.
